## Windows: put the cursor in the active terminal on activation and tab switch

### Problem

You had to click into the terminal before you could type, in two situations:

- **Returning to a window** with Alt+Tab, the taskbar or a click on the title bar. WinUI doesn't give focus back to a WebView2 when its window activates, so keyboard focus went nowhere.
- **Selecting a tab.** The switch rebuilds the panes, and `FocusPane` ran before the new pane frame had loaded, so its WebView2 wasn't in the visual tree yet.

### Change

- **New `ShellActivationFocus.cs`.** When a window activates, it focuses the active tab's input (the terminal, chat composer or browser). It does nothing when:
  - focus is already in a text field;
  - a dialog, menu or flyout is open;
  - the main window shows a page instead of tabs;
  - a mouse button is held. That press is a click into an inactive window, and moving focus would cancel it. For example, a pressed tab button that loses focus releases its pointer capture, so a tab drag started in an inactive window failed. Presses are tracked on the window root, because `InputKeyboardSource.GetKeyStateForCurrentThread` doesn't report mouse buttons for pointer input.
- **`FocusPane` waits briefly for the pane frame's `Loaded`**, since a later rebuild may replace the frame.
- **A new terminal whose page is still loading** takes the cursor once it reports ready, if its WebView2 already has focus.

### How it was tested

This was tested on Windows 10 22H2 (19045) with a Debug x64 build and a scratch `--user-data-dir`:

- Activating the window puts the cursor in the active terminal, so typing works without a click.
- Clicking another tab gives that tab's terminal the cursor.
- With real mouse input, pressing a tab in an inactive window and dragging it still reorders tabs. The reorder itself comes from the tab-strip PR (`fix/windows-smooth-tab-switch`).

Not tested one by one: Alt+Tab vs taskbar vs title-bar activation, switching tabs by keyboard, and focus kept in a text field or open menu. Also not tested: Windows 11.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
