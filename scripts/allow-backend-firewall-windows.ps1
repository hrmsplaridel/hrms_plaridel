# Allow inbound TCP 3000 so phones on the same LAN can reach the HRMS backend.
# Run in PowerShell as Administrator:
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\scripts\allow-backend-firewall-windows.ps1

$ruleName = 'HRMS API (port 3000)'
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Firewall rule already exists: $ruleName"
    exit 0
}

New-NetFirewallRule `
    -DisplayName $ruleName `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 3000 `
    -Action Allow `
    -Profile Private, Domain

Write-Host "Added inbound firewall rule for TCP port 3000 (Private + Domain profiles)."
Write-Host "Test from your phone browser: http://YOUR_PC_IP:3000/health"
