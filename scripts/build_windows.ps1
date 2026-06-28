# Build WinDeploy Studio Windows release without creating an installer.
# Requires: Flutter SDK. NuGet is bootstrapped automatically if missing.

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Building WinDeploy Studio Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[0/3] Ensuring NuGet is available..." -ForegroundColor Yellow
& "$PSScriptRoot\ensure_nuget.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  NuGet setup failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

Write-Host "[1/3] Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Failed to get dependencies!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

Write-Host "[2/3] Running analysis..." -ForegroundColor Yellow
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Analysis failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

Write-Host "[3/3] Building Windows release..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

Write-Host ""
Write-Host "Build output: build\windows\x64\runner\Release\win_deploy_studio.exe" -ForegroundColor Cyan
