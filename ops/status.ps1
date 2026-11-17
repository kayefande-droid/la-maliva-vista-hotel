<#
.SYNOPSIS
    Report the health of the whole hotel server stack.
.DESCRIPTION
    Checks: the API process, the database service, the listening port, the API
    health endpoint, the last backup, and Headscale inside WSL.
#>
[CmdletBinding()]
param(
    [int]$Port = 8000
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot

function Row($label, $value, $ok) {
    $colour = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("{0,-24}" -f $label) -NoNewline
    Write-Host $value -ForegroundColor $colour
}

Write-Host "`nLA-MALIVA VISTA — server status`n" -ForegroundColor Cyan

# API process
$api = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*wsgi.py*" }
Row 'API process' $(if ($api) { "running (PID $($api[0].ProcessId))" } else { 'not running' }) ([bool]$api)

# PostgreSQL service
$pg = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
Row 'PostgreSQL service' $(if ($pg) { "$($pg.Name): $($pg.Status)" } else { 'not installed' }) ($pg.Status -eq 'Running')

# Port
$listen = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
Row "Port $Port" $(if ($listen) { 'listening' } else { 'closed' }) ([bool]$listen)

# Health endpoint
try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/v1/health" -TimeoutSec 5
    Row 'API health' "$($health.status) / db $($health.database)" ($health.database -eq 'ok')
}
catch {
    Row 'API health' 'unreachable' $false
}

# Latest backup
$backupDir = Join-Path $repo 'backups'
if (Test-Path $backupDir) {
    $latest = Get-ChildItem $backupDir -Filter '*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Row 'Latest backup' $(if ($latest) { "$($latest.Name) ($($latest.LastWriteTime))" } else { 'none found' }) ([bool]$latest)
}
else {
    Row 'Latest backup' 'no backups folder' $false
}

# Headscale in WSL
$wsl = wsl -d Ubuntu -u root -- systemctl is-active headscale 2>$null
$headscale = if ($LASTEXITCODE -eq 0) { ($wsl | Out-String).Trim() } else { 'unavailable' }
Row 'Headscale (WSL)' $headscale ($headscale -eq 'active')

Write-Host ""
