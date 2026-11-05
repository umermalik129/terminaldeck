## Windows: one look for the CPU, memory, context and plan meters

### Problem

The meters at the right of a session header were drawn three different ways:

| Meter | Ring | Background | Button |
|---|---|---|---|
| This PC CPU, memory (`DesktopResourceMeter`) | 12 px, coloured track | none | 36 × 36 toolbar button |
| Context window (`UsageMeter` strip) | 12 px, coloured track | none | no padding |
| Plan limits (`UsageMeter` ring) | 14 px, grey track | grey capsule | 26 × 20 |

Side by side they looked unrelated and were spaced unevenly.

`DesktopResourceMeter` also rebuilt each button's flyout (a new `Flyout` and three TextBlocks) on every two-second sample. It did that in every loaded header, hidden retained tabs included.

### Change

- **New `MeterRing` (`Views/Usage/MeterRing.cs`).** It draws every meter the same way: a 14 px ring with a 2 px line on a neutral track, in the same 20 px capsule. Each button is exactly its capsule, with the capsule's rounded hover. Only the fill colour differs: blue for CPU, green for memory, purple for context, orange or critical red for the plan.
- **Shared drawing.** `DesktopResourceMeter` and `UsageMeter` use it. A short context figure (text) sits in the same capsule at the same height.
- **Spacing.** Meters are 4 px apart in both controls and in the header row (`ShellWindows.WindowUsageMeter`).
- **Fewer rebuilds.** `DesktopResourceMeter` builds each card once and updates its text. It redraws a ring only when the rounded reading changes.

### How it was tested

This was tested on Windows 10 22H2 (19045), dark theme, 100% scaling, with a Debug x64 build on a Claude Code terminal session.

- **Size.** UI Automation bounds: CPU, memory and plan buttons are all 26 × 20, 4 px apart. Before, CPU and memory were 36 × 36 and the plan button 26 × 20.
- **Look.** Screenshots before and after show the three capsules identical apart from the fill.

Not tested: the context ring itself (the test session had no fresh context figure, so it stayed hidden; it uses the same helper), the light theme for this change, and high contrast.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
