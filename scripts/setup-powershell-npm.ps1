# One-time setup: allows "npm run dev" in PowerShell without system policy changes.
# Run: powershell -ExecutionPolicy Bypass -File scripts/setup-powershell-npm.ps1

$marker = Join-Path $env:USERPROFILE '.hrms-npm-powershell-fixed'
if (Test-Path $marker) {
    Write-Host 'PowerShell npm fix is already configured.'
    exit 0
}

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE | Out-Null
}

Add-Content -Path $PROFILE -Value @'

# HRMS Plaridel: allow npm/npx in PowerShell (session-only, no admin needed)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
'@

New-Item -ItemType File -Path $marker -Force | Out-Null
Write-Host 'Configured. Close and reopen PowerShell, then run: npm run dev'
