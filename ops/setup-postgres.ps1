<#
.SYNOPSIS
    Install PostgreSQL 17, create the hotel database, load the legacy data, and verify it.
.DESCRIPTION
    Does five things, each idempotent, and stops at the first failure:

      1. Installs PostgreSQL 17 - from winget, or from a local installer file
         given with -InstallerPath when this machine has no internet.
      2. Starts the PostgreSQL Windows service.
      3. Creates the hotel role and database if they do not exist, then writes
         LAMALIVA_DATABASE_URL into backend\.env (never printed, never committed).
      4. Runs backend\scripts\migrate_from_sqlite.py --apply to load the 14 rooms,
         the admin account, guests and reservations.
      5. Reconnects as the application role and checks that the rows are really
         there: 14 rooms, at least one admin, the reservations.

    Installing software and creating a database change this machine, so this
    script is run deliberately, not as part of a normal start-up.
.PARAMETER Database
    Database name. Default lamaliva_hotel.
.PARAMETER DbUser
    Application role name. Default lamaliva.
.PARAMETER Password
    Password for the application role. Generated when omitted.
.PARAMETER SuperUser
    Existing PostgreSQL superuser used to create the role/database. Default postgres.
.PARAMETER SuperPassword
    Password for that superuser. Only needed on a fresh install or when psql would
    otherwise prompt. Generated (and shown once) when this script installs PostgreSQL.
.PARAMETER InstallerPath
    A PostgreSQL Windows installer (.exe) already on disk, used instead of winget.
    Get one from https://www.postgresql.org/download/windows/ on any machine with
    internet, copy it here, and pass its path.
.PARAMETER SkipInstall
    Do not install anything; assume PostgreSQL is already installed.
.PARAMETER SkipMigration
    Provision the database but do not load legacy data.
.PARAMETER SkipVerify
    Load the data but do not check the result.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ops\setup-postgres.ps1
.EXAMPLE
    # No internet on this PC: download the installer elsewhere, then
    powershell -ExecutionPolicy Bypass -File ops\setup-postgres.ps1 -InstallerPath C:\Users\Admin\Downloads\postgresql-17.6-1-windows-x64.exe
.NOTES
    Run from an elevated (Administrator) PowerShell window: installing a service
    and starting it requires elevation.

    winget needs outbound HTTPS. If this machine has none, -InstallerPath is the
    offline route; everything after the install is local.
#>
[CmdletBinding()]
param(
    [string]$Database = 'lamaliva_hotel',
    [string]$DbUser = 'lamaliva',
    [string]$Password,
    [string]$SuperUser = 'postgres',
    [string]$SuperPassword,
    [string]$InstallerPath,
    [switch]$SkipInstall,
    [switch]$SkipMigration,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'backend'
$envFile = Join-Path $backend '.env'
$sourceDb = Join-Path $repo 'instance\lamaliva.db'
$pgPort = 5432
$pgServiceName = 'postgresql-x64-17'

function Fail($message) {
    Write-Host "FAIL: $message" -ForegroundColor Red
    exit 1
}

function New-Secret([int]$length) {
    # URL-safe alphabet: passwords end up inside a connection URL.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object 'byte[]' $length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (-join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] }))
}

function Find-Psql {
    $cmd = Get-Command psql -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    return $null
}

function Test-Https([string]$hostName) {
    try {
        $request = [System.Net.HttpWebRequest]::Create("https://$hostName")
        $request.Method = 'HEAD'
        $request.Timeout = 8000
        $response = $request.GetResponse()
        $response.Close()
        return $true
    }
    catch [System.Net.WebException] {
        # A real HTTP answer (even 404/403) means the connection worked.
        if ($_.Exception.Response) { return $true }
        return $false
    }
    catch { return $false }
}

# --- 1. Install -------------------------------------------------------
$psql = Find-Psql
$freshInstall = $false

if (-not $psql) {
    if ($SkipInstall) { Fail "psql not found and -SkipInstall was given." }

    if ($InstallerPath) {
        if (-not (Test-Path $InstallerPath)) { Fail "Installer not found: $InstallerPath" }
        if (-not $SuperPassword) {
            $SuperPassword = New-Secret 24
            $freshInstall = $true
        }
        Write-Host "Installing PostgreSQL 17 from $InstallerPath (unattended)..." -ForegroundColor Cyan
        $installArgs = @(
            '--mode', 'unattended',
            '--unattendedmodeui', 'none',
            '--superpassword', $SuperPassword,
            '--serverport', "$pgPort",
            '--servicename', $pgServiceName,
            '--install_runtimes', '0',   # do not fetch the VC++ redistributable
            '--debuglevel', '1'
        )
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList $installArgs -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Fail "Installer exited with code $($proc.ExitCode). Its log is under %TEMP%\install-postgresql.log."
        }
    }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Checking internet access for winget..." -ForegroundColor Cyan
        if (-not (Test-Https 'cdn.winget.microsoft.com')) {
            Fail @"
This machine cannot reach cdn.winget.microsoft.com, so winget cannot download PostgreSQL.

Offline route (works with no internet here):
  1. On a PC or phone with internet, open https://www.postgresql.org/download/windows/
  2. Download the EDB installer, e.g. postgresql-17.6-1-windows-x64.exe
  3. Copy it to this PC, then run:
     powershell -ExecutionPolicy Bypass -File ops\setup-postgres.ps1 -InstallerPath C:\path\to\postgresql-17.6-1-windows-x64.exe
"@
        }
        Write-Host "Installing PostgreSQL 17 via winget (this takes a few minutes)..." -ForegroundColor Cyan
        winget install --id PostgreSQL.PostgreSQL.17 --exact --silent `
            --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Fail "winget install failed with exit code $LASTEXITCODE." }
    }
    else {
        Fail "Neither psql nor winget is available. Install PostgreSQL 17 from https://www.postgresql.org/download/windows/ then re-run with -SkipInstall."
    }

    $psql = Find-Psql
    if (-not $psql) { Fail "PostgreSQL was installed but psql.exe was not found. Open a new terminal and re-run with -SkipInstall." }
}
Write-Host "psql: $psql" -ForegroundColor Green

if ($SuperPassword) { $env:PGPASSWORD = $SuperPassword }

# --- 2. Service -------------------------------------------------------
$service = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $service) {
    # A fresh install registers the service a moment after the process returns.
    for ($i = 0; $i -lt 30 -and -not $service; $i++) {
        Start-Sleep -Seconds 1
        $service = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
    }
}
if (-not $service) { Fail "No PostgreSQL service registered. Re-run after a fresh terminal, or install manually." }
if ($service.Status -ne 'Running') {
    Write-Host "Starting $($service.Name)..." -ForegroundColor Yellow
    Start-Service $service.Name
}
Write-Host "Service $($service.Name): $((Get-Service $service.Name).Status)" -ForegroundColor Green

# --- 3. Role + database ----------------------------------------------
if (-not $Password) {
    $Password = New-Secret 32
    Write-Host "Generated a password for role '$DbUser' (not echoed)." -ForegroundColor Yellow
}

Write-Host "Creating role and database if missing as '$SuperUser' on 127.0.0.1:$pgPort." -ForegroundColor Cyan
if (-not $SuperPassword) {
    Write-Host "No -SuperPassword given, so psql may prompt once for the '$SuperUser' password." -ForegroundColor Yellow
}

$roleExists = & $psql -h 127.0.0.1 -p $pgPort -U $SuperUser -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$DbUser'"
if ($LASTEXITCODE -ne 0) { Fail "Could not connect to PostgreSQL as '$SuperUser' on 127.0.0.1:$pgPort." }

if ($roleExists -ne '1') {
    & $psql -h 127.0.0.1 -p $pgPort -U $SuperUser -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE $DbUser LOGIN PASSWORD '$Password'"
    if ($LASTEXITCODE -ne 0) { Fail "Could not create role $DbUser." }
    Write-Host "Role $DbUser created." -ForegroundColor Green
}
else {
    & $psql -h 127.0.0.1 -p $pgPort -U $SuperUser -d postgres -v ON_ERROR_STOP=1 -c "ALTER ROLE $DbUser WITH LOGIN PASSWORD '$Password'"
    if ($LASTEXITCODE -ne 0) { Fail "Could not update role $DbUser." }
    Write-Host "Role $DbUser already existed; password refreshed." -ForegroundColor Yellow
}

$dbExists = & $psql -h 127.0.0.1 -p $pgPort -U $SuperUser -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$Database'"
if ($dbExists -ne '1') {
    & $psql -h 127.0.0.1 -p $pgPort -U $SuperUser -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $Database OWNER $DbUser"
    if ($LASTEXITCODE -ne 0) { Fail "Could not create database $Database." }
    Write-Host "Database $Database created." -ForegroundColor Green
}
else {
    Write-Host "Database $Database already exists; left as is." -ForegroundColor Yellow
}

# --- 4. Connection settings ------------------------------------------
# .env is git-ignored; the URL never goes into source or logs.
$url = "postgresql://$DbUser`:$Password@127.0.0.1:$pgPort/$Database"
$line = "LAMALIVA_DATABASE_URL=$url"

$existing = @()
if (Test-Path $envFile) { $existing = @(Get-Content -Path $envFile) }
$found = $false
$updated = foreach ($row in $existing) {
    if ($row -match '^\s*LAMALIVA_DATABASE_URL\s*=') { $found = $true; $line }
    else { $row }
}
$updated = @($updated)
if (-not $found) { $updated += $line }

if (-not (Select-String -Path $envFile -Pattern '^\s*LAMALIVA_SECRET_KEY\s*=' -Quiet -ErrorAction SilentlyContinue)) {
    $secretBytes = New-Object 'byte[]' 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($secretBytes)
    $secret = -join ($secretBytes | ForEach-Object { '{0:x2}' -f $_ })
    $updated += "LAMALIVA_SECRET_KEY=$secret"
    Write-Host "Generated LAMALIVA_SECRET_KEY in backend\.env." -ForegroundColor Green
}

# UTF-8 without BOM: a BOM would corrupt the first key name for python-dotenv.
[System.IO.File]::WriteAllLines($envFile, [string[]]$updated, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote LAMALIVA_DATABASE_URL to backend\.env (value not shown)." -ForegroundColor Green

# --- 5. Load the legacy data -----------------------------------------
if ($SkipMigration) {
    Write-Host "Skipping data migration (-SkipMigration)." -ForegroundColor Yellow
    exit 0
}
if (-not (Test-Path $sourceDb)) {
    Fail "Legacy database not found at $sourceDb; nothing to migrate."
}

$python = Join-Path $backend '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) { $python = 'python' }

Push-Location $backend
try {
    $env:LAMALIVA_DATABASE_URL = $url
    Write-Host "Migrating legacy data..." -ForegroundColor Cyan
    & $python 'scripts\migrate_from_sqlite.py' --source $sourceDb --apply --create-schema
    if ($LASTEXITCODE -ne 0) { Fail "Data migration failed with exit code $LASTEXITCODE." }
}
finally {
    Pop-Location
}

# --- 6. Verify as the application role --------------------------------
if ($SkipVerify) {
    Write-Host "Skipping verification (-SkipVerify)." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Verifying as role '$DbUser' over TCP..." -ForegroundColor Cyan
$env:PGPASSWORD = $Password
$query = "SELECT (SELECT count(*) FROM room) || '|' || (SELECT count(*) FROM staff) || '|' || (SELECT count(*) FROM staff WHERE role = 'admin') || '|' || (SELECT count(*) FROM room_type) || '|' || (SELECT count(*) FROM reservation)"
$row = & $psql -h 127.0.0.1 -p $pgPort -U $DbUser -d $Database -tAc $query
if ($LASTEXITCODE -ne 0) { Fail "Could not connect as '$DbUser'. The .env URL may be wrong." }

$parts = "$row".Trim().Split('|')
$rooms = [int]$parts[0]
$staff = [int]$parts[1]
$admins = [int]$parts[2]
$types = [int]$parts[3]
$reservations = [int]$parts[4]

Write-Host ""
Write-Host "  rooms          $rooms" -ForegroundColor Gray
Write-Host "  room types     $types" -ForegroundColor Gray
Write-Host "  staff          $staff ($admins admin)" -ForegroundColor Gray
Write-Host "  reservations   $reservations" -ForegroundColor Gray

$problems = @()
if ($rooms -ne 14) { $problems += "expected 14 rooms, found $rooms" }
if ($admins -lt 1) { $problems += "no admin account found" }
if ($problems.Count -gt 0) { Fail ("Verification failed: " + ($problems -join '; ')) }

Write-Host ""
Write-Host "PostgreSQL is ready and verified." -ForegroundColor Green
if ($freshInstall -and $SuperPassword) {
    Write-Host ""
    Write-Host "Record this PostgreSQL superuser password somewhere safe - it is shown once:" -ForegroundColor Yellow
    Write-Host "  $SuperUser : $SuperPassword" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Start the API, then sign in from the staff apps:" -ForegroundColor Green
Write-Host "  powershell -ExecutionPolicy Bypass -File ops\start-backend.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "Sign in with the administrator account carried over from the old system" -ForegroundColor Gray
Write-Host "(migration marks it must-change-password). If that password is unknown, reset it:" -ForegroundColor Gray
Write-Host "  cd backend" -ForegroundColor Gray
Write-Host "  python scripts\reset_staff_password.py --list" -ForegroundColor Gray
Write-Host "  python scripts\reset_staff_password.py --username <name> --apply" -ForegroundColor Gray
