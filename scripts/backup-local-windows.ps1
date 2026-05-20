<#
.SYNOPSIS
Creates a local HRMS backup on a Windows production server.

.DESCRIPTION
Backs up the PostgreSQL database with pg_dump and archives backend/uploads.
Use this script from Windows Task Scheduler on the machine where the real
production PostgreSQL database and local uploads live.
#>

[CmdletBinding()]
param(
  [string]$ProjectRoot,
  [string]$EnvFile,
  [string]$DatabaseUrl,
  [string]$UploadDir,
  [string]$BackupRoot = $env:HRMS_BACKUP_ROOT,
  [string]$OffsiteBackupRoot = $env:HRMS_OFFSITE_BACKUP_ROOT,
  [string]$PgDumpPath = $env:PG_DUMP_PATH,
  [int]$KeepDaily = 7,
  [int]$KeepWeekly = 4,
  [int]$KeepMonthly = 12,
  [switch]$IncludeEnvFile,
  [switch]$SkipUploads,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-BackupLog {
  param([string]$Message)

  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Write-Host $line
  if ($script:LogFile -and -not $DryRun) {
    Add-Content -LiteralPath $script:LogFile -Value $line
  }
}

function Read-DotEnv {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) {
      continue
    }

    $equalsIndex = $trimmed.IndexOf('=')
    if ($equalsIndex -lt 1) {
      continue
    }

    $key = $trimmed.Substring(0, $equalsIndex).Trim()
    $value = $trimmed.Substring($equalsIndex + 1).Trim()

    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    $values[$key] = $value
  }

  return $values
}

function New-BackupDirectory {
  param([string]$Path)

  if ($DryRun) {
    Write-BackupLog "DRY RUN: would create directory $Path"
    return
  }

  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-BackupSnapshot {
  param(
    [string]$Source,
    [string]$Destination
  )

  Write-BackupLog "Copying snapshot to $Destination"
  if ($DryRun) {
    Write-BackupLog "DRY RUN: would copy $Source to $Destination"
    return
  }

  $parent = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Remove-OldSnapshots {
  param(
    [string]$Root,
    [int]$Keep
  )

  if ($Keep -lt 1 -or -not (Test-Path -LiteralPath $Root)) {
    return
  }

  $oldSnapshots = Get-ChildItem -LiteralPath $Root -Directory |
    Sort-Object Name -Descending |
    Select-Object -Skip $Keep

  foreach ($snapshot in $oldSnapshots) {
    Write-BackupLog "Removing old snapshot $($snapshot.FullName)"
    if (-not $DryRun) {
      Remove-Item -LiteralPath $snapshot.FullName -Recurse -Force
    }
  }
}

try {
  if (-not $ProjectRoot) {
    if ($PSScriptRoot) {
      $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    } else {
      $ProjectRoot = (Get-Location).Path
    }
  }

  $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
  $BackendDir = Join-Path $ProjectRoot 'backend'

  if (-not $EnvFile) {
    $EnvFile = Join-Path $BackendDir '.env'
  }

  if (-not $BackupRoot) {
    $BackupRoot = 'C:\HRMSBackups\hrms_plaridel'
  }

  if (-not $PgDumpPath) {
    $PgDumpPath = 'pg_dump'
  }

  $envValues = Read-DotEnv -Path $EnvFile

  if (-not $DatabaseUrl) {
    if ($env:DATABASE_URL) {
      $DatabaseUrl = $env:DATABASE_URL
    } elseif ($envValues.ContainsKey('DATABASE_URL')) {
      $DatabaseUrl = $envValues['DATABASE_URL']
    }
  }

  if (-not $DatabaseUrl) {
    throw 'DATABASE_URL was not found. Set it in backend\.env or pass -DatabaseUrl.'
  }

  if (-not $UploadDir) {
    if ($env:UPLOAD_DIR) {
      $UploadDir = $env:UPLOAD_DIR
    } elseif ($envValues.ContainsKey('UPLOAD_DIR')) {
      $UploadDir = $envValues['UPLOAD_DIR']
    } else {
      $UploadDir = Join-Path $BackendDir 'uploads'
    }
  }

  if (-not [System.IO.Path]::IsPathRooted($UploadDir)) {
    $UploadDir = Join-Path $BackendDir $UploadDir
  }

  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $dailyRoot = Join-Path $BackupRoot 'daily'
  $weeklyRoot = Join-Path $BackupRoot 'weekly'
  $monthlyRoot = Join-Path $BackupRoot 'monthly'
  $logRoot = Join-Path $BackupRoot 'logs'
  $snapshotDir = Join-Path $dailyRoot $timestamp

  if (-not $DryRun) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $script:LogFile = Join-Path $logRoot "backup_$timestamp.log"
  }

  Write-BackupLog "Starting HRMS Windows backup"
  Write-BackupLog "Project root: $ProjectRoot"
  Write-BackupLog "Backup root: $BackupRoot"
  Write-BackupLog "Upload dir: $UploadDir"

  New-BackupDirectory -Path $snapshotDir

  $pgDumpCommand = Get-Command $PgDumpPath -ErrorAction Stop
  $databaseDumpPath = Join-Path $snapshotDir 'database.dump'
  Write-BackupLog "Running pg_dump"

  if ($DryRun) {
    Write-BackupLog "DRY RUN: would run $($pgDumpCommand.Source) --format=custom --no-owner --no-acl --file=$databaseDumpPath DATABASE_URL"
  } else {
    & $pgDumpCommand.Source --format=custom --no-owner --no-acl "--file=$databaseDumpPath" $DatabaseUrl
    if ($LASTEXITCODE -ne 0) {
      throw "pg_dump failed with exit code $LASTEXITCODE"
    }
  }

  $uploadsArchivePath = $null
  if (-not $SkipUploads) {
    if (Test-Path -LiteralPath $UploadDir) {
      $uploadsArchivePath = Join-Path $snapshotDir 'uploads.zip'
      $uploadItems = Get-ChildItem -LiteralPath $UploadDir -Force

      if ($uploadItems.Count -gt 0) {
        Write-BackupLog "Compressing uploads"
        if ($DryRun) {
          Write-BackupLog "DRY RUN: would archive $UploadDir to $uploadsArchivePath"
        } else {
          Compress-Archive -LiteralPath $uploadItems.FullName -DestinationPath $uploadsArchivePath -CompressionLevel Optimal -Force
        }
      } else {
        Write-BackupLog "Upload directory exists but is empty"
        if (-not $DryRun) {
          Set-Content -LiteralPath (Join-Path $snapshotDir 'uploads_empty.txt') -Value 'Upload directory existed but had no files.'
        }
      }
    } else {
      Write-BackupLog "Upload directory does not exist; writing marker"
      if (-not $DryRun) {
        Set-Content -LiteralPath (Join-Path $snapshotDir 'uploads_missing.txt') -Value "Upload directory was not found: $UploadDir"
      }
    }
  }

  if ($IncludeEnvFile) {
    Write-BackupLog "Including backend .env file. Treat this backup as sensitive."
    if (-not $DryRun -and (Test-Path -LiteralPath $EnvFile)) {
      Copy-Item -LiteralPath $EnvFile -Destination (Join-Path $snapshotDir 'backend.env') -Force
    }
  }

  if (-not $DryRun) {
    $manifest = [ordered]@{
      created_at = (Get-Date).ToString('o')
      computer_name = $env:COMPUTERNAME
      project_root = $ProjectRoot
      env_file = $EnvFile
      upload_dir = $UploadDir
      database_dump = 'database.dump'
      uploads_archive = if ($uploadsArchivePath) { 'uploads.zip' } else { $null }
      include_env_file = [bool]$IncludeEnvFile
      keep_daily = $KeepDaily
      keep_weekly = $KeepWeekly
      keep_monthly = $KeepMonthly
    }

    $manifest |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath (Join-Path $snapshotDir 'manifest.json') -Encoding UTF8
  }

  $createdSnapshots = @(
    [pscustomobject]@{ Tier = 'daily'; Path = $snapshotDir }
  )

  $now = Get-Date
  if ($now.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
    $weeklySnapshot = Join-Path $weeklyRoot $timestamp
    Copy-BackupSnapshot -Source $snapshotDir -Destination $weeklySnapshot
    $createdSnapshots += [pscustomobject]@{ Tier = 'weekly'; Path = $weeklySnapshot }
  }

  if ($now.Day -eq 1) {
    $monthlySnapshot = Join-Path $monthlyRoot $timestamp
    Copy-BackupSnapshot -Source $snapshotDir -Destination $monthlySnapshot
    $createdSnapshots += [pscustomobject]@{ Tier = 'monthly'; Path = $monthlySnapshot }
  }

  if ($OffsiteBackupRoot) {
    foreach ($snapshot in $createdSnapshots) {
      $offsiteDestination = Join-Path (Join-Path $OffsiteBackupRoot $snapshot.Tier) $timestamp
      Copy-BackupSnapshot -Source $snapshot.Path -Destination $offsiteDestination
    }
  }

  Remove-OldSnapshots -Root $dailyRoot -Keep $KeepDaily
  Remove-OldSnapshots -Root $weeklyRoot -Keep $KeepWeekly
  Remove-OldSnapshots -Root $monthlyRoot -Keep $KeepMonthly

  if ($OffsiteBackupRoot) {
    Remove-OldSnapshots -Root (Join-Path $OffsiteBackupRoot 'daily') -Keep $KeepDaily
    Remove-OldSnapshots -Root (Join-Path $OffsiteBackupRoot 'weekly') -Keep $KeepWeekly
    Remove-OldSnapshots -Root (Join-Path $OffsiteBackupRoot 'monthly') -Keep $KeepMonthly
  }

  Write-BackupLog "Backup completed successfully: $snapshotDir"
  exit 0
} catch {
  Write-BackupLog "Backup failed: $($_.Exception.Message)"
  exit 1
}
