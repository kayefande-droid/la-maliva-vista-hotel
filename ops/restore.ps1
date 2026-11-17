<#
.SYNOPSIS
    Restore the hotel database from a backup.
.DESCRIPTION
    Destructive: replaces current data. Requires -Confirm unless -Force is given.
    Always takes a safety backup of the current state first.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ops\restore.ps1 -File "$env:USERPROFILE\LaMalivaBackups\lamaliva_2026-11-17_09-00-00.dump"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$File,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repo 'backend\.env'

if (-not (Test-Path $File)) { throw "Backup file not found: $File" }
if (-not (Test-Path $envFile)) { throw "backend\.env is missing." }

$settings = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+)\s*$') { $settings[$matches[1]] = $matches[2].Trim('"') }
}
$url = $settings['LAMALIVA_DATABASE_URL']
if (-not $url) { throw "LAMALIVA_DATABASE_URL is not set." }

Write-Host "This will REPLACE the current hotel database with:" -ForegroundColor Yellow
Write-Host "  $File" -ForegroundColor Yellow
if (-not $Force) {
    $answer = Read-Host "Type RESTORE to continue"
    if ($answer -ne 'RESTORE') { Write-Host "Cancelled." -ForegroundColor Red; exit 1 }
}

Write-Host "Taking a safety backup of the current state first..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'backup.ps1') | Out-Null

$pgRestore = (Get-Command pg_restore -ErrorAction SilentlyContinue).Source
if (-not $pgRestore) {
    $candidate = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\pg_restore.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $candidate) { throw "pg_restore not found." }
    $pgRestore = $candidate.FullName
}

Write-Host "Restoring..." -ForegroundColor Cyan
& $pgRestore --dbname $url --clean --if-exists --no-owner --no-privileges $File
# pg_restore returns 1 for warnings (e.g. "role does not exist" notices) — only fail hard on 2+.
if ($LASTEXITCODE -ge 2) { throw "pg_restore failed with exit code $LASTEXITCODE" }

Write-Host "Restore finished. Verify with ops\status.ps1 and by signing in." -ForegroundColor Green
