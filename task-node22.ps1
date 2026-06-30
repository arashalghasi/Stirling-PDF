#!/usr/bin/env pwsh
# Run any `task` command using this project's pinned Node version (via Volta),
# without changing your system-wide default Node.
#
# WHY THIS EXISTS:
#   On Windows a system-wide Node install (e.g. C:\Program Files\nodejs) lives in the
#   *system* PATH, which Windows resolves BEFORE the *user* PATH where Volta puts its shims.
#   So a bare `npx`/`node` runs the system Node and shadows Volta -- and if that Node is too
#   old for Vite 7 (needs >=20.19 / 22.x) the frontend fails to start with ERR_REQUIRE_ESM.
#   This wrapper prepends Volta's shim directory to PATH for THIS process only, so the
#   project's npm/npx/node resolve to Volta, which then honors the Node version pinned in
#   frontend/package.json (the "volta" field). Nothing global changes; your default Node
#   stays whatever it was, everywhere else.
#
#   On macOS/Linux (and on Windows with no conflicting system Node) Volta's shims are already
#   first on PATH, so plain `task dev` works and you don't need this script -- but it's
#   harmless to use anyway.
#
# ONE-TIME SETUP: see NODE_VERSION_SETUP_WINDOWS.md.
#
# USAGE (from the repo root):
#   ./task-node22.ps1                 # same as: task dev
#   ./task-node22.ps1 dev
#   ./task-node22.ps1 frontend:dev
#   ./task-node22.ps1 frontend:install
#   ./task-node22.ps1 frontend:check

$ErrorActionPreference = 'Stop'

function Find-VoltaBin {
    # 1. Explicit VOLTA_HOME (set by `volta setup`) -> VOLTA_HOME\bin.
    if ($env:VOLTA_HOME -and (Test-Path (Join-Path $env:VOLTA_HOME 'bin'))) {
        return (Join-Path $env:VOLTA_HOME 'bin')
    }
    # 2. A volta.exe already discoverable on PATH -> use its directory.
    $cmd = Get-Command volta -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path $cmd.Source -Parent) }
    # 3. Common install locations (MSI installer, then scoop).
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Volta\bin'),
        (Join-Path $env:USERPROFILE 'scoop\apps\volta\current\appdata\bin')
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'node.exe')) { return $c }
    }
    return $null
}

$voltaBin = Find-VoltaBin
if (-not $voltaBin) {
    throw "Volta not found. Install it (e.g. 'scoop install volta' or https://volta.sh), run 'volta setup', open a NEW shell, then retry. See NODE_VERSION_SETUP_WINDOWS.md."
}

# Prepend for THIS process only -- does not touch system/user PATH.
$env:Path = "$voltaBin;$env:Path"

# Default to `task dev` when no arguments are given.
# @(...) forces an array so splatting never degrades a lone arg into characters.
$taskArgs = @($args)
if ($taskArgs.Count -eq 0) { $taskArgs = @('dev') }

$nodeExe = Join-Path $voltaBin 'node.exe'
Write-Host "Using Node: $(& $nodeExe -v)  (project pin via Volta)" -ForegroundColor Cyan

& task @taskArgs
exit $LASTEXITCODE
