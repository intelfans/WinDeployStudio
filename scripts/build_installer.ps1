# Build WinDeploy Studio Installer
# Requires: Inno Setup 6, Flutter SDK

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Building WinDeploy Studio Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Clean previous build
Write-Host "[1/5] Cleaning previous build..." -ForegroundColor Yellow
if (Test-Path "build\windows\x64\runner\Release") {
    Remove-Item -Recurse -Force "build\windows\x64\runner\Release"
}
if (Test-Path "dist\windows") {
    Remove-Item -Recurse -Force "dist\windows"
}
Write-Host "  Done!" -ForegroundColor Green

# Step 2: Get dependencies
Write-Host "[2/5] Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Failed to get dependencies!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

# Step 3: Run analysis
Write-Host "[3/5] Running analysis..." -ForegroundColor Yellow
flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Analysis failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

# Step 4: Build Windows release
Write-Host "[4/5] Building Windows release..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

# Step 5: Create installer with Inno Setup
Write-Host "[5/5] Creating installer..." -ForegroundColor Yellow

# Check for Inno Setup
$possiblePaths = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
)

$isccPath = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $isccPath = $path
        break
    }
}

if (-not $isccPath) {
    # Try PATH
    $isccPath = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
}
if (-not $isccPath) {
    Write-Host "  Inno Setup not found! Please install Inno Setup 6 or 7." -ForegroundColor Red
    Write-Host "  Download from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    exit 1
}

# Create dist directory
New-Item -ItemType Directory -Path "dist\windows" -Force | Out-Null

# Run Inno Setup
& $isccPath "installer\windows\WinDeployStudio.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installer creation failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Installer location: dist\windows\WinDeployStudio_Setup_1.0.3.exe" -ForegroundColor Cyan
Write-Host ""

# Open output directory
explorer "dist\windows"
