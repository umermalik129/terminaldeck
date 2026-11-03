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
| .NET SDK | **10.0.403**, installed 2026-11-03 with `winget install --id Microsoft.DotNet.SDK.10 --version 10.0.403 --exact`. That is the same version upstream tested with. `windows/global.json` pins `10.0.400` with `rollForward: latestPatch`, so only 10.0.4xx SDKs work. |
| Windows App Runtime 1.8 | **8000.994.2142.0**, installed 2026-11-03 from the 1.8.260921001 installer (see §1). The app references WindowsAppSDK 1.8.260921001, which needs >= 8000.994.2142.0. The older 8000.946.1701.0 caused the dialog "Required components of the Windows App Runtime are missing". winget's newest package (1.8.10 = 260710003) is too old. |
| Installed Terminal Deck | MSIX **0.20.3.1** (`C:\Program Files\WindowsApps\TerminalDeck_0.20.3.1_x64__...`). It uses the stable channel (`%LOCALAPPDATA%\TerminalDeckStable`) and bundles its own WinAppSDK runtime, so updating the system runtime does not affect it. Dev runs use a different namespace and never touch it. |
| **IDE** | **none yet.** No Visual Studio, and VS Code is not on PATH. |

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

**Done on this machine** (2026-11-03). On a new machine, install these; the
installers raise a UAC prompt:

```powershell
winget install --id Microsoft.DotNet.SDK.10 --version 10.0.403 --exact
```

**Windows App Runtime: match the version in `TerminalDeck.App.csproj`**
(`Microsoft.WindowsAppSDK` 1.8.260921001 as of 169cd5e). winget can lag behind
it, so use Microsoft's direct link for that exact build:

```powershell
$v = '1.8.260921001'
$exe = "$env:TEMP\WindowsAppRuntimeInstall-x64-$v.exe"
Invoke-WebRequest "https://aka.ms/windowsappsdk/1.8/$v/windowsappruntimeinstall-x64.exe" -OutFile $exe -UseBasicParsing
(Get-AuthenticodeSignature $exe).SignerCertificate.Subject    # expect CN=Microsoft Corporation
& $exe --quiet                                                # no --force, so it never shuts down running apps
Get-AppxPackage Microsoft.WindowsAppRuntime.1.8* | Select-Object Name, Version   # expect >= 8000.994.2142.0
```

A terminal opened before the install will not see `dotnet`. Open a new one, or run
`$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`.

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

- **Confirmed on the first build (2026-11-03).** `TerminalDeck.Core` fails with
  `CSC : error CS1566: Error reading resource 'Contracts.deck-tools-windows-integration.json' -- 'Could not find a part of the path ...\windows\docs\contracts\...'`.
  That takes down everything that depends on Core: App, Keeper, Platform.Windows
  and every test project.
- Even with a successful build, `Core/Mcp/McpCatalogue.cs:15` would throw "The
  MCP contracts are missing." at run time.

**Unblock locally (already done here, never commit it):**

```powershell
.\.dev-notes\tools\make-local-contracts.ps1
```

The script does three things:
- It regenerates **`deck-tools-static-source.json` with real data**: 64 tools,
  from `macos/TerminalDeckNative/Sources/TerminalDeckBackend/`. It runs
  upstream's `windows/scripts/capture-source-contracts.py` from a temp copy
  with the source path fixed, because the original looks for
  `../td-native-shell/macos/...`.
- It writes `deck-tools-windows-integration.json` with **17 placeholder
  entries**: `accounts.install`, `accounts.sign_in_flow`, `browser.open`,
  `close`, `windows`, `page`, `profiles`, `read`, `step`, `screenshot` and
  `handover`, `mcp.callers`, `open` and `remote`, `remote.workspace`,
  `shell.read` and `ui.workspace`. Each has a permissive schema and a cautious
  guessed tier. It also writes an empty `deck-tools-runtime-source.json`.
  Nothing in the repo generates either file.
- It adds `/windows/docs/` to `.git/info/exclude`, so the files never show in
  `git status` or a PR.

**Why there are placeholders and not just empty stubs:** `McpDoor.Register`
(`Core/Mcp/McpDoor.cs:83`) throws `This tool has no source contract.` for any
tool the code registers that has no contract. With empty stubs, the first
launch logged that error from `AppRuntime.RegisterTools()` (called at
`ShellWindow.xaml.cs:101`), which aborted the rest of the shell's `Loaded`
handler. The visible symptoms were a "The session service could not connect"
notice and no workspace tabs. The list of 17 is every ID registered in
`windows/src` minus what `McpCatalogue.Load()` returns. If the log ever shows
that message again, add the new ID to the list in the script.

Real tiers and schemas for those 17 are unknown, so agents calling them may be
prompted differently than upstream intends. Test results for MCP tiers on this
setup don't tell you anything about upstream's behaviour.

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

**First build on this machine (2026-11-03):** it succeeded with **0 warnings
and 0 errors in 70 s**, including the first NuGet restore; the Windows App SDK
restore took about 32 s of that. That was with the local contracts from §2.

Building the App also builds Core, Platform.Windows, Keeper, ToolBridge and
Askpass through project references. The output (122 MB, 132 files) goes to
`windows\src\TerminalDeck.App\bin\x64\Debug\net10.0-windows10.0.19041.0\`,
with no `win-x64\` subfolder:

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
- **The app passes its environment on to every terminal and AI session.**
  - On 2026-11-03 the dev app was launched from a Claude Code tool shell. That
    shell has `NO_COLOR=1`, `GIT_EDITOR=true`, `GIT_TERMINAL_PROMPT=0`,
    `CLAUDECODE=1` and `CLAUDE_CODE_*` set.
  - The result: every terminal was monochrome, including Claude Code's own
    TUI; `git commit` got an editor that exits immediately; and a nested
    `claude` looked like a child session.
  - The run script now clears those variables before launching, unless you set
    one yourself in User or Machine env.
  - Sessions are planned inside the **keeper**. After changing the environment,
    restart the keeper too (no `-KeepKeeper`).
  - The installed app starts from Explorer and is not affected.
- **Second instance for experiments:** use `-DataDir C:\TD\dev\data2` so it
  never touches the window you're using.
  - The process filter matches the exact folder, so `data` and `data2` don't
    stop each other.
  - To build without stopping a running dev app, which locks its exe:
    `dotnet build ... "-p:OutDir=<scratch folder>\"`. Then start that exe with
    `TD_DEV=1 --user-data-dir C:\TD\dev\data2`.

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

### Core.Tests baseline on this machine (2026-11-03, upstream 169cd5e plus the local contracts)

**828 total: 734 passed, 94 failed, 0 skipped (20 s).** Before a PR, compare against
this list. A change should not add failures; failures that were already here are not yours.

| Failures | Error | Cause |
|---|---|---|
| 31 | `InvalidOperationException: No process is associated with this object.` from `ChatCliConnection.DisposeAsync` (`Core/Chats/ChatCliConnection.cs:153`) | **The tests assume macOS.** `ChatFixture.cs:90` and `ChatProtocolTests.cs:44,61` launch `/usr/bin/python3` with `PATH=/usr/bin:/bin`, so the fake CLI never starts on Windows. `DisposeAsync` then calls `HasExited` on a process that never started, and that exception hides the real error. Both problems are worth fixing upstream. |
| 22 | `ArgumentException: This tool has no source contract.` | **Local stubs.** The tool's contract would be in one of the two empty JSON files. |
| 15 | `InvalidOperationException: Sequence contains no matching element` (`.Single(...)` lookups of `browser.*` and other tools) | Most likely the local stubs. |
| 9 | `Assert.Equal() Failure: Strings differ`. Example: `WindowsSignInTests` expects `...\chosen/claude.exe` and gets `...\chosen\claude.exe` | **The tests assume macOS**: they hard-code `/` separators. Windows correctly produces `\`. |
| 6 | `ArgumentException: Choose an absolute scratch data folder.` (`McpTests.Manager`, `McpTests.cs:221`) | **The tests assume macOS**: Unix-style paths are not fully qualified on Windows. |
| 3 | `Assert.Equal() Failure: Values differ` (`DeckToolsAccessTests` for `browser_page`, `browser_read`, `browser_windows`) | Local stubs (missing browser tools) |
| 3 | `HttpRequestException: Error while copying content to a stream.` (Receiver HTTP) | Not investigated |
| 2 | `McpRefusal: An unexpected tool argument was supplied.` | Probably local stubs |
| 1 | `IOException: A required privilege is not held by the client` (td-receiver temp folder) | Creating a symlink on Windows needs Developer Mode or admin rights |
| 1 | `UnauthorizedAccessException: Access to the path ... is denied.` | Not investigated |
| 1 | (no message parsed) | Not investigated |

To get the list again:
`dotnet test tests\TerminalDeck.Core.Tests\TerminalDeck.Core.Tests.csproj 2>&1 | Out-File $env:TEMP\core-tests.log`,
then search the log for `Failed `.

### First launch (2026-11-03)

With runtime 8000.994 and the placeholder contracts, the dev build starts
cleanly, with no `errors.log`. Screenshots are in
`sessions/assets/2026-11-03-launch-*.png`.
- The keeper process appears about 12 s after the app starts, in two runs out of
  two. It is a Debug build on first JIT, so watch whether this is slow every
  time. It is not investigated yet.
- **Window dragging is limited by design**, not broken by our setup. See below.

### Title bar: only a 48 px strip drags the window

`ShellWindow.xaml:69,81`: `TitleDragRegion` is column 3 of `TitleBarRow` with
`Width="48"`, and that element alone is passed to `SetTitleBar`
(`Views/Windows/WorkspaceTitleBar.cs:20`, where the comment says "Only the
empty region is a drag surface"). The tab and page-title column (column 1,
`*`) is client area, even where it is empty.

Measured with `tools/probe-titlebar.ps1`. The probe is read-only: it sends
`WM_NCHITTEST` to the window's `InputNonClientPointerSource` child.
- `HTCAPTION` (draggable) only from about 186 to 150 px left of the right edge,
  the strip just before minimize.
- `HTCLIENT` everywhere else in the title row: the sidebar header, beside
  "Sessions", and the empty middle.

Users naturally try to drag from the empty middle and fail. This is a
**candidate upstream PR**: make the empty title-row space a caption region and
mark the tabs and buttons as passthrough, for example with
`InputNonClientPointerSource.SetRegionRects(NonClientRegionKind.Passthrough, ...)`,
or by giving the drag column the `*` width. Upstream may have chosen 48 px on
purpose, for the tabs, so ask in the PR. Verify any change with the probe.
The probe must show `HTCAPTION` in the empty space and `HTCLIENT` over every
tab and button.

**Possible first PRs upstream:**
1. Ask upstream to publish `windows/docs/contracts/`. File it as an issue.
2. Make the chat fixtures portable: find `python`/`python3` on PATH instead of `/usr/bin/python3`.
3. Make `ChatCliConnection.DisposeAsync` safe when `Start()` threw, so it does not call `HasExited` on a process that never started.
4. Use `Path.Combine` and `Path.GetTempPath()` in `WindowsSignInTests` and `McpTests`.
5. Make the empty title-bar space draggable (see above). The user hit this on the first launch.

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
