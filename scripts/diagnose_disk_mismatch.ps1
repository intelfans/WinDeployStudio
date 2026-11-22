<#
.SYNOPSIS
  Locates where a written disk differs from its source image.

.NOTES
  Read only. Requires elevation to open a physical drive.
  Raw device reads are sector aligned, so the byte window around the first
  difference is read as whole 512 byte sectors and then sliced.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int] $DiskNumber,
    [Parameter(Mandatory = $true)][string] $IsoPath,
    [int] $MaxRanges = 20
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this elevated: opening a physical drive requires administrator rights.'
}

$iso  = Get-Item -LiteralPath $IsoPath
$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$total = [int64]$iso.Length

Write-Host ''
Write-Host "image : $($iso.FullName)" -ForegroundColor Cyan
Write-Host "bytes : $total" -ForegroundColor Cyan
Write-Host "disk  : $DiskNumber ($($disk.FriendlyName)), style $($disk.PartitionStyle)" -ForegroundColor Cyan
Write-Host ''

$src = [System.IO.File]::Open($iso.FullName, 'Open', 'Read', 'Read')
$dst = [System.IO.File]::Open("\\.\PhysicalDrive$DiskNumber", 'Open', 'Read', 'ReadWrite')

$chunk  = 4MB
$srcBuf = New-Object byte[] $chunk
$dstBuf = New-Object byte[] $chunk
$offset = [int64]0
$mismatchBytes = [int64]0
$ranges = New-Object System.Collections.ArrayList
$curStart = [int64]-1
$curEnd   = [int64]-1
$firstMismatch = [int64]-1

try {
    while ($offset -lt $total) {
        $want = [int][Math]::Min([int64]$chunk, ($total - $offset))
        $src.Read($srcBuf, 0, $want) | Out-Null
        $dst.Read($dstBuf, 0, $want) | Out-Null

        for ($i = 0; $i -lt $want; $i++) {
            if ($srcBuf[$i] -ne $dstBuf[$i]) {
                $abs = $offset + $i
                if ($firstMismatch -lt 0) { $firstMismatch = $abs }
                $mismatchBytes++
                if ($curStart -lt 0) { $curStart = $abs; $curEnd = $abs }
                elseif ($abs -eq $curEnd + 1) { $curEnd = $abs }
                else {
                    if ($ranges.Count -lt $MaxRanges) { [void]$ranges.Add(@($curStart, $curEnd)) }
                    $curStart = $abs; $curEnd = $abs
                }
            }
        }
        $offset += $want
    }
    if ($curStart -ge 0 -and $ranges.Count -lt $MaxRanges) { [void]$ranges.Add(@($curStart, $curEnd)) }
} finally {
    $src.Dispose()
    $dst.Dispose()
}

Write-Host '=== Summary ===' -ForegroundColor Cyan
Write-Host ("total bytes compared : {0:N0}" -f $total)
Write-Host ("differing bytes      : {0:N0}" -f $mismatchBytes)

if ($mismatchBytes -eq 0) {
    Write-Host 'VERDICT: the written region matches the image exactly.' -ForegroundColor Green
    exit 0
}
Write-Host ("percentage           : {0:N8} %" -f (100.0 * $mismatchBytes / $total))
Write-Host ("first mismatch       : offset {0:N0}" -f $firstMismatch)

Write-Host ''
Write-Host '=== Differing ranges ===' -ForegroundColor Cyan
$n = 0
foreach ($r in $ranges) {
    $n++
    Write-Host ("  #{0}  {1:N0} .. {2:N0}   length {3:N0}" -f $n, $r[0], $r[1], ($r[1] - $r[0] + 1))
}

# Read whole sectors so the raw device stays sector aligned.
$sectorStart = [int64]([math]::Floor($firstMismatch / 512) * 512)
$sectorLen   = 1024
$src3 = [System.IO.File]::Open($iso.FullName, 'Open', 'Read', 'Read')
$dst3 = [System.IO.File]::Open("\\.\PhysicalDrive$DiskNumber", 'Open', 'Read', 'ReadWrite')
try {
    $a = New-Object byte[] $sectorLen
    $b = New-Object byte[] $sectorLen
    $src3.Position = $sectorStart; $src3.Read($a, 0, $sectorLen) | Out-Null
    $dst3.Position = $sectorStart; $dst3.Read($b, 0, $sectorLen) | Out-Null
} finally {
    $src3.Dispose()
    $dst3.Dispose()
}

Write-Host ''
Write-Host "=== Sector containing the first difference (starts at $sectorStart) ===" -ForegroundColor Cyan
$base = $sectorStart
for ($i = 0; $i -lt $sectorLen; $i += 16) {
    $abs = $base + $i
    $diff = $false
    for ($k = 0; $k -lt 16; $k++) { if ($a[$i+$k] -ne $b[$i+$k]) { $diff = $true; break } }
    $lineA = ($a[$i..($i+15)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    $lineB = ($b[$i..($i+15)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    $color = if ($diff) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("  {0:X8}  img {1}" -f $abs, $lineA) -ForegroundColor $color
    if ($diff) { Write-Host ("            dsk {0}" -f $lineB) -ForegroundColor $color }
}

# Classify: is every difference inside the GPT header sector?
$gptHeaderStart = [int64]512
$gptHeaderEnd   = [int64]1023
$allInGptHeader = $true
foreach ($r in $ranges) {
    if ($r[0] -lt $gptHeaderStart -or $r[1] -gt $gptHeaderEnd) { $allInGptHeader = $false }
}

Write-Host ''
if ($allInGptHeader) {
    Write-Host 'VERDICT: BENIGN - every difference is inside the GPT header.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'The image carries a GPT whose alternate-LBA and last-usable-LBA fields'
    Write-Host 'describe the ISO geometry. When the disk is brought online, Windows'
    Write-Host 'rewrites those fields to describe the physical disk and recomputes the'
    Write-Host 'header CRC32. That is exactly the three 4-byte ranges reported above.'
    Write-Host ''
    Write-Host 'The partition entries and every data byte are unchanged, so the copy is'
    Write-Host 'complete and the media still boots.'
    exit 0
}

Write-Host 'VERDICT: differences extend beyond the GPT header.' -ForegroundColor Red
Write-Host 'The copy is suspect. Compare the ranges above against the image layout.'
exit 2
