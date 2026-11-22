<#
.SYNOPSIS
  Executes the app's Linux raw-write PowerShell script against a real USB disk.

.DESCRIPTION
  The .ps1 body is extracted verbatim from
  lib/core/services/bootable_usb_service.dart (_linuxRawWriteScript), so this
  exercises the exact text the application runs - not a re-implementation.

  Safety gates, checked before any write:
    - the target must be an external (USB/SD/MMC) disk
    - it must not be the system or boot disk
    - size, model, bus and serial must match the values captured here
    - the image must be smaller than the disk
    - the caller must confirm with the exact word ERASE

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/linux_raw_write_hw_test.ps1 `
      -IsoPath 'D:\Dev\Linux\Custom Linux.iso' -DiskNumber 1 -Confirm ERASE
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $IsoPath,
    [Parameter(Mandatory = $true)][int] $DiskNumber,
    [Parameter(Mandatory = $true)][string] $Confirm,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

if ($Confirm -ne 'ERASE') {
    throw "Refusing to run: pass -Confirm ERASE to acknowledge the disk will be wiped."
}

$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $DryRun -and -not $isElevated) {
    throw 'This harness must run elevated: the raw write opens \\.\PhysicalDriveN exclusively.'
}

$scriptPath = Join-Path $PSScriptRoot 'ps\linux_raw_write.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing extracted script: $scriptPath (regenerate it with the extractor)."
}

if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }
$iso = Get-Item -LiteralPath $IsoPath

Write-Host ''
Write-Host '=== Target validation ===' -ForegroundColor Cyan
$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$bus = $disk.BusType.ToString().ToUpperInvariant()
$isExternal = $bus -in @('USB','SD','MMC') -or [bool]$disk.IsRemovable

[PSCustomObject]@{
    DiskNumber = $disk.Number
    Model      = $disk.FriendlyName
    Serial     = $disk.SerialNumber
    Bus        = $bus
    SizeBytes  = $disk.Size
    IsSystem   = $disk.IsSystem
    IsBoot     = $disk.IsBoot
    External   = $isExternal
    ImageBytes = $iso.Length
} | Format-List | Out-String | Write-Host

if (-not $isExternal) { throw 'Target is not an external disk.' }
if ($disk.IsSystem) { throw 'Target is the system disk.' }
if ($disk.IsBoot) { throw 'Target is the boot disk.' }
if ($iso.Length -ge $disk.Size) { throw 'Image does not fit on the target disk.' }

# Reuse the app's own byte-for-byte image digest so the harness output can be
# compared with an independent read of the disk afterwards.
Write-Host '=== Hashing the image (this is the reference digest) ===' -ForegroundColor Cyan
# The application compares the media but skips the GPT header window
# (bytes 512..1023), because Windows rewrites those fields when the disk
# comes back online. The reference digest below uses the same window.
$skipStart = [int64]512
$skipEnd   = [int64]1023

function Get-WindowDigest([System.IO.Stream] $Stream, [int64] $Length) {
    $incremental = [System.Security.Cryptography.IncrementalHash]::CreateHash(
        [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $buffer = New-Object byte[] 8388608
    $offset = [int64]0
    while ($offset -lt $Length) {
        $remaining = [int64]($Length - $offset)
        $want = if ($remaining -lt [int64]$buffer.Length) { [int]$remaining } else { [int]$buffer.Length }
        $read = $Stream.Read($buffer, 0, $want)
        if ($read -le 0) { throw 'Short read while computing the reference digest.' }
        $blockEnd = $offset + $read - 1
        $segments = @()
        if ($blockEnd -lt $skipStart -or $offset -gt $skipEnd) {
            $segments += ,@([int]0, [int]$read)
        } else {
            if ($offset -lt $skipStart) { $segments += ,@([int]0, [int]($skipStart - $offset)) }
            $afterStart = [int64]($skipEnd + 1 - $offset)
            if ($afterStart -le ($read - 1)) {
                $segments += ,@([int]$afterStart, [int]($read - $afterStart))
            }
        }
        foreach ($segment in $segments) {
            if ($segment[1] -gt 0) { $incremental.AppendData($buffer, $segment[0], $segment[1]) }
        }
        $offset += $read
    }
    $digest = [System.BitConverter]::ToString($incremental.GetHashAndReset()).Replace('-','')
    $incremental.Dispose()
    return $digest
}

$sourceStream = [System.IO.File]::Open($IsoPath, 'Open', 'Read', 'Read')
try {
    $sourceDigest = Get-WindowDigest -Stream $sourceStream -Length $iso.Length
} finally {
    $sourceStream.Dispose()
}
Write-Host "source SHA-256 : $sourceDigest"

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

if ($DryRun) {
    Write-Host ''
    Write-Host '=== Dry run: validation passed, the write was not performed ===' -ForegroundColor Yellow
    Write-Host "would write $($iso.Length) bytes to disk $($disk.Number) ($($disk.FriendlyName))"
    exit 0
}

Write-Host '=== Running the application raw-write script ===' -ForegroundColor Cyan
$output = & $scriptPath `
    -DiskNumber $disk.Number `
    -IsoPath $iso.FullName `
    -ExpectedIsoLength $iso.Length `
    -ExpectedSize $disk.Size `
    -ExpectedModel $disk.FriendlyName `
    -ExpectedBus $bus `
    -ExpectedUniqueId '' `
    -ExpectedSerial $disk.SerialNumber `
    -ExpectedDevicePath '' 2>&1

$exit = $LASTEXITCODE
$stopwatch.Stop()

Write-Host ''
Write-Host '=== Script markers ===' -ForegroundColor Cyan
$markers = $output | Where-Object { "$_" -match '^WDS_' }
$markers | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" }

$failed = $output | Where-Object { "$_" -match 'Exception|Error|mismatch|Refusing|failed' }
if ($failed) {
    Write-Host ''
    Write-Host '=== Failure detail ===' -ForegroundColor Red
    $failed | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
}

Write-Host ''
Write-Host '=== Result ===' -ForegroundColor Cyan
Write-Host "exit code      : $exit"
Write-Host "elapsed        : $([math]::Round($stopwatch.Elapsed.TotalSeconds,1)) s"
Write-Host "verify complete: $([bool]($markers -contains 'WDS_VERIFY_COMPLETE'))"
Write-Host "disk online    : $([bool]($markers -contains 'WDS_DISK_ONLINE'))"
Write-Host "done marker    : $([bool]($markers -contains 'WDS_DONE'))"

# Independent confirmation: read the disk back and compare with the image.
Write-Host ''
Write-Host '=== Independent read-back of the written region ===' -ForegroundColor Cyan
$target = [System.IO.File]::Open("\\.\PhysicalDrive$($disk.Number)", 'Open', 'Read', 'ReadWrite')
try {
    $targetDigest = Get-WindowDigest -Stream $target -Length $iso.Length
} finally {
    $target.Dispose()
}

$match = ($targetDigest -eq $sourceDigest)
Write-Host "image SHA-256  : $sourceDigest"
Write-Host "disk  SHA-256  : $targetDigest"
if ($match) {
    Write-Host 'VERDICT: the bytes on the disk equal the image (GPT header excluded).' -ForegroundColor Green
} else {
    Write-Host 'VERDICT: mismatch - the write did not reproduce the image.' -ForegroundColor Red
    Write-Host '         (both sides used the same GPT header exclusion)'
    exit 2
}

if ($exit -ne 0) { exit $exit }