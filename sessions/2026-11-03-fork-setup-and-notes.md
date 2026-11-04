# Session 2026-11-03: fork setup, developer notes, Windows dev guide

- **Branch:** eight PR branches from `upstream/main` 169cd5e (table in Part 12). Notes are on `dev-notes`.
- **PR:** asadev/terminaldeck #1–#8, open and ready for review (state at close: see "Wrap-up")
- **Upstream at:** `169cd5e` (v0.20.2, 2026-10-31); fork `main` is identical

## Goal

Survey the repo from a developer's point of view. Store session notes in the
fork only, never in upstream PRs. Document how to run, debug and test Windows
changes on this machine, then push and PR upstream.

## What changed

Local git config only. Nothing in the tracked tree changed.
- Added remote `upstream` = `https://github.com/asadev/terminaldeck.git`, with
  its push URL set to `DISABLED-use-a-PR-from-origin`.
- Created the orphan branch `dev-notes` as a worktree at `.dev-notes/`.
- `.git/info/exclude` now lists `/.dev-notes/` and
  `/windows/src/TerminalDeck.App/Properties/launchSettings.json`.
- Added `windows/src/TerminalDeck.App/Properties/launchSettings.json`
  (local-only). It has F5 profiles with `TD_DEV=1` and
  `--user-data-dir C:\TD\dev\data`.

Notes written: README, PROJECT_NOTES, WINDOWS_DEV, GIT_WORKFLOW, the session
template, and tools (`start-feature.ps1`, `run-windows-debug.ps1`,
`save-notes.ps1`, `pre-push`).

## How it was checked

- `start-feature.ps1`: ran it with a throwaway branch. It branched from
  `upstream/main` 169cd5e, and the branch was deleted afterwards.
- `run-windows-debug.ps1`: parse check passed. `-StopOnly` runs. The
  data-folder guard refuses `%LOCALAPPDATA%\TerminalDeck`. `-NoBuild` with no
  build fails cleanly. **A real build and launch has not been tested**,
  because there is no .NET SDK yet.
- Main worktree `git status` stays clean with the notes and launch profile present.

## Findings

- **No .NET SDK, no Visual Studio, no VS Code** on this machine. You need SDK
  **10.0.4xx** (`global.json` uses `latestPatch`) and the Windows App Runtime 1.8.
- **`windows/docs/contracts/*.json` is missing from upstream.**
  `TerminalDeck.Core.csproj:5-7` embeds those files, so the build is expected
  to fail. There is a local stub workaround in WINDOWS_DEV.md §2. It is worth
  raising as an upstream issue.
- The machine is Windows 10 (19045). The app supports 10.0.19041 and up, but
  Mica falls back to opaque brushes here, and upstream only tested on Windows 11.
- Writing `.git/hooks/pre-push` was blocked by the Claude Code permission
  classifier. Install it by hand if you want it:
  `Copy-Item .dev-notes\tools\pre-push .git\hooks\pre-push`.

## Part 2: SDK install and first build

- Installed .NET SDK **10.0.403** with winget. `dotnet --version` inside
  `windows/` resolves `global.json` to 10.0.403.
- Windows App Runtime 1.8 was already installed (`8000.946.1701.0`).
- Built Core alone first, with no workaround. It failed with
  **CS1566 (missing `windows/docs/contracts/...json`)**, confirming the blocker.
- Wrote `tools/make-local-contracts.ps1`:
  - It regenerates the real `deck-tools-static-source.json` (64 tools) from the
    in-repo Swift sources, using upstream's capture script with the path fixed.
  - It writes empty stubs for the other two files.
  - It adds `/windows/docs/` to `.git/info/exclude`.
  - Re-ran it from a deleted folder; it reproduced the same output.
- `dotnet build src\TerminalDeck.App\TerminalDeck.App.csproj -c Debug -p:Platform=x64`
  **succeeded, with 0 warnings and 0 errors, in 70 s.** The exe is at
  `bin\x64\Debug\net10.0-windows10.0.19041.0\TerminalDeck.App.exe`, and the
  keeper bundle is at `keeper\20261103100217238\` with Keeper, ToolBridge and Askpass.
- Core.Tests: **734 of 828 passed, 94 failed.** About 42 failures come from the
  local stubs. About 46 come from tests that assume macOS (`/usr/bin/python3`,
  `/` separators, Unix paths). 6 are other or not investigated. The full table
  is in WINDOWS_DEV.md §6.
- `git status` in the main worktree stayed clean throughout.
- The app has **not been launched yet**, and no IDE is installed yet.

## Part 3: first launch attempt

- Ran `run-windows-debug.ps1 -NoBuild`. The app showed the bootstrapper dialog
  **"Required components of the Windows App Runtime are missing. Version 1.8
  (MSIX package version >= 8000.994.2142.0)"**. The installed runtime is
  8000.946.1701.0. No data folder or keeper was created. The dev process
  (PID 2556) was closed with `-StopOnly`.
- I found the user's **installed Terminal Deck** running: MSIX 0.20.3.1, stable
  channel, 4 live session workers. It bundles its own runtime and was not
  touched.
- winget's newest runtime package is 1.8.10 (260710003), which is too old.
  Downloaded the exact `1.8.260921001` installer from Microsoft (106,879,800
  bytes, Authenticode signature Valid, Microsoft Corporation) into the scratchpad.
- **The Claude Code permission classifier blocked running it** ("Code from
  External"). The user has to run it themselves; the command is in WINDOWS_DEV.md §1.

## Part 4: runtime installed, first successful launch

- The user's first installer run printed only the help text, which means it
  got an unrecognized argument and did not install. The trailing
  `; "exit=..."` in the `!` command probably reached the exe as an argument.
  Running the bare exe worked. The runtime is now **8000.994.2142.0**, with the
  Main and DDLM packages.
- Launch 1 got the window up, but `errors.log` showed `[Shell initialization]
  ArgumentException: This tool has no source contract.` from
  `AccountFlowTools.Register` (`AppRuntime.cs:306`, called from
  `ShellWindow.xaml.cs:101`). The empty stubs were the cause. The UI showed
  "The session service could not connect". Screenshot:
  `assets/2026-11-03-launch-1-init-crash.png`.
- Built a throwaway console program in the scratchpad that calls
  `McpCatalogue.Load()`: 202 IDs. Diffed that against the IDs registered in
  `windows/src`, giving 17 missing. `make-local-contracts.ps1` now writes
  placeholder entries for them.
- Launch 2, after `-Clean` and a rebuild: **no errors.log, the workspace loads**
  (W1 tab, empty pane, New session). Screenshot: `assets/2026-11-03-launch-2-ok.png`.
- **The user reported "not able to drag window".** Measured it with
  `tools/probe-titlebar.ps1`: only a 48 px strip left of minimize is a caption
  region. The cause is upstream's XAML (`TitleDragRegion` is `Width="48"`), not
  our setup. It is a candidate PR (WINDOWS_DEV.md §6).
- Script fixes:
  - `run-windows-debug.ps1 -Clean` now also stops the dev WebView2 processes
    and retries the delete, because the first `-Clean` failed on a locked
    `BrowserMetrics-*.pma` file.
  - The script refreshes PATH if `dotnet` is missing.
- Your installed Terminal Deck (0.20.3.1, 4 sessions, 10 WebView2 processes)
  was never touched.

## Part 5: first PR branch, draggable title bar

- **Branch:** `fix/windows-titlebar-drag` from `upstream/main` 169cd5e.
  Commit `a8b0873` is **local only, not pushed yet**; push and PR after the
  user tries it.
- **Change:**
  - `WorkspaceTitleBar` now passes the whole title-bar row to `SetTitleBar`.
    That's `TitleBarRow` for the main window and `header` for separate tab windows.
  - It cuts every `ButtonBase`, `TextBox`, `PasswordBox`, `AutoSuggestBox` and
    `ComboBox` out as `NonClientRegionKind.Passthrough` through
    `InputNonClientPointerSource`.
  - The regions are recomputed on `LayoutUpdated` and only sent when they differ
    from `GetRegionRects`.
  - Tabs are clipped to the strip's `ScrollViewer`.
  - Open popups that aren't tooltips also get passthrough, with a recheck on `Popup.Closed`.
- **Gotchas:**
  - `GetRegionRects` returns **null** when nothing is set. The first build threw
    `ArgumentNullException` from `SequenceEqual`, and errors.log caught it.
  - Passthrough works as **holes in the `InputNonClientPointerSource` window
    region**, not as a WM_NCHITTEST answer. Sending WM_NCHITTEST directly
    bypasses the region and still says HTCAPTION. `probe-titlebar.ps1` now
    checks `GetWindowRgn` and `PtInRegion` first.
  - UI Automation reports a tab button's bounds as its **label only**, so the
    probe treats gaps inside the tab strip as "inside a tab".
- **Verified** with the probe:
  - 1, 3 and 7 tabs, and sidebar collapsed: all points as expected.
  - 19 tabs: UI Automation timed out, so I read the region directly. Drag is at
    0–8, 44–284 and 1060–1264 (client px); holes cover the toggle, the whole
    strip and the + buttons.
  - Build has 0 warnings, and there's no errors.log.
- **Not verified:**
  - right-click menus over the row;
  - separate (popped-out) tab windows;
  - more than 100% scaling;
  - Windows 11.

  The user should try these by hand.
- **Tooling:**
  - The probe was rewritten to find buttons through UI Automation.
  - `run-windows-debug.ps1` ignores WebView2 children that exit during the stop.
  - The scratchpad helpers (UI Automation invoke, PrintWindow screenshot)
    stayed local.
- The user's next requests are separate branches: smoother tab switching,
  blurry text and icons, the usage ring design, choosing PowerShell or cmd,
  and focusing the terminal when the window activates.

## Part 6: user feedback round (smoothness, colour, focus, shell)

The user asked for:
- smooth tab selection;
- smooth fonts and icons;
- the usage ring to match the icons in design and smoothness;
- the cursor in the terminal when the window activates;
- whether the shell can be cmd instead of PowerShell.

Later they added "the terminal should be color".

| Finding | Cause | Branch (local commits, **none pushed**) |
|---|---|---|
| Terminals monochrome, Claude Code TUI too | **Dev-only.** The dev app was launched from a Claude Code tool shell (`NO_COLOR=1`, `GIT_EDITOR=true`, `GIT_TERMINAL_PROMPT=0`, `CLAUDECODE`, `CLAUDE_CODE_*`), and the app, keeper and sessions inherit it | none. `run-windows-debug.ps1` now clears these |
| Terminal text "crisp" | xterm WebGL atlas is opaque, so Chromium uses ClearType (colour fringes); the WinUI text around it is grayscale | `fix/windows-terminal-smooth-text` b0e46c4 (`allowTransparency: true`; rebuilding the bundle unchanged reproduced it byte for byte, `npm ci --ignore-scripts` + `node build.mjs`) |
| Have to click before typing | Nothing refocuses WebView2 on window activation; after a tab click, `FocusPane` ran before the rebuilt pane was loaded | `fix/windows-focus-terminal` cf5bdc6 |
| Tab switching janky | 2 full rebuilds per click (every chip: XamlReader icons, SVGs, menus) | `fix/windows-smooth-tab-switch` 79e3988 |
| Toolbar icons uneven, ⋯ specks | 16-pt drawings rendered at 14 px (0.875×); the + buttons beside them use 16 | `fix/windows-toolbar-icons-ring` e79332c |
| Usage ring small, blurry | 12 px with inset stroke vs the Mac's ~14 pt; dim instead of pulse | same branch |
| Shell choice | Hard-coded `powershell.exe -NoLogo -NoProfile` (`WindowsProviderLaunchPlanner.cs:15`), with no setting. `pwsh` isn't installed here | not started: proposal to the user |

**Tab-switch timing.** Measured on a Debug build with 4 terminal tabs, in a
second off-screen instance (`C:\TD\dev\data2`). The temporary `TdTiming.cs`
instrumentation was never committed; the patches are in the scratchpad only.

| | Before | After |
|---|---|---|
| Renders per click | 2 full | 1 panes-only |
| Render cost | 11–71 ms | 3–14 ms |
| UI thread busy per click | 35–105 ms | 11–27 ms |
| First frame | 30–138 ms | 4–49 ms |

- A header rebuild was about 9–13 ms (up to 39 ms); the panes were about 3 ms.
- The state save fsync is about 2 ms, so it isn't the problem.
- The title-bar `LayoutUpdated` walk costs about 0.3–0.5 ms, 3–4 times per switch.
- Some 20–30 ms frame gaps remain. Likely cause: WebView2 being reparented
  into the new pane holder. Not addressed.

**Side fix.** The cheap `UpdateFocus` path never moved the selected-tab shape,
divider or ×, which only showed with split panes of the same owner. The
per-chip restyle fixes that.

**Verified:**
- All 5 branches compile, and `local/try-all` builds with 0 warnings.
- The data2 screenshot after a switch shows the selected tab moved, a focused
  cursor in the terminal, grayscale terminal text (4× zoom), and icons at 16 px.

**Not verified:**
- the ring visuals (needs an AI session);
- focus on Alt+Tab (needs real activation);
- Release build timings;
- Windows 11.

**Integration branch.** The local-only `local/try-all` merges all the fix
branches, and the dev app runs from it. See GIT_WORKFLOW.md.

**Script fixes:**
- clears tool environment variables (by `SetEnvironmentVariable`, because
  `Remove-Item env:` fails on an empty value);
- matches the exact data folder (`data` vs `data2`);
- ignores WebView2 children that exit during a stop.

**Restarts.** The first clean-environment restart ended the user's Claude Code
session in the dev app (iPresent project), which can be resumed. Later rebuilds
used `-KeepKeeper`.

## Part 7: shell setting and Chrome-like tab switching

The user asked to "add the shell setting with cmd option" and said "the tabs
are not smooth yet, it should work like the chrome tabs".

**`feat/windows-terminal-shell` 8f9700f** (local, not pushed):
- **Choice:** Settings → General → *Terminal shell*: Windows PowerShell
  (default), PowerShell 7 (selectable only if `pwsh.exe` is on PATH or in
  `Program Files\PowerShell\7`; not installed here), and Command Prompt.
- **Session pinning:** a new `SessionDefinition.Shell` field pins the shell per
  session.
- **Scope:** only `StartShellForProjectAsync` applies the setting. That covers
  the + button, the New session picker and project menus. Agents, MCP tools and
  proofs keep Windows PowerShell.
- **Labels:** tab titles, sidebar subtitles and the picker name the shell.
- **Tests:** 12 `TerminalShellTests` pass. The failing Core.Tests names are
  identical to upstream/main (52 vs 52). The old 94-failure baseline predates
  the 17 placeholder contracts.
- **Verified** in a fresh data2 instance with `{"TerminalShell":"cmd"}`: the
  keeper started `C:\WINDOWS\system32\cmd.exe`, the tab and subtitle read
  "Command Prompt", and the Settings row renders.

**`fix/windows-smooth-tab-switch` +78dfdc2 +79e8acd:**
- **Kept pane sets:** rendered panes are kept per (owner, tabs shown) and only
  their visibility toggles; a view moves only when another set needs it.
- **Select on press:** tab buttons use `ClickMode.Press`, as in Chrome.
- **Measured** (data2, Debug, 4 tabs, after warm-up): every switch reused its
  panes. Render 1–2.6 ms, whole click about 10 ms, first frame 3–32 ms.
- **Outlier:** one earlier run showed a ~90–160 ms click. Finer logs showed no
  slow step, so it was outside interference.

**Not verified:**
- dragging tabs by hand with `ClickMode.Press`;
- the ring in an AI session;
- Alt+Tab focus.

**Helper scripts (scratchpad):** `switch-tabs.ps1` now restores a minimized
window, because a relaunch remembered an off-screen position and came up
minimized, and UI Automation then finds no buttons. `settings-shot.ps1`
captures Settings off-screen.

## Part 8: "terminal is one colour" again, and keystroke errors

- **Environment checked directly.** I read each process's environment block
  from its PEB with the scratchpad `proc-env.ps1` (read-only).
  - Checked: dev app 42556, keeper 36460, worker 43192, and the session shell
    `cmd.exe` 40036.
  - None has `NO_COLOR`, `CLAUDECODE` or `GIT_*`; only `TD_DEV=1` is passed on.
  - So the leak is fixed. The user's only live session was **Command Prompt**,
    which prints in one colour by nature. Windows PowerShell 5.1 is also mostly
    one colour.
- **`errors.log` "[Terminal action] EndOfStreamException" on input.**
  - Cause: `KeeperEndpoint` drops the connection when `RequireLease` throws.
    That happens for a session that isn't Running (or no longer exists), for
    example the old "Claude Code" tab whose session ended in an earlier restart.
  - Typing into such a tab logs these errors and does nothing. That's upstream
    behaviour and possibly worth a small PR: show the tab as ended, or don't
    send input.
  - Correction: I first blamed `-KeepKeeper` (new app, older keeper). That's
    wrong. The protocol version, secret and instance were unchanged, so a kept
    keeper only matters when keeper code changes.

## Part 9: tab reordering

The user reported "reorder still not working" after 1a67cb7.

**Automated real-input test** (scratchpad):
- `setup-instance.ps1`: a fresh data2 instance with tabs W1, Command Prompt
  and PowerShell.
- `drag-test.ps1`: brings the window topmost and on-screen, does a SendInput
  drag, reads the tab order through UI Automation, then restores the cursor
  and puts the window back off-screen.

**Pitfalls:**
- My first INPUT struct was 48 bytes (two extra pad ints). SendInput failed
  with error 87 while SetCursorPos still worked; on x64 INPUT is **40 bytes**.
- **The PC was locked.** `WindowFromPoint` returned LockApp's
  "Windows Default Lock Screen" CoreWindow over the whole screen, so every
  synthetic click went there. The "no reorder" results, upstream included,
  prove nothing. Check `GetForegroundWindow` → LockApp before any input test.

**Change.** Commit d799055 on `fix/windows-smooth-tab-switch` replaces
`CanDrag` with in-strip sliding:
- `UIElement.Translation`, with a 150 ms `Vector3Transition` for the tabs the
  dragged one passes;
- `WorkspaceState.Move` on release;
- `StartDragAsync` when the pointer leaves the strip vertically, to keep
  pop-out and merge;
- a slide is cancelled on `PointerCaptureLost` only if no release follows,
  because the capture loss arrives before `PointerReleased`.

**Not yet verified with real input.** Run `drag-test.ps1` once the PC is
unlocked and the user agrees.

**Real-input test, run with the user's go-ahead.** These findings came from
diagnostic builds logging press, move, capture-lost, slide and focus changes:

1. **Inactive window.** The press activated the window, and
   `FocusInputOnActivation` moved focus to the terminal WebView2 while the
   button was held. The tab button lost focus, released capture after 15 ms,
   and the slide never started.
   - `InputKeyboardSource.GetKeyStateForCurrentThread(LeftButton)` does **not**
     report mouse buttons for pointer input, so the first fix (3e46c30) didn't
     help.
   - The real fix (5f45d1c) tracks presses on the window root: set on
     PointerPressed, cleared on release, cancel or deactivate.
2. **Harness.** `SetCursorPos` gives sparse pointer updates while a button is
   held; use absolute `SendInput` moves (`MOUSEEVENTF_MOVE|ABSOLUTE`, 0x8001)
   instead. Also, `GetGUIThreadInfo` showed no Win32 capture during a XAML
   pointer capture; delivery relies on implicit pointer capture.
3. **Harness.** A test window that starts minimized shows UI Automation zero
   elements. `setup-instance.ps1` now restores it and waits for the
   "New terminal tab" button.

**Result with the final combined build:**

| Test | Before | After |
|---|---|---|
| Drag PowerShell onto W1 (inactive window) | W1 \| CP \| PS | PS \| W1 \| CP |
| Drag W1 back | PS \| W1 \| CP | W1 \| PS \| CP |
| Other directions | | correct |
| Plain click | | selects without moving; terminal gets the cursor after release |

## Part 10: terminal tab naming and the "typing after a pause" glitch

**Naming.** Commit 8466fe2 on `feat/windows-terminal-shell`:
- Terminals opened by the user are titled with the project name, or the
  folder leaf outside a project.
- The tab and the sidebar `SessionPicture` show the shell program's own icon:
  the `ShellIcons` helper calls `StorageFile.GetThumbnailAsync` on
  cmd.exe / powershell.exe / pwsh.exe, cached.
- New local terminals record `Shell = "powershell"` explicitly. Sessions with
  `Shell == null` (old ones, remote servers) keep the generic glyph.
- Verified in data2: tabs read "admin" with the black cmd icon or the blue
  PowerShell icon, and the sidebar shows the icon, "admin" and
  "Command Prompt".
- Tried and reverted: prefixing `WindowLocationLabel` with the shell. That
  label feeds the pane header's *folder chip*, which shows only the last path
  segment and is announced as "Project folder: …".

**Typing glitch.** The user reports: in cmd and PowerShell tabs, after pausing
a few seconds, the next key lands one cell back, so a trailing space vanishes
or the previous letter is replaced.
- **Not reproduced** in a fresh data2 instance, either by DevTools
  `Input.insertText` or by real SendInput keys with an 8–12 s pause. Inputs
  were exactly the typed characters (no BS/DEL); there was no reset, replay
  or resize during the pause; the screen showed `echo a b` correctly.
- Not system-wide: the HKCU Input settings for hardware-keyboard prediction
  and autocorrect are unset, the only layout is en-US, and no text expander
  is running. PowerToys runs, but not Quick Accent or Keyboard Manager.
- **Hypothesis:** the user's sessions went through several app restarts with
  `-KeepKeeper`. Each reattach rebuilds the screen from a replay, which the
  code admits "can sit a cell away". Also suspect: Edge text input (TSF) with
  real typing habits.
- **Diagnostics:** the user's dev window (`local/try-all` plus the
  uncommitted `typing-diag.patch.lf` and `TdTiming-mask.cs` in the scratchpad)
  logs input and keeper events with printable characters masked to
  `.`/`_`, keeping control and escape sequences, to
  `%TEMP%\td-timing-<pid>.log`.
  - Ask the user for a time when it happens, then look for
    BS/DEL/ESC sequences, reset, replay or resize around it.
  - **Remove the diagnostics before any PR build.** They're local only.
- The hypothesis above was wrong; see Part 11.

## Part 11: the cause of the typing glitch, Windows 10 ConPTY and C0 controls

The user confirmed it happens inside Terminal Deck's PowerShell and Command
Prompt tabs. The masked log caught it: every affected tab was running
**Claude Code**. After a pause, the first keystroke produced this output:

```
input  .                      (the typed letter)
event  ESC[?2004h<0F>         (Claude Code's redraw: bracketed paste on, then a raw SI)
event  <BS>.                  (ConPTY: back one column, then the letter)
```

**Cause, reproduced outside the app** (`scratchpad\si-probe\probe.cs`
hosts the inbox ConPTY and prints its output):
- Windows 10's conhost (19041 branch) stores most C0 controls as **cells**,
  the CP437 glyphs (SI = ☼), instead of running or dropping them. Newer
  console hosts reportedly drop them. Not checked here: there's no
  Windows 11 machine.
- In **code page 65001** (Claude Code selects it) ConPTY forwards the raw
  byte and counts it as one column. In 437 it sends the glyph (`☼`), which
  is harmless.
- xterm.js treats SI/SO as charset shifts and VT/FF as line feeds, and
  ignores the rest. None of them take a column, so the terminal is one column
  behind ConPTY, and ConPTY's next `BS` lands one cell too far left.
- The affected set, measured: 0x01–0x06, 0x0B, 0x0C, 0x0E–0x1A, 0x1C–0x1F.
  NUL, BEL, BS, TAB, LF, CR, ESC and DEL take no cell.

**Fix, on `fix/windows-conpty-control-cells` (95711de):**
- New `ConPtyControlCells`: on Windows builds below 22000 only, the ConPTY
  output pump rewrites those bytes to a space, in place. A C0 byte never
  occurs inside a UTF-8 sequence, so each chunk can be handled alone.
- Tests are in `Tests\ConPtyControlCellTests.cs` (TerminalDeck.Windows.Tests):
  the byte map, escape and UTF-8 passthrough, and an end-to-end run of
  PowerShell under ConPTY with `chcp 65001`. The end-to-end test **fails
  without the fix**.
  Run them with
  `dotnet test src\TerminalDeck.Platform.Windows\Tests\TerminalDeck.Windows.Tests.csproj --filter "FullyQualifiedName~ConPtyControlCellTests|FullyQualifiedName~TerminalIoTests"`.
  The build needs `windows\docs\contracts` copied into the worktree.
- **In the real app** (data2), `idle-redraw.js` mimics Claude Code: it writes
  "ab ", pauses, writes `ESC[?2004h` plus SI, then `\b` plus "c".
  - Unfixed keeper: `CELLTEST abc END`, the space eaten exactly as reported.
  - Fixed keeper: `CELLTEST ab c END`.

**Gotchas found on the way:**
- The fix lives in the **session worker** (keeper bundle). A build with
  `-p:OutDir=<scratch>` copies the keeper from `TerminalDeck.Keeper\bin\...`
  (`CopyKeeper`), which a global OutDir doesn't update. Build
  `TerminalDeck.Keeper.csproj` first.
- The keeper runs from `bin\...\keeper\<bundle id>`, so `-KeepKeeper`
  rebuilds never reach running sessions. New terminals get the fix only
  after a keeper restart, which ends the open terminals.
- `ScreenForProofAsync` reads `document.body.innerText`. That is empty with
  the WebGL renderer, so read results from a `PrintWindow` screenshot.
- The fix branch was built in a separate worktree,
  `C:\TD\wt\conpty-control-cells`, so the uncommitted diagnostics in the main
  checkout stayed put.

## Part 12: "session ended" notice, and the push

**Context.** After the dev keeper restart, the user "couldn't type". They were
typing into the old tabs, whose sessions had ended (state Exited), but the
tabs still showed their last screen with nothing saying so.

**Fix on `fix/windows-session-ended-notice` (caae39b):**
- `SessionPane` shows a notice that stays up until dismissed: "This session
  has ended, so typing here does nothing. Open a new tab to keep working."
  Typing into the tab brings it back and no longer sends input.
- **Found on the way (upstream bug).** A shell that exits on its own reaches
  the pane as a `reset` event, from `RestoreWorkerReplayAsync`. The pane only
  refreshed on `exit` and `status`, so the UI never learned the shell had
  ended, and the sidebar kept it under Running. It now refreshes on `reset`
  too.
- **Tested in data2**, by ending the shell process from outside (Stop-Process
  on the worker's child):
  - restarting the app shows the notice on attach;
  - a live exit shows it about 55 ms later, and the sidebar drops the tab
    from Running.
  - Temporary logging showed that before the `reset` change, no `State`
    change reached the pane.

**Pushed to origin** with the user's go-ahead ("add commit create pr"), all
based on upstream/main 169cd5e:

| Branch | Head |
|---|---|
| `fix/windows-titlebar-drag` | a8b0873 |
| `fix/windows-terminal-smooth-text` | b0e46c4 |
| `fix/windows-focus-terminal` | 5f45d1c |
| `fix/windows-smooth-tab-switch` | d799055 |
| `fix/windows-toolbar-icons-ring` | e79332c |
| `feat/windows-terminal-shell` | 8466fe2 |
| `fix/windows-conpty-control-cells` | 95711de |
| `fix/windows-session-ended-notice` | caae39b |

- No pair of branches conflicts (checked with `git merge-tree`), and
  `local/try-all` merges all eight and builds with 0 warnings.
- **The PRs aren't opened yet.** `gh pr create` on asadev was denied by the
  Claude Code permission classifier ("Create Public Surface"). The user runs
  `tools/create-draft-prs.ps1`, which takes titles and bodies from `prs/*.md`
  and skips PRs that already exist; `-DryRun` checks without creating.
- **Diagnostics removed** from `local/try-all`. They're kept in
  `tools/diag/` (moved there at wrap-up from the temporary scratchpad).
  The user's running dev app still has them until its next rebuild.

Later the same day the user said "open the PRs", and `tools/create-draft-prs.ps1`
opened #1–#8 as drafts. Then they said "mark them ready for review", and
`gh pr ready` ran for each one.

## Wrap-up: where things stand

State at the end of the session (2026-11-03, checked at wrap-up):

- **PRs.** asadev/terminaldeck #1–#8 are open and ready for review, with no
  comments or reviews yet. Branch heads are in the Part 12 table. Follow-up
  commits go on the matching branch, pushed only when the user says so.
- **Dev app** (`C:\TD\dev\data`). It runs from `local/try-all` 50908bf, which
  merges all eight branches, with the diagnostics removed. It was rebuilt with
  `-KeepKeeper`, so the keeper is still bundle `20261103154135211`. That
  bundle was built after the ConPTY fix and has it.
- **Local git.** `local/try-all` is clean. The worktrees under `C:\TD\wt` were
  removed at the user's request after checking they were clean and matched
  origin. The branches stay, locally and on origin. A new worktree for a PR
  follow-up needs `windows/docs/contracts` copied in (`make-local-contracts.ps1`).
  No data2 test instance is running.
- **Diagnostics** are in `tools/diag/`: the masked typing log patch,
  `TdTiming.cs`, and the ConPTY probe with its C0 test scripts.

Lessons for next time:
- `gh` under Windows PowerShell 5.1: `--jq` filters with quotes get mangled,
  so pipe `--json` to `ConvertFrom-Json` instead. `gh` writes success messages
  to stderr, which PowerShell shows as a red NativeCommandError even when it
  worked.
- Opening PRs on asadev is outward-facing. The Claude Code classifier blocks
  it unless the user has just asked for it.
- Natural shell exits reach the UI as `reset` events, not `exit` (Part 12).

## Next

- [x] Install .NET SDK 10.0.4xx
- [x] Update Windows App Runtime 1.8 to >= 8000.994.2142.0
- [x] First build (passes with the local contracts)
- [x] First launch, clean (with the 17 placeholder contracts)
- [x] Decide on a first PR: draggable title bar (`fix/windows-titlebar-drag`, committed locally)
- [x] User tries the title bar, then push it and open a draft PR upstream (PR #1)
- [x] User checks the fix branches in the dev app (from `local/try-all`), then push and open a PR per branch (#2–#8)
- [x] Shell choice setting (`feat/windows-terminal-shell`). Possible follow-up: a dropdown on the terminal + button to pick per tab
- [x] Open the 8 draft PRs on asadev, with the user's explicit go-ahead: asadev/terminaldeck #1 title bar, #2 smooth text, #3 focus, #4 tab switch and reorder, #5 icons and ring, #6 shell choice and tab names, #7 ConPTY control cells, #8 session ended. Dev window rebuilt with `-KeepKeeper` (diagnostics gone, notice in).
- [x] PRs #1–#8 marked ready for review at the user's request
- [ ] Watch the PRs for maintainer feedback. Run `gh pr list --repo asadev/terminaldeck --author umermalik129`, and `gh pr view <n> --comments` for each.
- [ ] Open question, noted in the `fix/windows-smooth-tab-switch` PR: `errors.log` has 2 unhandled `ArgumentException: Choose an open window tab.`. They come from `WorkspaceState.Focus` via `pane.GotFocus` in `RenderNode` (upstream has the same handler), at 13:28 UTC while sessions were dying under restarts. Check whether cached pane sets let a closed tab's pane take focus.
- [x] Dev keeper restarted with the typing-after-a-pause fix (`fix/windows-conpty-control-cells`, PR #7)
- [ ] User confirms the typing glitch is gone when using Claude Code in a new tab over several days. After the restart they said "looks good so far", but haven't confirmed this glitch specifically.
- [ ] Possible upstream report to Claude Code: it writes a raw SI on its idle redraw (repro: `tools/diag/conpty-probe/idle-redraw.js`)
- [ ] User tries tab reordering by hand. They had reported "tab reorder is not working": with `ClickMode.Press`, `FocusPane` moved focus into the WebView2 synchronously inside the button's PointerPressed, and a pressed ButtonBase that loses focus releases capture, so `CanDrag` never starts. Fix: focus only on release, drop or key up. Synthetic real-mouse tests pass (PR #4 table), but **the user hasn't confirmed it by hand**. If it still fails, fall back to select-on-release (upstream behaviour).
- [ ] PowerShell input latency: each keystroke opens new pipes app→keeper→worker (`KeeperClient.cs:29-59`, `DurableSessionProcessKeeper.cs:91-109`); the global keeper `gate` holds across worker round trips
- [ ] Remaining tab-switch frame gaps (WebView2 reparenting)
- [ ] Check timings in a Release build
- [ ] Look into the ~12 s keeper start delay
- [ ] Install Visual Studio 2026 with the WinUI workload, or VS Code with C# Dev Kit
- [ ] Open an upstream issue about the missing `windows/docs/contracts/`
- [ ] Candidate PR: portable chat test fixtures, plus making `ChatCliConnection.DisposeAsync` safe when Start() failed
- [ ] Optionally install the pre-push hook
