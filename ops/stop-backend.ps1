<#
.SYNOPSIS
    Stop the LA-MALIVA VISTA hotel API.
.DESCRIPTION
    Stops only python processes whose command line runs wsgi.py from this repo.
    PostgreSQL is left running so the data stays available.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'backend'

$targets = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*$backend*wsgi.py*" }

if (-not $targets) {
    Write-Host "The hotel API is not running." -ForegroundColor Yellow
    exit 0
}

foreach ($process in $targets) {
    Write-Host "Stopping API (PID $($process.ProcessId))..." -ForegroundColor Cyan
    Stop-Process -Id $process.ProcessId -Force
}

Write-Host "The hotel API has stopped. PostgreSQL is still running." -ForegroundColor Green
