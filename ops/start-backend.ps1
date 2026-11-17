<#
.SYNOPSIS
    Start the LA-MALIVA VISTA hotel API on this Windows PC.
.DESCRIPTION
    Preflight checks, then runs the API. PostgreSQL must already be running as a
    Windows service; this script does not start the database for you silently.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ops\start-backend.ps1
#>
[CmdletBinding()]
param(
    [int]$Port = 8000,
    [switch]$Background
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'backend'
$envFile = Join-Path $backend '.env'

function Fail($message) {
    Write-Host "FAIL: $message" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $envFile)) {
    Fail "backend\.env is missing. Copy backend\.env.example and fill it in."
}

$service = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $service) {
    Fail "No PostgreSQL service found. Install PostgreSQL and create the hotel database first."
}
if ($service.Status -ne 'Running') {
    Write-Host "Starting $($service.Name)..." -ForegroundColor Yellow
    Start-Service $service.Name
}

$python = Join-Path $backend '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) {
    $python = 'python'
    Write-Host "No backend virtualenv found; using the system python." -ForegroundColor Yellow
}

Push-Location $backend
try {
    Write-Host "Checking database connectivity..." -ForegroundColor Cyan
    & $python -c "from wsgi import app; from lamaliva.extensions import db; app.app_context().push(); db.session.execute(db.text('SELECT 1')); print('database ok')"
    if ($LASTEXITCODE -ne 0) { Fail "Database connection failed. Check LAMALIVA_DATABASE_URL in backend\.env." }

    $env:LAMALIVA_ENV = if ($env:LAMALIVA_ENV) { $env:LAMALIVA_ENV } else { 'development' }
    $env:LAMALIVA_PORT = "$Port"

    Write-Host "Serving on http://127.0.0.1:$Port (env: $env:LAMALIVA_ENV)" -ForegroundColor Green
    if ($Background) {
        Start-Process -FilePath $python -ArgumentList 'wsgi.py' -WorkingDirectory $backend -WindowStyle Hidden
        Write-Host "Started in the background. Use ops\status.ps1 to check it." -ForegroundColor Green
    }
    else {
        & $python wsgi.py
    }
}
finally {
    Pop-Location
}
