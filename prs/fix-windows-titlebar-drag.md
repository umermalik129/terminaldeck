## Windows: make the whole empty title bar drag the window

### Problem

On Windows, only a fixed 48 DIP column just left of the minimize button moved the window. Everything else in the title-bar row didn't react:

- the empty space above the sidebar, beside the sidebar toggle;
- the margin before the first tab;
- the space after the new-tab buttons.

Dragging, double-click to maximize and Snap were all unavailable there, so in practice the window felt impossible to move. The cause is that `WorkspaceTitleBar` passed only `TitleDragRegion` (`ShellWindow.xaml`, `Width="48"`) to `Window.SetTitleBar`.

### Change

`WorkspaceTitleBar` (`windows/src/TerminalDeck.App/Views/Windows/WorkspaceTitleBar.cs`):

- It registers the **whole title-bar row** with `SetTitleBar`: `TitleBarRow` for the main window, and `header` for separate tab windows.
- It cuts each button and input in the row out as a `NonClientRegionKind.Passthrough` region through `InputNonClientPointerSource`, so tabs, the sidebar toggle, ×, + and Accounts keep normal input. The covered types are `ButtonBase`, `TextBox`, `PasswordBox`, `AutoSuggestBox` and `ComboBox`.
- It recomputes the regions after layout passes, which covers tabs opening, closing and resizing, the sidebar toggle and DPI changes. It only calls `SetRegionRects` when the regions differ from what Windows already holds.
- Tabs scrolled out of the strip are clipped to its `ScrollViewer`.
- An open menu or flyout over the row also gets a passthrough region, removed again on `Closed`, so it can't turn into a drag area.

The 48 DIP column stays as guaranteed grab space when the tab strip is full. The caption buttons, the top resize edge and the Settings and Devices windows are unchanged.

### How it was tested

This was tested on Windows 10 22H2 (19045) at 100% scaling with a Debug x64 build, using a scratch `--user-data-dir` and `TD_DEV=1`. The build had 0 warnings and wrote no `errors.log`.

I used a hit-test probe, a local script: it finds the title-bar buttons through UI Automation, then asks the window's `InputNonClientPointerSource` child what each point is, taking its window region into account. Passthrough regions are holes in that region.

| Layout | Before (main) | After (this branch) |
|---|---|---|
| 1 tab | Empty space beside the toggle, before the tabs and after the + buttons: **HTCLIENT** (no drag) | All of it: **HTCAPTION**. Toggle, tab, × and + buttons: HTCLIENT |
| 3 tabs, 7 tabs | n/a | Every tab and button HTCLIENT, every empty gap HTCAPTION |
| 19 tabs (icon-only) | n/a | Holes cover the toggle, the whole tab strip and the + buttons; the rest drags |
| Sidebar collapsed | n/a | Regions follow the new layout |
| Minimize / close | HTMINBUTTON / HTCLOSE | Unchanged |

Not tested yet: Windows 11, scaling above 100%, and dragging a popped-out tab window by hand.

### Screenshots

(before/after: to add)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
