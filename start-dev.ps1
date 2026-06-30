#!/usr/bin/env pwsh
# Start Stirling-PDF for local development in the correct order:
#   1. Backend  (Spring Boot)         -> wait until it accepts connections
#   2. Frontend (Vite, Node via Volta) -> wait until it accepts connections
#   3. Open the login page in your default browser
#
# This avoids the "application cannot connect to the backend" error you get when the browser
# opens before the backend has finished booting (the backend takes ~20-60s; the frontend ~1s).
#
# The backend and frontend each open in their own window so you can see their logs and stop
# them with Ctrl+C. The Node version is provided by Volta (pinned in frontend/package.json);
# see NODE_VERSION_SETUP_WINDOWS.md for the why.
#
# Usage (from anywhere):
#   .\start-dev.ps1
#   .\start-dev.ps1 -BackendPort 8080 -FrontendPort 5173

param(
    [int]$BackendPort  = 8080,
    [int]$FrontendPort = 5173,
    [int]$BackendTimeoutSec  = 240,
    [int]$FrontendTimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$Url      = "http://localhost:$FrontendPort/"

# --- Ensure node/npx resolve to the Volta-pinned Node (Windows system-PATH workaround) -------
# Child windows launched below inherit this PATH, so the frontend window gets the right Node.
function Find-VoltaBin {
    if ($env:VOLTA_HOME -and (Test-Path (Join-Path $env:VOLTA_HOME 'bin'))) {
        return (Join-Path $env:VOLTA_HOME 'bin')
    }
    $cmd = Get-Command volta -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path $cmd.Source -Parent) }
    foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Volta\bin'),
        (Join-Path $env:USERPROFILE 'scoop\apps\volta\current\appdata\bin')
    )) {
        if (Test-Path (Join-Path $c 'node.exe')) { return $c }
    }
    return $null
}

$voltaBin = Find-VoltaBin
if (-not $voltaBin) {
    throw "Volta not found. Install it (scoop install volta or https://volta.sh), run 'volta setup', open a NEW shell, then retry. See NODE_VERSION_SETUP_WINDOWS.md."
}
$env:Path = "$voltaBin;$env:Path"
Write-Host "Using Node: $(& (Join-Path $voltaBin 'node.exe') -v)  (project pin via Volta)" -ForegroundColor Cyan

# --- Helpers ---------------------------------------------------------------------------------
function Test-Port([int]$port) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $iar = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(800) -and $client.Connected) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Wait-Port([int]$port, [string]$name, [int]$timeoutSec) {
    Write-Host ("Waiting for {0} (port {1}, up to {2}s) ..." -f $name, $port, $timeoutSec) -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        if (Test-Port $port) {
            Write-Host ("{0} is ready (port {1})." -f $name, $port) -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Start-DevWindow([string]$title, [string]$taskName) {
    # Open a titled PowerShell window that stays open (-NoExit) and runs the given task.
    $command = "`$host.UI.RawUI.WindowTitle = '$title'; task $taskName"
    Start-Process -FilePath 'powershell' -WorkingDirectory $RepoRoot `
        -ArgumentList '-NoExit', '-Command', $command | Out-Null
}

# --- 1) Backend ------------------------------------------------------------------------------
Write-Host "`n[1/3] Starting backend (task backend:dev) ..." -ForegroundColor Cyan
Start-DevWindow -title 'Stirling Backend' -taskName 'backend:dev'
if (-not (Wait-Port $BackendPort 'Backend' $BackendTimeoutSec)) {
    throw "Backend did not start within $BackendTimeoutSec s. Check the 'Stirling Backend' window."
}

# --- 2) Frontend -----------------------------------------------------------------------------
Write-Host "`n[2/3] Starting frontend (task frontend:dev) ..." -ForegroundColor Cyan
Start-DevWindow -title 'Stirling Frontend' -taskName 'frontend:dev'
if (-not (Wait-Port $FrontendPort 'Frontend' $FrontendTimeoutSec)) {
    throw "Frontend did not start within $FrontendTimeoutSec s. Check the 'Stirling Frontend' window."
}

# --- 3) Open the browser ---------------------------------------------------------------------
Write-Host "`n[3/3] Opening $Url in your browser ..." -ForegroundColor Cyan
Start-Process $Url

Write-Host "`nReady. Backend and frontend run in their own windows." -ForegroundColor Green
Write-Host "Stop them with Ctrl+C in each window (or just close the windows)." -ForegroundColor Green
