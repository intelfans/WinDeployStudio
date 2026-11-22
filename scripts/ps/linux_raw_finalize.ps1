
param(
  [Parameter(Mandatory = $true)][int]$DiskNumber,
  [Parameter(Mandatory = $true)][int64]$ExpectedSize,
  [Parameter(Mandatory = $true)][string]$ExpectedModel,
  [Parameter(Mandatory = $true)][string]$ExpectedBus,
  [string]$ExpectedSerial = '',
  [string]$ExpectedDevicePath = '',
  [string]$ExpectedUniqueId = ''
)

$ErrorActionPreference = 'Stop'

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$bus = $disk.BusType.ToString().ToUpperInvariant()
$isExternal = $bus -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
if (-not $isExternal -or $disk.IsSystem -or $disk.IsBoot) {
  throw "Refusing to return a non-external disk online."
}
if ([int64]$disk.Size -ne $ExpectedSize -or
    $disk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $ExpectedModel.Trim().ToUpperInvariant() -or
    $bus -ne $ExpectedBus.Trim().ToUpperInvariant()) {
  throw "Target disk identity changed before it could be returned online."
}
if ($ExpectedSerial -and $ExpectedSerial.Trim().ToUpperInvariant() -notin @('N/A', 'UNKNOWN')) {
  $physical = Get-PhysicalDisk -ErrorAction Stop |
    Where-Object { $_.DeviceId -eq $disk.Number.ToString() } |
    Select-Object -First 1
  $currentSerial = if ($physical -and $physical.SerialNumber) {
    $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
  } else { '' }
  if ($currentSerial -ne $ExpectedSerial.Trim().ToUpperInvariant()) {
    throw "Target disk serial number changed before it could be returned online."
  }
} elseif ($ExpectedUniqueId) {
  $currentUniqueId = if ($disk.UniqueId) { $disk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentUniqueId -ne $ExpectedUniqueId.Trim().ToUpperInvariant()) {
    throw "Target disk unique identity changed before it could be returned online."
  }
} elseif ($ExpectedDevicePath) {
  $currentPath = if ($disk.Path) { $disk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentPath -ne $ExpectedDevicePath.Trim().ToUpperInvariant()) {
    throw "Target disk device path changed before it could be returned online."
  }
} else {
  throw "Target disk has no reliable physical identity."
}

if ($disk.IsOffline) {
  Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop
}
Update-Disk -Number $DiskNumber -ErrorAction Stop | Out-Null
Write-Output "WDS_DISK_ONLINE"
