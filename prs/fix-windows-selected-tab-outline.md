## Windows: outline the selected tab

### Problem

Only its fill marked the selected tab, and the fill barely differs from the tab strip:

| Theme | Selected terminal tab (paper) | Tab strip (top bar) |
|---|---|---|
| Light | `#E8E8E8` | `#E9E9EE` |
| Dark | `#191919` | `#121212` |

In the light theme a selected terminal tab was practically invisible. In the dark theme it was hard to pick out.

### Change

- **A 1 px rim.** The selected tab also draws a rim along its top, sides and flared feet. It is open along the bottom, where the tab runs into its pane.
- **Shape.** `WorkspaceTabShape.Edge` builds the rim half a pixel inside `Outline`, so the stroke stays sharp at 100% scaling.
- **Colour.** The new `DeckTabRimBrush` is `#B4B4BC` in the light theme and `#56565C` in the dark theme. High contrast uses the window text colour.
- **Toggling.** The rim shows and hides with the selected shape, in `chipStyles`, so a tab switch still restyles in place without rebuilding chips.

### How it was tested

This was tested on Windows 10 22H2 (19045), 100% scaling, with a Debug x64 build and a scratch `--user-data-dir`. Magnified screenshots of the tab strip in both themes show the rim around the selected tab only, with crisp 1 px lines and the bottom open into the pane.

Not tested: high contrast, scaling above 100%, Windows 11.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
