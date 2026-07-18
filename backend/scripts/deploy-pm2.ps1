[CmdletBinding()]
param(
  [ValidateRange(10, 300)]
  [int]$HealthTimeoutSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$backendRoot = Split-Path -Parent $PSScriptRoot
$healthUrl = 'http://127.0.0.1:3000/health'
$databaseHealthUrl = 'http://127.0.0.1:3000/health/db'

function Resolve-CommandPath {
  param([Parameter(Mandatory = $true)][string[]]$Names)

  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
      return $command.Source
    }
  }

  throw "Required command was not found: $($Names -join ', ')"
}

function Invoke-CheckedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
  )

  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
  }
}

function Wait-ForHealth {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][datetime]$Deadline
  )

  $lastError = $null
  do {
    try {
      $response = Invoke-RestMethod -Uri $Url -TimeoutSec 5
      if ($response.ok -eq $true) {
        return
      }
      $lastError = "Endpoint returned ok=$($response.ok)"
    } catch {
      $lastError = $_.Exception.Message
    }

    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $Deadline)

  throw "Health check failed for $Url. Last error: $lastError"
}

$npm = Resolve-CommandPath -Names @('npm.cmd', 'npm')
$pm2 = Resolve-CommandPath -Names @('pm2.cmd', 'pm2')

Push-Location $backendRoot
try {
  Write-Host '[deploy] Running startup preflight before changing PM2...'
  Invoke-CheckedCommand $npm 'run' 'preflight'

  Write-Host '[deploy] Applying bounded PM2 restart policy...'
  Invoke-CheckedCommand $pm2 'startOrReload' 'ecosystem.config.cjs' '--only' 'hrms-backend' '--update-env'

  $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
  Wait-ForHealth -Url $healthUrl -Deadline $deadline
  Wait-ForHealth -Url $databaseHealthUrl -Deadline $deadline

  $firstPid = ((& $pm2 'pid' 'hrms-backend') | Out-String).Trim()
  if (-not $firstPid -or $firstPid -eq '0') {
    throw 'PM2 did not return a running PID for hrms-backend.'
  }

  Write-Host '[deploy] Initial health passed; verifying stability beyond min_uptime...'
  Start-Sleep -Seconds 12

  Wait-ForHealth -Url $healthUrl -Deadline ((Get-Date).AddSeconds(10))
  Wait-ForHealth -Url $databaseHealthUrl -Deadline ((Get-Date).AddSeconds(10))

  $stablePid = ((& $pm2 'pid' 'hrms-backend') | Out-String).Trim()
  if ($stablePid -ne $firstPid) {
    throw "Backend restarted during the stability window (PID $firstPid -> $stablePid)."
  }

  Write-Host '[deploy] Health and PID are stable; saving the PM2 reboot list...'
  Invoke-CheckedCommand $pm2 'save'

  Write-Host "[deploy] SUCCESS: hrms-backend is healthy and stable with PID $stablePid."
} catch {
  Write-Host "[deploy] FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host '[deploy] Recent PM2 errors:'
  & $pm2 'logs' 'hrms-backend' '--err' '--lines' '40' '--nostream'
  exit 1
} finally {
  Pop-Location
}
