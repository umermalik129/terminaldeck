## Windows: render at 60 fps on Windows 10

### Problem

On Windows 10 the app drew a frame about every 31 ms (32 fps) instead of every 16.7 ms. Tab switches, tab slides, scrolling and every transition ran at half rate.

WinUI 3 paces frames with the compositor clock on Windows 11. On Windows 10 it waits on a timer. At the default 15.6 ms timer resolution, each 16.7 ms wait lasts two ticks (31.25 ms). Since Windows 10 2004 the timer resolution belongs to the process that asks for it, so WebView2 raising its own doesn't help the app's frames.

### Change

New `FrameClock` (`Views/Windows/FrameClock.cs`), started in `App.OnLaunched`:

- **Scope.** Only on Windows 10, i.e. builds below 22000.
- **What it does.** It raises the process timer resolution to 1 ms (`timeBeginPeriod(1)`) while a Terminal Deck window is in the foreground. It restores it (`timeEndPeriod(1)`) when another app comes forward.
- **How it follows the foreground.** An out-of-context `EVENT_SYSTEM_FOREGROUND` WinEvent hook calls back on the UI thread, so it covers every app window without per-window wiring.

### How it was tested

This was tested on Windows 10 22H2 (19045) with a GTX 1080 at 60 Hz and a Release x64 build. The measure is the time between `CompositionTarget.Rendering` callbacks after a tab click.

| Timer resolution | Time between frames |
|---|---|
| Default | 30.6–31.2 ms |
| 1 ms (`timeBeginPeriod(1)` forced on in a scratch build) | 16.5–17.6 ms |

Tab-switch latency with the 1 ms timer: median 70.4 → 67.1 ms, p90 91.9 → 73.2 ms.

The foreground hook was checked by logging: it reports the app's own window coming forward and other windows taking over.

Not tested:
- Frame timing with the foreground-gated version itself. The measurements above forced the timer on, because the test window was kept in the background.
- Windows 11, where `FrameClock` does nothing by design.
- Power use.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
