# Frontend Node version setup (Windows + Volta)

This guide explains how to run the Stirling-PDF frontend with the Node.js version the
project requires, on Windows, **without changing or uninstalling any system-wide Node**.
The project pins its Node version with [Volta](https://volta.sh) and ships two small
PowerShell helper scripts that make Windows use that pinned version even when an older Node is
installed system-wide:

- **`start-dev.ps1`** — the convenient one-command startup: launches the backend, waits for
  it, then launches the frontend, then opens the login page. Use this for everyday "run the
  app" work.
- **`task-node22.ps1`** — a general-purpose wrapper that runs **any** `task` command with the
  pinned Node (e.g. `frontend:install`, `frontend:check`, a single component).

See [The two scripts — which to use and why](#the-two-scripts--which-to-use-and-why) for the
full explanation.

> **macOS / Linux users:** you usually don't need any of this. Install Volta
> (`curl https://get.volta.sh | bash`), open a new shell, and run `task dev` — Volta reads
> the pin from `frontend/package.json` automatically. The launcher exists only to work
> around a Windows `PATH` precedence issue described in [Why the launcher is needed](#why-the-launcher-is-needed-windows).

---

## Quick start

1. **Install Volta** (user-level, no admin required):

   ```powershell
   scoop install volta        # or download the installer from https://volta.sh
   volta setup                # registers Volta's node/npm/npx shims
   ```

   Open a **new terminal** afterwards so the changes take effect.

2. **Run the project** from the repository root:

   ```powershell
   .\start-dev.ps1            # backend -> frontend -> opens the login page
   ```

   On first run, Volta automatically downloads the pinned Node version. You should see:

   ```
   Using Node: v22.x.x  (project pin via Volta)
   [1/3] Starting backend ...   Backend is ready (port 8080).
   [2/3] Starting frontend ...  Frontend is ready (port 5173).
   [3/3] Opening http://localhost:5173/ in your browser ...
   ```

That's it. `start-dev.ps1` opens the backend and frontend in their own windows (so you can
see their logs) and only opens the browser once both are listening — so you never hit the
"cannot connect to the backend" error. See [Startup timing](#startup-timing) for why ordering
matters.

---

## Why a specific Node version is required

The frontend is built with **Vite 7**, whose `package.json` declares:

```
engines.node = "^20.19.0 || >=22.12.0"
```

An older Node (for example Node 18) cannot load Vite 7's ESM-only config and fails with:

```
You are using Node.js 18.x. Vite requires Node.js version 20.19+ or 22.12+.
Error [ERR_REQUIRE_ESM]: require() of ES Module @vitejs/plugin-react-swc/index.js not supported.
```

The project's CI runs on **Node 22** (see `.github/workflows/*.yml`), so Node 22 is the
target for local development as well. The exact version is pinned in
`frontend/package.json` under the `"volta"` field.

---

## Why the launcher is needed (Windows)

Windows composes a process's `PATH` as **System entries first, then User entries**. A
system-wide Node install (such as `C:\Program Files\nodejs`) lives in the *System* `PATH`,
while per-user version managers (Volta, nvm-windows, fnm) install their shims into the
*User* `PATH`.

As a result, a bare `node` / `npx` always resolves to the system Node and shadows Volta's
shims. You cannot fix the ordering by editing the *User* `PATH` (System always wins), and
editing the *System* `PATH` or uninstalling the system Node requires administrator rights.

`task-node22.ps1` works around this **per command**: it prepends Volta's shim directory to
`PATH` for that single process only. Inside the launcher, `node` / `npm` / `npx` resolve to
Volta, which then honors the version pinned in `frontend/package.json`. Nothing global
changes — your system Node remains the default everywhere else.

If you have **no** conflicting system Node, plain `task dev` already works; the launcher is
still safe to use.

---

## How it works

Two pieces cooperate:

| Piece | Location | Purpose |
|-------|----------|---------|
| **Version pin** | `"volta"` field in `frontend/package.json` | Declares which Node version the project uses. Volta reads it automatically when a Volta-managed `node`/`npm`/`npx` runs inside the project, and downloads that version on first use. |
| **PATH workaround** | `task-node22.ps1` and `start-dev.ps1` (repository root) | Both prepend Volta's shim directory to `PATH` for their own process so the pin is actually honored on Windows. They auto-detect Volta's location (via `VOLTA_HOME`, a `volta` on `PATH`, or the standard MSI/scoop install paths), so they work on any machine. |

`task-node22.ps1` is the minimal version of this — it adds nothing but the PATH fix and
forwards your arguments to `task`:

```powershell
$ErrorActionPreference = 'Stop'

function Find-VoltaBin {
    if ($env:VOLTA_HOME -and (Test-Path (Join-Path $env:VOLTA_HOME 'bin'))) {
        return (Join-Path $env:VOLTA_HOME 'bin')
    }
    $cmd = Get-Command volta -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path $cmd.Source -Parent) }
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
    throw "Volta not found. Install it (scoop install volta or https://volta.sh), run 'volta setup', open a NEW shell, then retry."
}

# Prepend for THIS process only — does not touch system/user PATH.
$env:Path = "$voltaBin;$env:Path"

# Default to `task dev` when no arguments are given.
# @(...) forces an array so splatting never degrades a lone arg into characters.
$taskArgs = @($args)
if ($taskArgs.Count -eq 0) { $taskArgs = @('dev') }

$nodeExe = Join-Path $voltaBin 'node.exe'
Write-Host "Using Node: $(& $nodeExe -v)  (project pin via Volta)" -ForegroundColor Cyan
& task @taskArgs
exit $LASTEXITCODE
```

---

## The two scripts — which to use and why

Both scripts live at the repository root and both apply the Volta-pinned Node using the same
PATH workaround. They exist because they solve **two different problems**:

| Script | Solves | Use it when |
|--------|--------|-------------|
| **`start-dev.ps1`** | *Startup ordering.* It starts the backend, **waits until port 8080 is actually accepting connections**, then starts the frontend, waits for port 5173, and only then opens the browser. | You want to run the whole app for development. |
| **`task-node22.ps1`** | *Node version only.* It is a thin pass-through: it prepends Volta to `PATH` and forwards whatever arguments you give straight to `task`. It does **not** sequence anything or open a browser. | You want to run a single `task` command with the right Node (install, check, lint, a single component, etc.). |

### Why a second script was needed

The plain combined command (`task dev`, or `task-node22.ps1 dev`) starts the backend and
frontend **in parallel** and opens the browser **immediately**. But the frontend is ready in
~1–2 seconds while the backend (Spring Boot via Gradle) needs ~20–60 seconds. So the browser
opens, the page tries to reach the backend that isn't up yet, and you see:

> *"The application currently cannot connect to the backend. Check the backend status and
> network connectivity, then try again."*

`task-node22.ps1` cannot fix this on its own — it only controls the Node version, not timing.
`start-dev.ps1` was added to enforce the **backend → frontend → browser** order, so the page
only loads once the backend is reachable. That is the single reason the two scripts are
separate: one is a generic Node-version wrapper, the other adds startup orchestration on top.

> In short: `start-dev.ps1` is for *running the app*; `task-node22.ps1` is for *running a
> task*. `start-dev.ps1` is the one you'll use most.

---

## Usage

### Everyday startup — `start-dev.ps1`

```powershell
.\start-dev.ps1                                  # backend -> frontend -> open browser
.\start-dev.ps1 -BackendPort 8080 -FrontendPort 5173   # override default ports
```

The backend and frontend each open in their own titled window ("Stirling Backend" /
"Stirling Frontend") so you can read their logs. Stop them with `Ctrl+C` in each window, or
just close the windows.

### Any other task — `task-node22.ps1`

Run any `task` command through the wrapper; arguments are passed straight to `task`:

```powershell
.\task-node22.ps1 dev               # backend + frontend together (parallel, browser auto-opens early)
.\task-node22.ps1 frontend:dev      # frontend only
.\task-node22.ps1 frontend:install  # (re)install dependencies
.\task-node22.ps1 frontend:check    # lint + typecheck + test
```

Always run both from the **repository root** (they call `task`, which discovers the root
`Taskfile.yml`). On Windows, prefer these wrappers over bare `task` whenever a conflicting
system Node may be present.

---

## Startup timing

`task dev` starts the backend and frontend together:

- The **frontend** (Vite) is ready in ~1–2 seconds and serves at `http://localhost:5173/`
  (the combined `task dev` may choose another free port and open the browser for you).
- The **backend** (Spring Boot via Gradle) takes roughly **30–60 seconds** on first start —
  the Gradle daemon warms up silently before producing output.

While the backend is still starting, the browser shows a message such as *"the application
cannot connect to the backend"*, and the Vite console logs `http proxy error … ECONNREFUSED`
for `/api/...` requests. **This is expected.** Once the backend logs `Started SPDFApplication`
(Tomcat listening on its port), refresh the browser and the app connects.

**`start-dev.ps1` avoids this entirely** by waiting for the backend before starting the
frontend and waiting for both before opening the browser. If you instead use `task dev` /
`task-node22.ps1 dev`, just wait for `Started SPDFApplication` and refresh.

Backend startup also logs warnings like `Missing dependency: qpdf / tesseract / ghostscript`.
These are **optional external tools**; the corresponding features are disabled but the
application runs normally without them.

---

## Troubleshooting

- **Which Node am I using?** Run `node -v`. In a normal shell it reflects your system
  default; inside the launcher it should print the pinned version.
- **`Volta not found` from the launcher** — Volta isn't installed or isn't detectable.
  Re-run `scoop install volta` (or the installer from https://volta.sh), then `volta setup`,
  then open a new shell.
- **Is Volta reading the pin?**

  ```powershell
  cd frontend
  volta list node
  # -> runtime node@22.x.x (current @ ...\frontend\package.json)
  ```

- **`Task "f" does not exist`** — a PowerShell quirk: a single-element array can be unwrapped
  to a string and then splatted character-by-character. The launcher guards against this with
  `@($args)`; keep that wrapping if you modify the script.
- **App can't connect to the backend in the browser** — the backend hasn't finished starting.
  Use `start-dev.ps1` (which waits for the backend), or wait for `Started SPDFApplication` in
  the logs and refresh. See [Startup timing](#startup-timing).
- **Port already in use** — a previous dev server is still running. Stop it (close the
  "Stirling Backend"/"Stirling Frontend" windows), or pass different ports to `start-dev.ps1`
  (`-BackendPort` / `-FrontendPort`). The combined `task dev` selects free ports automatically.

---

## Alternatives

- **nvm-windows** manages Node by swapping a symlink at `C:\Program Files\nodejs`; it cannot
  be used alongside a separate system Node occupying that path, and it does not read
  `.nvmrc` / `.node-version`, so it can't auto-switch per project.
- **fnm** (`scoop install fnm`) supports `.node-version` auto-switching via a shell hook, but
  has the same System-`PATH` precedence caveat for a bare shell on Windows.
- **Removing the system Node and using Volta (or another manager) globally** is the cleanest
  long-term setup, but requires administrator rights and changes your global default — out of
  scope for this guide.
