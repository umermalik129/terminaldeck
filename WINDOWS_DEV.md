# Running, debugging and testing the Windows app on this machine

Target: the **native Windows app** in `windows/` (C# / .NET 10, WinUI 3, WebView2).
The Electron app at the repo root (`npm run dev`) is the older desktop app.
Upstream ships it for macOS now, and its last Windows release was 0.15.0. See
[PROJECT_NOTES.md](PROJECT_NOTES.md#the-electron-app-at-the-root).

## 0. This machine (checked 2026-11-03)

| Thing | State |
|---|---|
| OS | Windows 10 Pro 22H2, build 19045, x64. The app's minimum is 10.0.19041, so this is fine. |
| Node / npm | v24.21.0 / 11.19.0 (OK, the repo needs >= 22) |
| git / gh | 2.55, `gh` logged in as `umermalik129` (scopes include `repo` and `workflow`) |
| Python | 3.15.2 |
| WebView2 runtime | 156.0.4314.58 installed |
| **.NET SDK** | **missing.** `windows/global.json` pins `10.0.400` with `rollForward: latestPatch`, so you need a **10.0.4xx** SDK specifically. |
| **Windows App Runtime 1.8** | **not checked yet.** The app is unpackaged and not self-contained, so it needs this runtime at launch. |
| **IDE** | **none.** No Visual Studio, and VS Code is not on PATH. |

Windows 10 caveats (from reading the code; nothing in the repo records a Windows 10 test run):
- Mica is Windows 11 only. `Views/Windows/WindowMaterials.cs` checks
  `MicaController.IsSupported()` and falls back to opaque brushes. That is a
  visual difference only, so screenshots taken here will not match upstream's
  Windows 11 ones.
- The Mica proof (`LookMicaProof.cs`) does not have that guard, so it **will fail on Windows 10**.
- Upstream's README says "Windows 11" for building. The code targets Windows 10
  2004 or newer, but upstream only tested on Windows 11.
- The share target needs MSIX package identity, so it does not work in a dev (unpackaged) build.

## 1. One-time setup

Run these in an **elevated** PowerShell, because installers trigger UAC:

```powershell
winget install Microsoft.DotNet.SDK.10
winget install Microsoft.WindowsAppRuntime.1.8
```

Then, in a new terminal:

```powershell
dotnet --list-sdks          # must show a 10.0.4xx entry
cd C:\Users\admin\Projects\terminaldeck\windows
dotnet --version            # run inside windows/: global.json must resolve, or every build fails
```

If winget installs a different feature band (for example 10.0.1xx), install the 4xx band with the official script:

```powershell
Invoke-WebRequest https://dot.net/v1/dotnet-install.ps1 -OutFile $env:TEMP\dotnet-install.ps1
& $env:TEMP\dotnet-install.ps1 -Channel 10.0.4xx -InstallDir "C:\Program Files\dotnet"
```

**IDE (pick one):**

- **Visual Studio 2026 Community (recommended for WinUI).** Install it from
  visualstudio.microsoft.com with the **.NET desktop development** and
  **WinUI application development** workloads. You get F5 debugging, XAML Hot
  Reload, Live Visual Tree and Attach to Process. VS installs its own SDK, but
  `global.json` still decides which one is used, so keep the 10.0.4xx SDK installed.
- **VS Code.** `winget install Microsoft.VisualStudioCode`, then add the
  **C# Dev Kit** extension. It reads the same `launchSettings.json` (below) but
  has no XAML designer and no XAML Hot Reload.

## 2. Known blocker: missing MCP contract files

`windows/src/TerminalDeck.Core/TerminalDeck.Core.csproj:5-7` embeds:

```
windows/docs/contracts/deck-tools-windows-integration.json
windows/docs/contracts/deck-tools-static-source.json
windows/docs/contracts/deck-tools-runtime-source.json
```

`windows/docs/` does not exist in upstream's public commit (`169cd5e`). Other
files also point into it: `Platform.Windows/README.md` cites
`docs/WIN-PROGRESS.md` and `docs/WIN-PARITY-REQUESTS.md`. The likely cause is
that the folder was left out of the public export. Two consequences:

- The compiler cannot read a missing embedded resource, so **`TerminalDeck.Core`
  is expected to fail to build**. That would take down everything that depends
  on it: App, Keeper, Platform.Windows and every test project. Confirm this on
  the first build.
- If you got past the build, `Core/Mcp/McpCatalogue.cs:15` would throw "The MCP
  contracts are missing." at run time.

**Unblock locally (never commit this).** Each file only needs a top-level
`entries` array. Empty stubs drop the Mac-derived `sessions.*`, `browser.*`,
`accounts.*` and similar MCP tools, but Projects, Tasks, Servers, Receiver,
Hoot, Code and Account tools are still registered in code:

```powershell
cd C:\Users\admin\Projects\terminaldeck
New-Item -ItemType Directory -Force windows\docs\contracts | Out-Null
foreach ($n in 'deck-tools-windows-integration','deck-tools-static-source','deck-tools-runtime-source') {
  $f = "windows\docs\contracts\$n.json"; if (-not (Test-Path $f)) { Set-Content $f '{"entries":[]}' -Encoding ascii }
}
Add-Content .git\info\exclude "/windows/docs/contracts/"   # keeps the stubs out of every PR
```

Expect MCP and tool-list tests to fail with the stubs. `windows/scripts/capture-source-contracts.py`
can regenerate the *static* file from the Swift sources, but it looks for them
in `../td-native-shell/macos/...`. Here they are in
`macos/TerminalDeckNative/Sources/TerminalDeckBackend/`, so the script needs
its source path changed. Nothing in the repo generates the other two files.

**Better fix:** open an issue upstream asking for `windows/docs/contracts/` to be
published. That could be the first contribution to `asadev/terminaldeck`.

## 3. Build (Debug)

Always pass a platform. The `CopyKeeper` target in `TerminalDeck.App.csproj`
copies from `../TerminalDeck.Keeper/bin/$(Platform)/$(Configuration)/...`, so an
AnyCPU build leaves the bundled keeper folder empty.

```powershell
cd C:\Users\admin\Projects\terminaldeck\windows
dotnet restore TerminalDeck.slnx
dotnet build src\TerminalDeck.App\TerminalDeck.App.csproj -c Debug -p:Platform=x64
```

Building the App also builds Keeper, ToolBridge and Askpass through project
references. Output goes to
`windows\src\TerminalDeck.App\bin\x64\Debug\net10.0-windows10.0.19041.0\`
(look in a `win-x64\` subfolder if the exe is not directly there):

```
TerminalDeck.App.exe
keeper-location.txt               <- the id of the current keeper bundle
keeper\<yyyyMMddHHmmssfff>\       <- a new folder on every build; they pile up, delete old ones
    TerminalDeck.Keeper.exe
    tools-bridge\TerminalDeck.ToolBridge.exe
    askpass\...
```

`Directory.Build.props` sets `TreatWarningsAsErrors=true`, so a new warning breaks the build.

## 4. Run against scratch data

Never point a dev build at the real data folder (`%LOCALAPPDATA%\TerminalDeck`).
With `TD_DEV=1` the app **requires** `--user-data-dir <absolute path>` and
refuses the installed data folders.

```powershell
.\.dev-notes\tools\run-windows-debug.ps1               # builds Debug x64, stops the old app and keeper, launches
.\.dev-notes\tools\run-windows-debug.ps1 -NoBuild      # relaunch only
.\.dev-notes\tools\run-windows-debug.ps1 -KeepKeeper   # keep sessions alive, to test reattach
.\.dev-notes\tools\run-windows-debug.ps1 -Clean        # stop everything, delete scratch data and its Credential Manager entries
```

The default data folder is `C:\TD\dev\data`. The equivalent by hand:

```powershell
$env:TD_DEV = '1'
& .\windows\src\TerminalDeck.App\bin\x64\Debug\net10.0-windows10.0.19041.0\TerminalDeck.App.exe --user-data-dir C:\TD\dev\data
```

Things to know:
- The only accepted arguments are `--user-data-dir <abs>` (or `=<abs>`) and
  `--start-minimized`. Anything else shows an error window.
- Each data folder is its own namespace, so two scratch folders can run side by
  side. The namespace is the first 24 hex characters of SHA-256 over the
  upper-cased path; it scopes the single-instance key, the keeper mutex, the
  pipes and the Credential Manager entries. A second launch for the *same*
  folder is redirected to the window that is already open.
- **The keeper outlives the window.** After you rebuild, the app reconnects to
  the **old** keeper process running old code. The script stops it by default.
  To do it by hand, kill the PID in `C:\TD\dev\data\keeper\supervisor.identity.json`.
  Session workers are `TerminalDeck.Keeper.exe --worker ...` processes.
- Folders under `C:\TD\` also get a pointer written to
  `C:\TD\share-target\<SID>\root.txt`. That is harmless.
- **Don't leave `TD_*_PROOF` or `TD_W12_OFFSCREEN` variables set** in your
  shell. Some of them move the window to x = -20000 or start it unfocused.

**Logs:**
- `C:\TD\dev\data\logs\errors.log` is the only log file. It records XAML,
  task, AppDomain and dispatcher exceptions with their HRESULTs. The app's
  "Show log" command opens this folder.
- `TD_CRASH_DIAGNOSTICS=1` (or the script's `-CrashDiagnostics` switch) also
  logs the first 100 first-chance exceptions.
- `C:\TD\dev\data\mcp\actions.jsonl` is the MCP audit trail.
- The keeper has **no log file**. It is started detached, so its stderr is lost.
  To debug it, attach a debugger (below).

## 5. Debug with breakpoints

A local launch profile is already in place:
`windows\src\TerminalDeck.App\Properties\launchSettings.json`. It is listed in
`.git\info\exclude`, so it never shows in `git status` or a PR. It has two
profiles. Both set `TD_DEV=1` and `--user-data-dir C:\TD\dev\data`; the second
also sets `TD_CRASH_DIAGNOSTICS=1`.

**Visual Studio:**
1. Open `windows\TerminalDeck.slnx`.
2. Set **TerminalDeck.App** as the startup project.
3. Choose the **Debug | x64** configuration.
4. Pick the profile "TerminalDeck.App (scratch data)" from the dropdown next to the green Run button.
5. Press **F5**. Breakpoints in App, Core and Platform.Windows code that runs in the app process just work.
6. XAML Hot Reload and C# Hot Reload work for unpackaged WinUI apps. Structural XAML changes still need a restart.

Before you press F5 again after a rebuild, stop the old keeper (see section 4).
Otherwise keeper-side changes will not show up:

```powershell
.\.dev-notes\tools\run-windows-debug.ps1 -StopOnly    # stops the app, keeper, workers and toolbridge for C:\TD\dev\data
```

**Keeper and session workers.** They are separate processes, so use **Debug >
Attach to Process** and pick `TerminalDeck.Keeper.exe`. The supervisor has only
`--user-data-dir` in its command line, and workers have `--worker <key>`. Show
the Command Line column in the Attach dialog to tell them apart. Choose the
**Managed (.NET Core 5+)** code type.

**ToolBridge** is started by AI CLIs as the `deck-tools` MCP server
(`--root <dataRoot> --chat <chatId>`). Attach to it the same way.

**VS Code with C# Dev Kit:** open the `windows` folder, then use
Run and Debug > **C#: Launch Startup Project**. It picks up `launchSettings.json`.

## 6. Tests

**Run these anywhere** (`net10.0`, plain xunit). Node must be on PATH for
some Core tests:

```powershell
cd C:\Users\admin\Projects\terminaldeck\windows
dotnet test tests\TerminalDeck.Core.Tests\TerminalDeck.Core.Tests.csproj           # ~607, the one upstream documents
dotnet test tests\TerminalDeck.ProjectsAgents.Tests\TerminalDeck.ProjectsAgents.Tests.csproj
dotnet test tests\TerminalDeck.Servers.Tests\TerminalDeck.Servers.Tests.csproj
dotnet test tests\Hoot\TerminalDeck.Hoot.Tests.csproj
dotnet test tests\TerminalDeck.Chat.ViewModel.Tests\TerminalDeck.Chat.ViewModel.Tests.csproj
dotnet test tests\TerminalDeck.Recovery.Tests\TerminalDeck.Recovery.Tests.csproj
dotnet test src\TerminalDeck.Platform.Windows\Tests\Core\TerminalDeck.WorkerCore.Tests.csproj
# Shell tests: keep generated files out of the App source tree
dotnet test src\TerminalDeck.App\Views\Windows\Tests\TerminalDeck.Shell.Tests.csproj --artifacts-path C:\TD\artifacts\shell-tests
```

Only Core.Tests is part of a solution (`TerminalDeck.slnx`, or
`TerminalDeck.Core.slnf` for Core alone), so the others need the explicit
`.csproj` path. All the paths above were checked against the tree on 2026-11-03.

**Windows integration tests** need environment variables and upstream's
`C:\TD\...` lab layout. They throw if a variable is missing:

| Project | Needs |
|---|---|
| `src\TerminalDeck.Platform.Windows\Tests\TerminalDeck.Windows.Tests` | `TD_KEEPER_EXE` (a built keeper), `C:\TD\out\...`, `C:\TD\tools\ai` CLIs, `TD_EVIDENCE_DIR` |
| `tests\HootWindows\TerminalDeck.Hoot.Windows.Tests.csproj` | `TD_HOOT_TEST_ROOT` |
| `tests\TerminalDeck.Chat.Windows.Tests` | `TD_CHAT_PROOF_ROOT`, `TD_CHAT_WORKER_HOST` |
| `tests\TerminalDeck.Servers.Windows.Tests` | `TD_SERVERS_PROOF_ROOT` (must be under `C:\TD\out\`), `TD_SERVERS_ASKPASS` |

The **"Proof" projects** (`tests\*.Proof`, `HootProof`, the `W12-*.ps1`
scripts) are WinUI screenshot harnesses that need an interactive desktop
session. Their scripts assume the maintainer's lab PC (`C:\TD\work`,
`C:\TD\locks`, `tools/win/*`, lane branches) and won't run here without edits.
Use them as reading material, not as the test gate.

`windows\tools\terminal-assets` builds the bundled xterm.js page into
`src\TerminalDeck.App\Assets\terminal\`. Its output is committed, so you only
need it if you change the terminal surface:

```powershell
cd windows\tools\terminal-assets; npm ci; npm run build
```

Its `npm test` uses a hard-coded macOS Chrome path, so it does not run on Windows as written.

**TypeScript checks from upstream's PR template** (`npm run typecheck`, `npm test`)
cover the Electron and TS code at the root. For a Windows-only PR, say in the
PR body which `dotnet test` projects you ran instead, and whether the root
checks were relevant.

## 7. The change loop

1. `.\.dev-notes\tools\start-feature.ps1 fix/windows-<thing>`
2. Edit the code.
3. Press F5 in VS, or run `.\.dev-notes\tools\run-windows-debug.ps1`.
4. **Look at it.** Take before and after screenshots (Win+Shift+S) and keep them
   in `.dev-notes\sessions\assets\`.
5. Run `dotnet test` on the projects you touched.
6. Commit, then `git push -u origin fix/windows-<thing>`, then
   `gh pr create --repo asadev/terminaldeck ...` (see [GIT_WORKFLOW.md](GIT_WORKFLOW.md)).
7. Write the session log in `.dev-notes\sessions\`, then run `.\.dev-notes\tools\save-notes.ps1`.

## 8. Cleanup

- `run-windows-debug.ps1 -Clean` stops the app, keeper, workers and toolbridge
  for that data folder. It then deletes the folder and its Credential Manager
  entries: `Terminal Deck/<ns>/keeper/auth-v2`, `remote-host` and
  `remote-identity`, all generic credentials.
- `windows\src\TerminalDeck.App\bin\...\keeper\<id>\` folders build up, one per
  build. Delete them, or run `dotnet clean`.
