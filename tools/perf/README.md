# Tab-switch and frame measurement tools (session 2026-11-05)

These drive the **data2 test instance only** (`C:\TD\dev\data2`), built from a separate worktree. Never use them on the dev or installed app. Paths inside point at `C:\TD\wt\v021` and `C:\TD\scratch`; adjust before reuse.

| File | What it does |
|---|---|
| `td2.ps1` | Helpers: `Start-Td2`, `Stop-Td2App`, `Build-Td2` (set `$script:Td2Config`), `Get-Td2Buttons`, `Invoke-Td2`, `Save-Td2Shot` (PrintWindow), `Move-Td2` |
| `unminimize.ps1` | Restores the test window without activating it (SetWindowPlacement, SW_SHOWNOACTIVATE) |
| `tabprobe/` | `TabProbe --pid <app pid> --sequence 1,0,2 --rounds 3`: captures the window with Windows.Graphics.Capture, clicks tabs through UI Automation, reports click → strip change, content change and settled times. `--idle 2000` reports which pixels change while idle |
| `ab.ps1` | A/B of two variants of one build (it used a `TD_NODEFER` switch that is no longer in the code) |
| `nothrottle.ps1` | Opts a process out of EcoQoS power throttling (Windows 10 accepts only EXECUTION_SPEED) |
| `browser-repro.ps1`, `browser-repro3.ps1` | Browser tab → terminal tab, checks that a "Session title:" element appears |
| `real-clicks.ps1` | **Moves the real mouse.** Run only with the user's OK. It refuses any click that is not on the test window |

Pitfalls:
- **Off-screen capture.** Windows.Graphics.Capture returns a 0×0 item for a window that is entirely off-screen. `Move-Td2` leaves 1 px on screen.
- **Minimized window.** A minimized WinUI window has an empty UI Automation tree and no capture frames. `ShowWindow(SW_SHOWNOACTIVATE)` leaves it minimized; use `unminimize.ps1`.
- **Locked screen.** UI Automation `Invoke` takes about 2 s per call; results are invalid.
- **Focus.** A fresh `Start-Td2` launch takes the foreground until the user clicks elsewhere.
- **Browser tab showing.** The UI Automation tree is sometimes empty. Find the tabs while a terminal is showing and keep the elements.
- **Windows 10 frame rate.** WinUI frames come about 31 ms apart unless the process timer resolution is raised (see `FrameClock`).
