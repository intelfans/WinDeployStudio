# Build WinDeploy Studio Installer
# Requires: Inno Setup 6 or 7, Flutter SDK, Visual Studio with the C++ workload.

$ErrorActionPreference = "Stop"

# Anchor every path to the repository root. All later Remove-Item calls are
# destructive; resolving them against the caller's working directory deleted
# an unrelated tree when the script was invoked from another folder.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

$version = (Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') -Pattern '^version:\s*(\S+)' |
    Select-Object -First 1).Matches[0].Groups[1].Value
if (-not $version) { throw 'Could not read the version from pubspec.yaml.' }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Building WinDeploy Studio $version Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Removes a directory only when it really is inside the repository.
function Remove-BuildDirectory {
    param([Parameter(Mandatory = $true)][string] $RelativePath)

    $target = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $RelativePath))
    $root = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'
    if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete outside the repository: $target"
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

# Step 0: Ensure NuGet for Flutter Windows native assets
Write-Host "[0/5] Ensuring NuGet is available..." -ForegroundColor Yellow
& "$PSScriptRoot\ensure_nuget.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  NuGet setup failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

# Step 1: Clean previous build output
Write-Host "[1/5] Cleaning previous build..." -ForegroundColor Yellow
Remove-BuildDirectory "build\windows\x64\runner\Release"
Remove-BuildDirectory "dist\windows"
Write-Host "  Done!" -ForegroundColor Green

# Step 2: Get dependencies
Write-Host "[2/5] Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Failed to get dependencies!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

# Step 3: Static analysis
Write-Host "[3/5] Running analysis..." -ForegroundColor Yellow
flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Analysis failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

# Step 3b: Tests. Shipping a release without them let regressions reach users.
Write-Host "[3/5] Running tests..." -ForegroundColor Yellow
flutter test --no-pub
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Tests failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

# Step 3c: Drop a CMake cache that points at a toolchain that no longer exists.
# Reinstalling or relocating Visual Studio leaves the cached generator instance
# behind, and CMake then fails with "could not find specified instance".
$cmakeCache = Join-Path $repoRoot "build\windows\x64\CMakeCache.txt"
if (Test-Path -LiteralPath $cmakeCache) {
    $instanceLine = Get-Content -LiteralPath $cmakeCache |
        Where-Object { $_ -like 'CMAKE_GENERATOR_INSTANCE:INTERNAL=*' } |
        Select-Object -First 1
    if ($instanceLine) {
        $cachedInstance = ($instanceLine -split '=', 2)[1].Trim()
        if ($cachedInstance -and -not (Test-Path -LiteralPath $cachedInstance)) {
            Write-Host "  Stale CMake cache points at '$cachedInstance'; removing build\windows." -ForegroundColor Yellow
            Remove-BuildDirectory "build\windows"
        }
    }
}

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

$possiblePaths = @(
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)

$isccPath = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $isccPath = $path
        break
    }
}
if (-not $isccPath) {
    $isccPath = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
}
if (-not $isccPath) {
    Write-Host "  Inno Setup not found! Please install Inno Setup 6 or 7." -ForegroundColor Red
    Write-Host "  Download from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    exit 1
}

New-Item -ItemType Directory -Path (Join-Path $repoRoot 'dist\windows') -Force | Out-Null

& $isccPath (Join-Path $repoRoot 'installer\windows\WinDeployStudio.iss')
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installer creation failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  Done!" -ForegroundColor Green

$installer = Join-Path $repoRoot "dist\windows\WinDeployStudio_Setup_$version.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host "  Expected installer was not produced: $installer" -ForegroundColor Red
    exit 1
}
$item = Get-Item -LiteralPath $installer
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Installer : $($item.FullName)" -ForegroundColor Cyan
Write-Host "Version   : $version" -ForegroundColor Cyan
Write-Host ("Size      : {0:N2} MB" -f ($item.Length / 1MB)) -ForegroundColor Cyan
Write-Host "SHA-256   : $hash" -ForegroundColor Cyan
Write-Host ""
