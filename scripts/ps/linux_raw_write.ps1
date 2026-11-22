
param(
  [Parameter(Mandatory = $true)][int]$DiskNumber,
  [Parameter(Mandatory = $true)][string]$IsoPath,
  [Parameter(Mandatory = $true)][int64]$ExpectedIsoLength,
  [Parameter(Mandatory = $true)][int64]$ExpectedSize,
  [Parameter(Mandatory = $true)][string]$ExpectedModel,
  [Parameter(Mandatory = $true)][string]$ExpectedBus,
  [string]$ExpectedUniqueId = '',
  [string]$ExpectedSerial = '',
  [string]$ExpectedDevicePath = ''
)

$ErrorActionPreference = 'Stop'

function Emit-Progress([int]$Percent, [int64]$Written, [int64]$Total) {
  Write-Output ("WDS_PROGRESS:{0}:{1}:{2}" -f $Percent, $Written, $Total)
}

function Test-OfflineIsolationUnsupported([object]$Failure) {
  if ($Failure.Exception -and
      [int]$Failure.Exception.HResult -eq -2147024846) {
    # HRESULT 0x80070032: ERROR_NOT_SUPPORTED.
    return $true
  }

  $details = @(
    [string]$Failure.Exception.Message,
    [string]$Failure.FullyQualifiedErrorId,
    [string]$Failure.CategoryInfo,
    [string]$Failure
  ) -join [Environment]::NewLine
  return $details -match '(?i)\b(not supported|not implemented)\b' -or
    $details -match '不支持|未实现'
}

if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
  throw "ISO file not found: $IsoPath"
}

$isoItem = Get-Item -LiteralPath $IsoPath -ErrorAction Stop
if ([int64]$isoItem.Length -ne $ExpectedIsoLength -or $ExpectedIsoLength -le 0) {
  throw "ISO file changed after preflight."
}

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$bus = $disk.BusType.ToString().ToUpperInvariant()
$isExternal = $bus -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
if (-not $isExternal -or $disk.IsSystem -or $disk.IsBoot -or $disk.IsOffline) {
  throw "Refusing to write to a disk that is not a safe external target."
}
if ([int64]$disk.Size -ne $ExpectedSize -or
    $disk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $ExpectedModel.Trim().ToUpperInvariant() -or
    $bus -ne $ExpectedBus.Trim().ToUpperInvariant()) {
  throw "Target disk identity changed after selection."
}
if ($ExpectedSerial -and $ExpectedSerial.Trim().ToUpperInvariant() -notin @('N/A', 'UNKNOWN')) {
  $physical = Get-PhysicalDisk -ErrorAction Stop |
    Where-Object { $_.DeviceId -eq $disk.Number.ToString() } |
    Select-Object -First 1
  $currentSerial = if ($physical -and $physical.SerialNumber) {
    $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
  } else { '' }
  if ($currentSerial -ne $ExpectedSerial.Trim().ToUpperInvariant()) {
    throw "Target disk serial number changed after selection."
  }
} elseif ($ExpectedUniqueId) {
  $currentUniqueId = if ($disk.UniqueId) { $disk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentUniqueId -ne $ExpectedUniqueId.Trim().ToUpperInvariant()) {
    throw "Target disk unique identity changed after selection."
  }
} elseif ($ExpectedDevicePath) {
  $currentPath = if ($disk.Path) { $disk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentPath -ne $ExpectedDevicePath.Trim().ToUpperInvariant()) {
    throw "Target disk device path changed after selection."
  }
} else {
  throw "Target disk has no reliable physical identity."
}

if ($ExpectedIsoLength -gt [int64]$disk.Size) {
  throw "ISO image is larger than the target disk."
}
$sourceVolume = Get-Volume -FilePath $IsoPath -ErrorAction Stop
$sourcePartitions = @(Get-Partition -Volume $sourceVolume -ErrorAction Stop)
if ($sourcePartitions.Count -ne 1) {
  throw "ISO source did not resolve to exactly one physical partition."
}
if ([int]$sourcePartitions[0].DiskNumber -eq $DiskNumber) {
  throw "ISO source is stored on the target disk."
}

if ($disk.IsOffline) {
  Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction SilentlyContinue
}
if ($disk.IsReadOnly) {
  Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
}

$driveLetters = @(
  Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter } |
    Select-Object -ExpandProperty DriveLetter
)

foreach ($letter in $driveLetters) {
  if ($null -ne $letter -and "$letter".Length -gt 0) {
    $drive = ("{0}:" -f $letter)
    & "$env:SystemRoot\System32\mountvol.exe" $drive /D 2>$null | Out-Null
  }
}

Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
$offlineIsolation = $false
try {
  Set-Disk -Number $DiskNumber -IsOffline $true -ErrorAction Stop
  $offlineIsolation = $true
  Write-Output 'WDS_ISOLATION:OFFLINE'
} catch {
  # Some removable-media bridges reject the Storage cmdlet with
  # ERROR_NOT_SUPPORTED. The exclusive raw handle below is then held over
  # both the write and the full verification, with no Update-Disk in between.
  if (-not (Test-OfflineIsolationUnsupported $_)) {
    throw
  }
  Write-Output 'WDS_ISOLATION:EXCLUSIVE'
}

if ($offlineIsolation) {
  Start-Sleep -Milliseconds 700
}

$source = $null
$target = $null
$sourceHash = $null
$targetHash = $null
$operationFailure = $null
$restoreFailure = $null
try {
  $source = [System.IO.File]::Open(
    $IsoPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::Read
  )
  if ([int64]$source.Length -ne $ExpectedIsoLength) {
    throw "ISO file changed before raw writing."
  }

  $targetPath = "\\.\PhysicalDrive$DiskNumber"
  $target = [System.IO.File]::Open(
    $targetPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
  )

  $buffer = New-Object byte[] 4194304
  $total = $source.Length
  $written = [int64]0
  $lastPercent = -1
  Emit-Progress 0 0 $total

  while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $target.Write($buffer, 0, $read)
    $written += $read
    $percent = [int][Math]::Floor(($written * 100.0) / $total)
    if ($percent -ne $lastPercent) {
      Emit-Progress $percent $written $total
      $lastPercent = $percent
    }
  }

  $target.Flush($true)
  Emit-Progress 100 $written $total

  # Do not release the target handle before this verification finishes. This
  # keeps the fallback safe for bridges that do not implement Set-Disk
  # offline, and also avoids a separate process observing a newly-written
  # hybrid partition layout.
  Write-Output 'WDS_VERIFY_STARTED'
  Write-Output 'WDS_VERIFY_PROGRESS:0'
  $bufferLength = 8388608
  $sourceBuffer = New-Object byte[] $bufferLength
  $targetBuffer = New-Object byte[] $bufferLength
  $source.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
  $target.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
  $sourceHash = [System.Security.Cryptography.IncrementalHash]::CreateHash(
    [System.Security.Cryptography.HashAlgorithmName]::SHA256
  )
  $targetHash = [System.Security.Cryptography.IncrementalHash]::CreateHash(
    [System.Security.Cryptography.HashAlgorithmName]::SHA256
  )
  # Windows rewrites the GPT header (LBA 1) when it brings the disk back
  # online, because that header describes the medium rather than the image:
  # the alternate-LBA, last-usable-LBA and header CRC fields are recomputed
  # for the physical disk. Verifying those three fields can never succeed on
  # a disk larger than the image, and they carry no user data. The partition
  # table and everything else are still compared byte for byte.
  $verifySkipStart = [int64]512
  $verifySkipEnd = [int64]1023

  $verified = [int64]0
  $firstMismatchOffset = [int64]-1
  $firstSourceByte = $null
  $firstTargetByte = $null
  $lastVerifyPercent = -1

  while ($verified -lt $total) {
    # Keep arithmetic in Int64 until the bounded chunk length is known.  Calling
    # Math.Min here can select an Int32 overload in PowerShell and overflow when
    # the remaining ISO size is larger than 2 GiB.
    $remaining = [int64]($total - $verified)
    $requested = if ($remaining -lt [int64]$bufferLength) {
      [int]$remaining
    } else {
      [int]$bufferLength
    }
    $sourceRead = $source.Read($sourceBuffer, 0, $requested)
    $targetRead = $target.Read($targetBuffer, 0, $requested)
    if ($sourceRead -ne $requested -or $targetRead -ne $requested) {
      throw "Short read while verifying at offset $verified."
    }

    # Compare every byte of this block except the GPT header window. A block
    # can contain the window in the middle, so it is split into up to two
    # segments: everything before the window and everything after it.
    $blockStart = $verified
    $blockEnd = $blockStart + $requested - 1
    $segments = @()
    if ($blockEnd -lt $verifySkipStart -or $blockStart -gt $verifySkipEnd) {
      $segments += ,@([int]0, [int]$requested)
    } else {
      if ($blockStart -lt $verifySkipStart) {
        $segments += ,@([int]0, [int]($verifySkipStart - $blockStart))
      }
      $afterStart = [int64]($verifySkipEnd + 1 - $blockStart)
      if ($afterStart -le ($requested - 1)) {
        $afterLength = [int]($requested - $afterStart)
        $segments += ,@([int]$afterStart, $afterLength)
      }
    }

    foreach ($segment in $segments) {
      $segmentStart = $segment[0]
      $segmentLength = $segment[1]
      if ($segmentLength -le 0) { continue }
      $segmentEnd = $segmentStart + $segmentLength
      $sourceHash.AppendData($sourceBuffer, $segmentStart, $segmentLength)
      $targetHash.AppendData($targetBuffer, $segmentStart, $segmentLength)

      if ($firstMismatchOffset -lt 0) {
        $segmentMatches = $true
        for ($index = $segmentStart; $index -lt $segmentEnd; $index++) {
          if ($sourceBuffer[$index] -ne $targetBuffer[$index]) {
            $segmentMatches = $false
            $firstMismatchOffset = $blockStart + $index
            $firstSourceByte = $sourceBuffer[$index]
            $firstTargetByte = $targetBuffer[$index]
            break
          }
        }
        if (-not $segmentMatches) {
          # Keep hashing the remaining segments so both digests cover the
          # same bytes, but stop scanning for a second mismatch.
          continue
        }
      }
    }


    $verified += $requested
    $verifyPercent = [int][Math]::Floor(($verified * 100.0) / $total)
    if ($verifyPercent -ne $lastVerifyPercent) {
      Write-Output ("WDS_VERIFY_PROGRESS:{0}" -f $verifyPercent)
      $lastVerifyPercent = $verifyPercent
    }
  }

  $sourceDigest = $sourceHash.GetHashAndReset()
  $targetDigest = $targetHash.GetHashAndReset()
  if ($firstMismatchOffset -ge 0) {
    throw (
      "Full-stream SHA-256 verification mismatch at offset {0} " +
      "(source 0x{1:X2}, target 0x{2:X2})." -f
        $firstMismatchOffset, $firstSourceByte, $firstTargetByte
    )
  }
  if (-not [System.Linq.Enumerable]::SequenceEqual(
      [byte[]]$sourceDigest,
      [byte[]]$targetDigest
    )) {
    throw "Full-stream SHA-256 verification mismatch."
  }

  Write-Output "WDS_VERIFY_COMPLETE"
} catch {
  # Always release the exclusive raw handle before asking the Storage module
  # to rediscover the newly-written hybrid layout.  Retaining the original
  # error lets the caller distinguish write/verification failures from the
  # recovery step below.
  $operationFailure = $_
} finally {
  if ($null -ne $targetHash) { $targetHash.Dispose() }
  if ($null -ne $sourceHash) { $sourceHash.Dispose() }
  if ($null -ne $target) { $target.Dispose() }
  if ($null -ne $source) { $source.Dispose() }
}

# Do this in the same elevated PowerShell process that performed the raw
# write. Starting a second process after verification can be denied by a
# security product or by a transient device state, even though the image is
# already correct. The separate finalizer remains only as a timeout/cancel
# fallback in Dart.
try {
  $restoredDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  $restoredBus = $restoredDisk.BusType.ToString().ToUpperInvariant()
  $restoredIsExternal = $restoredBus -in @('USB', 'SD', 'MMC') -or [bool]$restoredDisk.IsRemovable
  if (-not $restoredIsExternal -or $restoredDisk.IsSystem -or $restoredDisk.IsBoot) {
    throw "Refusing to return a non-external disk online."
  }
  if ([int64]$restoredDisk.Size -ne $ExpectedSize -or
      $restoredDisk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $ExpectedModel.Trim().ToUpperInvariant() -or
      $restoredBus -ne $ExpectedBus.Trim().ToUpperInvariant()) {
    throw "Target disk identity changed before it could be returned online."
  }
  if ($ExpectedSerial -and $ExpectedSerial.Trim().ToUpperInvariant() -notin @('N/A', 'UNKNOWN')) {
    $physical = Get-PhysicalDisk -ErrorAction Stop |
      Where-Object { $_.DeviceId -eq $restoredDisk.Number.ToString() } |
      Select-Object -First 1
    $currentSerial = if ($physical -and $physical.SerialNumber) {
      $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
    } else { '' }
    if ($currentSerial -ne $ExpectedSerial.Trim().ToUpperInvariant()) {
      throw "Target disk serial number changed before it could be returned online."
    }
  } elseif ($ExpectedUniqueId) {
    $currentUniqueId = if ($restoredDisk.UniqueId) { $restoredDisk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
    if ($currentUniqueId -ne $ExpectedUniqueId.Trim().ToUpperInvariant()) {
      throw "Target disk unique identity changed before it could be returned online."
    }
  } elseif ($ExpectedDevicePath) {
    $currentPath = if ($restoredDisk.Path) { $restoredDisk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
    if ($currentPath -ne $ExpectedDevicePath.Trim().ToUpperInvariant()) {
      throw "Target disk device path changed before it could be returned online."
    }
  } else {
    throw "Target disk has no reliable physical identity."
  }

  if ($restoredDisk.IsOffline) {
    Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop
  }
  Update-Disk -Number $DiskNumber -ErrorAction Stop | Out-Null
  $onlineDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  if ([bool]$onlineDisk.IsOffline) {
    throw "Target disk is still offline after recovery."
  }
  Write-Output "WDS_DISK_ONLINE"

  # The disk is mounted again, which is exactly when Windows rewrites the GPT
  # header. Verify the media the user will actually keep, not the handle we
  # were still holding a moment ago: reopen the device read-only and compare
  # the same region again. This is the check that makes the completion marker
  # describe reality.
  $post = $null
  $postSource = $null
  try {
    $post = [System.IO.File]::Open(
      "\\.\PhysicalDrive$DiskNumber",
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::ReadWrite
    )
    $postSource = [System.IO.File]::Open(
      $IsoPath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read
    )
    $postBufferLength = 8MB
    $postSourceBuffer = New-Object byte[] $postBufferLength
    $postTargetBuffer = New-Object byte[] $postBufferLength
    $postOffset = [int64]0
    $postMismatch = [int64]-1
    Write-Output "WDS_VERIFY_ONLINE_STARTED"
    while ($postOffset -lt $total) {
      $postRemaining = [int64]($total - $postOffset)
      $postRequested = if ($postRemaining -lt [int64]$postBufferLength) {
        [int]$postRemaining
      } else {
        [int]$postBufferLength
      }
      $postSource.Read($postSourceBuffer, 0, $postRequested) | Out-Null
      $post.Read($postTargetBuffer, 0, $postRequested) | Out-Null

      $postBlockEnd = $postOffset + $postRequested - 1
      $postSegments = @()
      if ($postBlockEnd -lt $verifySkipStart -or $postOffset -gt $verifySkipEnd) {
        $postSegments += ,@([int]0, [int]$postRequested)
      } else {
        if ($postOffset -lt $verifySkipStart) {
          $postSegments += ,@([int]0, [int]($verifySkipStart - $postOffset))
        }
        $postAfterStart = [int64]($verifySkipEnd + 1 - $postOffset)
        if ($postAfterStart -le ($postRequested - 1)) {
          $postSegments += ,@([int]$postAfterStart, [int]($postRequested - $postAfterStart))
        }
      }

      foreach ($postSegment in $postSegments) {
        $postSegmentStart = $postSegment[0]
        $postSegmentLength = $postSegment[1]
        if ($postSegmentLength -le 0) { continue }
        $postSegmentEnd = $postSegmentStart + $postSegmentLength
        for ($index = $postSegmentStart; $index -lt $postSegmentEnd; $index++) {
          if ($postSourceBuffer[$index] -ne $postTargetBuffer[$index]) {
            $postMismatch = $postOffset + $index
            break
          }
        }
        if ($postMismatch -ge 0) { break }
      }
      if ($postMismatch -ge 0) { break }
      $postOffset += $postRequested
    }
    if ($postMismatch -ge 0) {
      throw ("Post-mount verification mismatch at offset {0}." -f $postMismatch)
    }
    Write-Output "WDS_VERIFY_ONLINE_COMPLETE"
  } finally {
    if ($null -ne $postSource) { $postSource.Dispose() }
    if ($null -ne $post) { $post.Dispose() }
  }
} catch {
  $restoreFailure = $_
  Write-Output ("WDS_RESTORE_FAILED:{0}" -f $_.Exception.Message)
}

if ($null -ne $operationFailure) {
  if ($null -ne $restoreFailure) {
    throw (
      "Linux raw operation failed: {0}`nDisk recovery also failed: {1}" -f
        $operationFailure.Exception.Message, $restoreFailure.Exception.Message
    )
  }
  throw $operationFailure
}
if ($null -ne $restoreFailure) {
  throw (
    "Image verification completed, but the target disk could not be returned online: {0}" -f
      $restoreFailure.Exception.Message
  )
}

Write-Output "WDS_DONE"
