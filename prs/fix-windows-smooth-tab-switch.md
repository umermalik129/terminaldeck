## Windows: smoother tab switching, and reordering tabs by sliding them

### Problem

- **Switching tabs was slow and visibly janky.** One click rendered the whole window twice:
  1. `WorkspaceState.Select` published a layout change.
  2. Focusing the tab's owner changed the shell scope.

  Each `RenderWindows` pass rebuilt every tab chip (icons parsed from XAML, SVG pictures, menus) and all panes. Every terminal or page view was pulled out of its holder and put into a new one, so its WebView2 was reparented and redrew.

  Measured on Windows 10 in a Debug build with four terminal tabs:
  - the UI thread was busy for 47–105 ms per click;
  - the first new frame came 66–138 ms after the click;
  - the frames after that were 20–40 ms apart.
- **Tabs couldn't be reordered on Windows 10.** Reordering relied on a system drag-and-drop from the tab button (`CanDrag`) and on `DragOver` finding the `deck-workspace` DataPackage property.

### Change

**Switching** (`WorkspaceSurface.cs`, `ShellWindows.cs`):

- `WorkspaceSurface.Select` runs through a `Batch` callback, and the shell window defers `RenderWindows` until the batch ends, so a click renders once.
- `RenderWindows` keys the tab strip separately from the scope and layout. When only the scope or layout changed, it re-renders the panes and keeps the chips. A full rebuild still happens when tabs, identities, browser state or the page change.
- Each chip registers a restyle action: selected shape, divider, close button, title weight, ink and icon. `UpdateFocus` runs it, so the selection moves without a rebuild.
  - This also fixes the cheap `UpdateFocus` path, for example moving between split panes, which left the selected-tab shape on the previous tab.
- A chip's context menu is built as it opens, because its split items depend on the current layout.
- **The panes stay alive, as in a browser.** The surface keeps one rendered pane set per owner and per set of tabs shown, and a switch only toggles visibility.
  - A set is rebuilt when its pane tree changes (split, close, ratio), and all sets are dropped when the tabs change.
  - A view only moves between holders when another set needs it.
- **Tabs select on press** (`ClickMode.Press`), as in Chrome.
  - While the pointer is held, focus moves to the pane only on release, drop or key up. A pressed button that loses focus releases its pointer capture, which would kill the drag.

**Reordering:**

- Press a tab and move it along the strip: it follows the pointer, and the tabs it passes glide aside. This uses `UIElement.Translation` with a 150 ms `Vector3Transition`, so there are no layout passes.
- Releasing drops it into place with `WorkspaceState.Move`.
- Moving up or down off the strip hands the tab to a system drag (`StartDragAsync`). Dragging a tab out to its own window, or onto another window's strip, keeps working through the existing handlers.
- `PointerCaptureLost` arrives before `PointerReleased`, so a slide is only cancelled when no release follows.

### How it was tested

This was tested on Windows 10 22H2 (19045) with a Debug x64 build and a scratch `--user-data-dir`.

- **Switch timing**, same setup as above:
  - about 10 ms of UI-thread work per click (was 47–105 ms);
  - first new frame after 3–32 ms (was 66–138 ms).
- **Reorder**, with real mouse input, including a press in an inactive window (that case also needs `fix/windows-focus-terminal`):

| Action | Tab order before | Tab order after |
|---|---|---|
| Drag PowerShell onto W1 | W1 \| CP \| PS | PS \| W1 \| CP |
| Drag W1 back | PS \| W1 \| CP | W1 \| PS \| CP |
| Plain click | unchanged | unchanged: the tab is selected on press and the terminal gets the cursor on release |

**Open question.** The error log twice recorded `ArgumentException: Choose an open window tab.`. It came from the pane `GotFocus` handler in `RenderNode`, which is unchanged from main, while sessions were being torn down during testing. I haven't confirmed whether the kept pane sets make this more likely.

Not tested: Windows 11, a Release build, multi-monitor drags.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
