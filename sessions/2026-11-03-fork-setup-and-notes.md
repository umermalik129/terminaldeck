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

## Next

- [ ] Install .NET SDK 10.0.4xx and Windows App Runtime 1.8 (elevated): see WINDOWS_DEV.md §1
- [ ] Install Visual Studio 2026 with the WinUI workload, or VS Code with C# Dev Kit
- [ ] First build. Confirm whether the missing contracts fail it, then apply the stub
- [ ] Open an upstream issue about the missing `windows/docs/contracts/`
- [ ] Optionally install the pre-push hook
