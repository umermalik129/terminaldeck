## Windows: draw toolbar icons at their 16 px size; Mac-sized usage ring

### Problem

- **Toolbar icons looked blurry.** They're 16-point drawings with 1.5-point rounded strokes, but `WorkspaceSurface.IconButton` drew them at 14 px.
  - At 0.875× every stroke lands between pixels, about 1.3 px wide, so each icon got one sharp edge and one soft edge.
  - The ellipsis shrank to specks.
  - The new-tab buttons next to them already used 16 px, so the two toolbars didn't match.
- **The plan-limits ring was smaller than on the Mac.**
  - Windows drew it 12 px across with the stroke inset. The Mac draws a 12 pt frame with a 2 pt line centred on its edge, about 14 pt across.
  - While checking, it only dimmed, where the Mac pulses.

### Change

- `IconButton` uses the drawings' own 16 px size.
- The ellipsis (`DeckIconCatalog`) is three solid 2.5-point dots instead of zero-length stroked segments.
- `UsageMeter`:
  - the ring is 14 px across, with a 2 px rounded line on one centre line for both track and arc;
  - its capsule is rounded to its height;
  - while checking, it pulses between full and 55% opacity (0.8 s, ease in-out). With Windows animations turned off, it just dims as before.

### How it was tested

This was tested on Windows 10 22H2 (19045) at 100% scaling with a Debug x64 build, using magnified screenshots:

- toolbar strokes are now a uniform width, and the ellipsis shows three round dots;
- the pane and new-tab toolbars match.

Not tested: the ring in an AI session with live limits, Windows 11, and scaling above 100%.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
