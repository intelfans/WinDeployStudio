param(
    [string]$GoExe = 'go'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $root 'wds_ext4_builder.exe'

if ($GoExe -eq 'go') {
    $resolved = Get-Command go -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        throw 'Go 1.21 or later is required to rebuild wds_ext4_builder.exe.'
    }
    $GoExe = $resolved.Source
}

$previousCgo = $env:CGO_ENABLED
try {
    $env:CGO_ENABLED = '0'
    Push-Location $root
    & $GoExe build -mod=readonly -trimpath -buildvcs=false -ldflags '-s -w -buildid=' -o $output .
    if ($LASTEXITCODE -ne 0) {
        throw "Go build failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location -ErrorAction SilentlyContinue
    if ($null -eq $previousCgo) {
        Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
    } else {
        $env:CGO_ENABLED = $previousCgo
    }
}
