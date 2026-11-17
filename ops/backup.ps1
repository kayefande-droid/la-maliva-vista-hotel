<#
.SYNOPSIS
    Back up the hotel database.
.DESCRIPTION
    Runs pg_dump in custom format, verifies the archive is readable, and keeps
    the last 30 backups. Backups live outside the repository by default.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ops\backup.ps1
#>
[CmdletBinding()]
param(
    [string]$BackupDir = "$env:USERPROFILE\LaMalivaBackups",
    [int]$Keep = 30
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repo 'backend\.env'

if (-not (Test-Path $envFile)) { throw "backend\.env is missing; cannot read database settings." }

$settings = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)\s*$') { $settings[$matches[1]] = $matches[2].Trim('"') }
}

$url = $settings['LAMALIVA_DATABASE_URL']
if (-not $url) { throw "LAMALIVA_DATABASE_URL is not set in backend\.env" }

$pgDump = (Get-Command pg_dump -ErrorAction SilentlyContinue).Source
if (-not $pgDump) {
    $candidate = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\pg_dump.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $candidate) { throw "pg_dump not found. Install PostgreSQL client tools." }
    $pgDump = $candidate.FullName
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$file = Join-Path $BackupDir "lamaliva_$stamp.dump"

Write-Host "Backing up to $file ..." -ForegroundColor Cyan
& $pgDump --dbname $url --format=custom --no-owner --no-privileges --file $file
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed with exit code $LASTEXITCODE" }

$size = (Get-Item $file).Length
if ($size -lt 1024) { throw "Backup looks empty ($size bytes). Treating as a failure." }

Write-Host "Verifying archive..." -ForegroundColor Cyan
& (Join-Path (Split-Path $pgDump) 'pg_restore.exe') --list $file | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Backup archive could not be read back." }

Write-Host "Backup complete: $([math]::Round($size/1MB,2)) MB" -ForegroundColor Green

Get-ChildItem $BackupDir -Filter 'lamaliva_*.dump' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $Keep |
    ForEach-Object {
        Write-Host "Removing old backup $($_.Name)" -ForegroundColor Yellow
        Remove-Item $_.FullName -Force
    }
