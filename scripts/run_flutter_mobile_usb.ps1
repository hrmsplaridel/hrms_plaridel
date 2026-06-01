# Run the app on a USB-connected Android device using adb reverse (no LAN/firewall needed).
# Requires: backend on this PC (npm start in backend/), phone USB debugging on.
#
# Usage (from repo root):
#   .\scripts\run_flutter_mobile_usb.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$frontendRoot = Join-Path $repoRoot 'frontend'

$adbCandidates = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
)
$adb = $adbCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $adb) {
    Write-Error "adb not found. Install Android SDK platform-tools or set ANDROID_HOME."
}

Write-Host "Setting up adb reverse: phone 127.0.0.1:3000 -> PC localhost:3000"
& $adb reverse tcp:3000 tcp:3000
if ($LASTEXITCODE -ne 0) {
    Write-Error "adb reverse failed. Is the phone connected with USB debugging enabled?"
}

Set-Location $frontendRoot
Write-Host "Starting Flutter (API_BASE_URL=http://127.0.0.1:3000)..."
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000 @args
