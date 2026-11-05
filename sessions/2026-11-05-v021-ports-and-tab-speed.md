# Session 2026-11-05: 0.21.2 follow-ups (tab speed, 60 fps, meters, account chip, tab outline)

- **Branches:** five PR branches cut from `upstream/main` 0b2f432 (0.21.2). Integration branch `local/try-021` in worktree `C:\TD\wt\v021`; `local/dev` in the main checkout is the same code (61c55fd)
- **PRs** (opened 2026-11-05, ready for review, each branch cut from 0b2f432):

  | PR | Branch | Commits |
  |---|---|---|
  | asadev/terminaldeck #9 | `fix/windows-account-switch-dialog` | 5ec4dac |
  | #10 | `fix/windows-header-meters` | 744a353 |
  | #11 | `fix/windows-selected-tab-outline` | 49219ae |
  | #12 | `fix/windows-faster-tab-switch` | 4db6e50, 4552247 |
  | #13 | `fix/windows-60fps-win10` | 5302c2f |

  Bodies are in `prs/`. Every branch compiles alone with 0 warnings. Shell tests: 74/76 on both the branches and upstream/main; the same 2 symlink tests (`ShellCommandsTests` QuickOpen…/FolderLinks…) fail on main.
- **Area:** windows/src/TerminalDeck.App

## Context

- **PRs #1–#8.** On 2026-11-04 asadev closed them unmerged, in the same second as a force-push of `main` (`base_ref_force_pushed`). The 0.21.2 notes port all eight and thank the user ("eight Windows ports"). Upstream publishes each release as one squashed commit, so contributions arrive as ports, not merges.
- **New base.** Upstream now ships `windows/docs/contracts`. The old local stubs are only needed for 169cd5e-era branches; they're backed up in `C:\TD\scratch\contract-stubs-169cd5e`.
- **What the user reported after updating to 0.21.2:**
  - tabs not smooth, with a delay when selecting a tab (in the dev build too);
  - the selected tab should stand out;
  - the CPU, RAM and Claude meters should share one design;
  - the email chip does nothing;
  - from a browser tab, a terminal tab click sometimes "does nothing, a second click works";
  - the installed app's icon differs from the dev build's.

## What changed (local/try-021)

| Commit | What |
|---|---|
| efeb179 | **Account chip.** `ShowAccountAsync` added one feedback TextBlock to every row and again below the list, so COMException 0x800F1000 fired before the dialog opened whenever ≥1 account existed. It's now added once. `WorkspaceSurface.Guard` also logs unexpected exceptions |
| eb2838d | **Meters.** `MeterRing` (14 px ring, 20 px capsule, neutral track) for CPU, memory, context and plan. `DesktopResourceMeter` builds each card once instead of every 2 s per loaded header |
| ecea1af | **Selected tab.** 1 px rim (`DeckTabRimBrush` #B4B4BC light / #56565C dark), open at the bottom |
| 16011aa | **Tab switch.** The selection's bookkeeping (`Model.Select`, read marks, account chip, navigation, sidebar) runs after the frame showing the new tab (`AfterNextFrame`) |
| 837e1f7 | **`FrameClock`.** On Windows 10, `timeBeginPeriod(1)` while an app window is in the foreground. WinUI 3 on Win10 waited on a 15.6 ms timer, so frames came about 31 ms apart (32 fps) |
| 61c55fd | **Browser window → session tab.** (a) 16011aa's deferral also applied on the Browser page, where `Scope` depends on `Model.Page`, so the click redrew the browser page; it now applies only on Sessions. (b) `tabsStructure` counted Sessions and Browser as different pages, so each such click rebuilt every chip and dropped every pane set; they now share one key |

## How it was checked

- **Builds.** Debug and Release x64, 0 warnings. Each PR branch compile-checked on its own.
- **Measurements.** Probe (`tools/perf/tabprobe`): Windows.Graphics.Capture on the data2 window, tabs clicked through UI Automation. Times run from the click to the composed frame.

| Measurement | Before | After |
|---|---|---|
| Tab → tab, Release, 3 fresh starts each: strip median | 91.0 ms | 72.2 ms |
| Tab → tab: content settled median | 95.6 ms | 72.2 ms |
| Tab → tab: p90 | 103.9 ms | 97.3 ms |
| Frame interval after a click, Release | 30.6–31.2 ms (default timer) | 16.5–17.6 ms (1 ms timer) |
| Browser window → terminal, Debug: median | 101 ms (with only 16011aa) | 75 ms |
| Browser window → terminal: p90 | 202 ms | 99 ms |
| Browser window → terminal: worst | 287 ms | 106 ms |

- **What the click costs** (Release, in-app logs): handler 11.8 → 7.2 ms. Before: `UpdateSidebarSessions` 4.3 ms on every `WorkspaceState` change, `Model.Select` (`SyncWindows` + `Refresh` twice) 1.8 ms Release / 5–9 ms Debug, and a second focus round via `pane.GotFocus`.
- **Ruled out:**
  - the per-tab terminal resize on switch: it only happens on a tab's first show after launch;
  - a continuous XAML render loop: the frame counter reads 001/002 at idle;
  - power throttling (no change with EcoQoS off);
  - Remote Desktop: it's a console session.
- **Account chip, before:** the error notice, and `errors.log` showed 0x800F1000 at line 437. **After:** the dialog lists the accounts.
- **Real mouse:** 8 rounds of a session's browser tab B1 → terminal, with and without a click inside the page, all switched.
- **The user's exact symptom** ("nothing happens, second click works") was not reproduced with test clicks.

## Icon difference (not fixable in this repo)

- **Dev build.** The exe and `AppWindow.SetIcon` use `Assets/icons/app.ico`. Its 16 and 32 px images are the deliberately simplified mark (`build/art/icon.mjs`, `simplifiedAt = size <= 32`): a white card with a blue spine.
- **Installed MSIX 0.21.2.** The manifest sets `Square44x44Logo = logo50.png`, with no targetsize variants. That's the full mark (dark tile, card, chevron) downscaled to 24 px with padding.
- **Where the fix belongs.** The packaging lives in the maintainer's release tooling, not in the repo. The fix would be targetsize logos generated by `icon.mjs`. Not raised upstream yet.

## Mistakes and dead ends

- **Shared bin.** A `-p:OutDir` build of the main checkout still copied `.xbf` files into the default `bin`, and the running dev app locked them. Nothing was overwritten. Work now happens in a separate worktree.
- **Focus and a minimized window.**
  - Each test-instance launch took the foreground until the user clicked elsewhere.
  - A "minimize, then SW_SHOWNOACTIVATE" hand-back left the WinUI window minimized.
  - The app saved and restored that minimized state.
  - The first real-click run therefore clicked the user's Claude Code console twice (QuickEdit "Select" mode). `real-clicks.ps1` now refuses clicks off the test window.
- **Lock screen.** UI Automation timings taken while the screen was locked (LockApp) were 2 s per call and discarded.
- **Patch encoding.** `git diff > file` in PowerShell 5.1 writes UTF-16, so `git apply` failed.
- **Dev window.** The dev app's "Finish the update" ran on its own while the user was idle (14:45) and the window didn't reopen. Sessions moved to the new keeper.

## Next

- [x] Push and open PRs #9–#13 (user: "if you are done commit and pr")
- [ ] Watch PRs #9–#13; upstream ports rather than merges
- [x] Dev window rebuilt at 61c55fd (`local/dev`). Its update step replaced the keeper at 20:52; the window stayed open and the sessions reopened
- [ ] User checks the dev window: tab switching, browser → terminal clicks, 60 fps while the window is active, meters, rim, account chip
- [ ] If "nothing happens" still occurs from a browser tab, get a real-mouse repro with the user's OK
- [ ] Icon: optionally propose targetsize MSIX logos to the maintainer (issue), with the user's go-ahead
- [ ] Possible accessibility bug: the UI Automation tree is sometimes empty while a browser tab shows
- [ ] Stop the data2 test instance and keeper when no longer needed
- [ ] The dev app's "Finish the update" after `-KeepKeeper` rebuilds restarts the keeper and closes the window; the dev window doesn't reopen by itself
