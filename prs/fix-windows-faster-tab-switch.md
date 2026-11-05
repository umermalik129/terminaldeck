## Windows: draw the new tab first, and switch from a browser window in one click

### Problem

- **Bookkeeping before drawing.** A tab click ran all of the selection's follow-up work before the window could draw the new tab:
  - the view model's `Selected`, which runs `SyncWindows` and `Refresh` and renders twice;
  - read marks, the account chip and navigation;
  - a sidebar refresh on every `WorkspaceState` change.

  With retained panes, that bookkeeping was most of the click.
- **Browser window → session tab.** With a browser window that belongs to no session selected (W1, W2…), the window is on the browser page. The page was part of the tab-strip key (`tabsStructure`), so moving back to sessions counted as a new strip. Every such click destroyed and rebuilt every chip, the pressed one included, and dropped every retained pane.

### Change

- **Bookkeeping after the frame.** `FocusWindow` still sets `workspaceOwner` at once, since the panes render from it. On the sessions page the rest waits until the frame showing the new tab has been drawn. `AfterNextFrame` waits for the second `CompositionTarget.Rendering`, and subscribing also guarantees that frame happens.
- **Browser page excluded.** On any other page, the browser page included, the bookkeeping still runs before rendering: it is what moves `Model.Page` back to sessions, and `Scope` depends on it.
- **Sidebar.** Refreshes after `WorkspaceState` changes wait for the frame the same way and are coalesced (`UpdateSidebarSessionsSoon`).
- **One key.** The sessions and browser pages share one tab-strip key, as they share one strip and one pane surface.

### How it was tested

This was tested on Windows 10 22H2 (19045) with five terminal tabs and a scratch `--user-data-dir`. I captured the window with Windows.Graphics.Capture and clicked tabs through UI Automation. Times run from the click to the first composed frame that shows the new content. Every tab was shown once first.

**Tab to tab** (Release x64, three fresh starts per build):

| | main | this branch |
|---|---|---|
| Tab strip changes (median) | 91.0 ms | 72.2 ms |
| Content settled (median) | 95.6 ms | 72.2 ms |
| Content settled (p90) | 103.9 ms | 97.3 ms |

Inside the app, the click's synchronous work fell from 11.8 to 7.2 ms. The new tab now appears in the first frame after the click instead of the second.

**Unattached browser window → terminal tab** (Debug x64, 16 switches). "Before" is this branch's first commit only. The full chip rebuild on this path is the same on main.

| | before | after |
|---|---|---|
| Content settled (median) | 101 ms | 75 ms |
| Content settled (p90) | 202 ms | 99 ms |
| Content settled (worst) | 287 ms | 106 ms |

The terminal showed within 150 ms of every click. Real mouse clicks between a session's browser tab and terminal tabs, eight rounds with and without a click inside the page first, all switched.

Not tested: Windows 11, detached tab windows, swarm layout.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
