## Windows: say when a terminal session has ended

### Problem

A terminal whose process had ended kept showing its last screen with no sign that it was over. Typing went nowhere, so the tab looked frozen. This happened in two cases:

- **After a keeper restart.** Every restored tab looked alive.
- **When a shell exited on its own.** The keeper reports that exit as a `reset` event carrying the worker's final replay (`SessionKeeper.RestoreWorkerReplayAsync`), not as `exit` or `status`. The pane refreshed sessions only on those two, so the app never learned that the shell had ended, and the sidebar kept listing it under Running.

### Change

`SessionPane.cs` and `SessionPane.Notices.cs`:

- **A notice in the ended tab:** "This session has ended, so typing here does nothing. Open a new tab to keep working."
  - It stays until dismissed, and comes back when the user types into the tab.
  - Typing there no longer sends input to the keeper.
- **At attach**, the pane checks the snapshot's state, so tabs restored after a restart say so right away.
- **Afterwards**, it follows the draft's `State`, acting only when the state crosses `exited`, because `Sync` raises `State` on every refresh.
- **The pane also refreshes sessions on `reset`**, so a shell that exits on its own updates the tab and the sidebar.

### How it was tested

This was tested on Windows 10 22H2 (19045) with a Debug x64 build and a scratch `--user-data-dir`:

| Case | Before | After |
|---|---|---|
| App restarted while its terminals' processes had ended | Last screen, no notice | Notice shown on attach; Running is empty |
| A terminal's shell process ends | Tab and sidebar still show it as running | The notice appears about 55 ms later, and the sidebar drops it from Running |

Not tested by hand: typing into an ended tab to bring the notice back; Windows 11.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
