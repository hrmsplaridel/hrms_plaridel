[CmdletBinding()]
param(
  [ValidateRange(10, 180)]
  [int]$HealthTimeoutSeconds = 45,
  # Set by start-pm2-at-logon.vbs so we do not re-enter the silent launcher loop.
  [switch]$SilentHost
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Task Scheduler still shows a blank console for powershell -WindowStyle Hidden.
# Re-launch once through WScript (window style 0), then exit this visible host.
if (-not $SilentHost) {
  $vbsPath = Join-Path $PSScriptRoot 'start-pm2-at-logon.vbs'
  if (-not (Test-Path -LiteralPath $vbsPath)) {
    throw "Silent launcher not found: $vbsPath"
  }
  Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList @('//B', "`"$vbsPath`"") -WindowStyle Hidden | Out-Null
  exit 0
}

$backendRoot = Split-Path -Parent $PSScriptRoot
$userProfile = [Environment]::GetFolderPath('UserProfile')
$appData = [Environment]::GetFolderPath('ApplicationData')
$nodePath = Join-Path $env:ProgramFiles 'nodejs\node.exe'
$pm2Cli = Join-Path $appData 'npm\node_modules\pm2\bin\pm2'
$env:PM2_HOME = Join-Path $userProfile '.pm2'
$logPath = Join-Path $env:PM2_HOME 'hrms-startup.log'
$healthUrls = @(
  'http://127.0.0.1:3000/health',
  'http://127.0.0.1:3000/health/db'
)

function Write-StartupLog {
  param([Parameter(Mandatory = $true)][string]$Message)

  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -LiteralPath $logPath -Value "[$timestamp] $Message"
}

function Test-HealthEndpoints {
  foreach ($url in $healthUrls) {
    try {
      $response = Invoke-RestMethod -Uri $url -TimeoutSec 5
      if ($response.ok -ne $true) {
        return $false
      }
    } catch {
      return $false
    }
  }
  return $true
}

try {
  if (-not (Test-Path -LiteralPath $env:PM2_HOME)) {
    New-Item -ItemType Directory -Path $env:PM2_HOME | Out-Null
  }
  if (-not (Test-Path -LiteralPath $nodePath)) {
    throw "Node executable not found: $nodePath"
  }
  if (-not (Test-Path -LiteralPath $pm2Cli)) {
    throw "PM2 CLI not found: $pm2Cli"
  }

  Write-StartupLog "Startup task began for $env:USERNAME."
  if (Test-HealthEndpoints) {
    Write-StartupLog 'Backend and database were already healthy.'
    exit 0
  }

  Push-Location $backendRoot
  try {
    $pm2Args = @($pm2Cli, 'resurrect')
    $pm2Process = Start-Process -FilePath $nodePath -ArgumentList $pm2Args -WorkingDirectory $backendRoot -WindowStyle Hidden -PassThru -Wait
    $pm2ExitCode = $pm2Process.ExitCode
    Write-StartupLog "PM2 resurrect exited with code $pm2ExitCode."
    if ($pm2ExitCode -ne 0) {
      throw "PM2 resurrect failed with exit code $pm2ExitCode."
    }
  } finally {
    Pop-Location
  }

  $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
  do {
    if (Test-HealthEndpoints) {
      Write-StartupLog 'Backend and database health checks passed.'
      exit 0
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)

  throw 'Backend health checks did not pass before the timeout.'
} catch {
  Write-StartupLog "FAILED: $($_.Exception.Message)"
  exit 1
}
