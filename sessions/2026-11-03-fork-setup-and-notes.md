# Session 2026-11-03: fork setup, developer notes, Windows dev guide

- **Branch:** none (setup only). Notes are on `dev-notes`.
- **PR:** none
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

## Next

- [x] Install .NET SDK 10.0.4xx and Windows App Runtime 1.8
- [x] First build (passes with the local contracts)
- [ ] First launch: `.\.dev-notes\tools\run-windows-debug.ps1 -NoBuild`, then check `C:\TD\dev\data\logs\errors.log`
- [ ] Install Visual Studio 2026 with the WinUI workload, or VS Code with C# Dev Kit
- [ ] Open an upstream issue about the missing `windows/docs/contracts/`
- [ ] Candidate PR: portable chat test fixtures, plus making `ChatCliConnection.DisposeAsync` safe when Start() failed
- [ ] Optionally install the pre-push hook
