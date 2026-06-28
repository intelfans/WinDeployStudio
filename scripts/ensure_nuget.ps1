# Ensures nuget.exe is available for Flutter Windows native asset builds.
# The local fallback keeps the project buildable even when Visual Studio did not install NuGet.

param(
    [switch]$AddToUserPath
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $repoRoot ".tools\nuget"
$localNuget = Join-Path $toolsDir "nuget.exe"
$nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"

function Add-ToProcessPath {
    param([string]$PathToAdd)

    $entries = @($env:Path -split ";" | Where-Object { $_ })
    if ($entries -notcontains $PathToAdd) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Add-ToUserPath {
    param([string]$PathToAdd)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($userPath -split ";" | Where-Object { $_ })
    if ($entries -notcontains $PathToAdd) {
        $newPath = (@($entries) + $PathToAdd) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added NuGet fallback to user PATH: $PathToAdd" -ForegroundColor Green
    }
}

function Send-EnvironmentChanged {
    $signature = @"
using System;
using System.Runtime.InteropServices;

public static class EnvironmentBroadcaster {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult);
}
"@

    if (-not ("EnvironmentBroadcaster" -as [type])) {
        Add-Type -TypeDefinition $signature
    }

    $result = [UIntPtr]::Zero
    [EnvironmentBroadcaster]::SendMessageTimeout(
        [IntPtr]0xffff,
        0x001A,
        [UIntPtr]::Zero,
        "Environment",
        0x0002,
        5000,
        [ref]$result
    ) | Out-Null
}

$existingNuget = Get-Command nuget.exe -ErrorAction SilentlyContinue
if ($existingNuget) {
    Write-Host "NuGet found: $($existingNuget.Source)" -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $localNuget)) {
    Write-Host "NuGet not found in PATH. Downloading local fallback..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

    $tmpFile = "$localNuget.download"
    if (Test-Path $tmpFile) {
        Remove-Item -Force $tmpFile
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $nugetUrl -OutFile $tmpFile

    $signature = Get-AuthenticodeSignature $tmpFile
    if ($signature.Status -ne "Valid") {
        Remove-Item -Force $tmpFile
        throw "Downloaded nuget.exe has an invalid Authenticode signature: $($signature.Status)"
    }

    Move-Item -Force $tmpFile $localNuget
}

Add-ToProcessPath -PathToAdd $toolsDir

if ($AddToUserPath) {
    Add-ToUserPath -PathToAdd $toolsDir
    Send-EnvironmentChanged
}

$resolvedNuget = Get-Command nuget.exe -ErrorAction Stop
& $resolvedNuget.Source help | Out-Null
Write-Host "NuGet ready: $($resolvedNuget.Source)" -ForegroundColor Green
