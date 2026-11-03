## Windows: keep ConPTY's column count when it forwards control characters

### Problem

On Windows 10, typing after a pause could land one column too far left. A trailing space disappeared, or the previous letter was replaced. It happened in PowerShell and Command Prompt tabs running Claude Code.

A masked output log caught the moment. After the pause, Claude Code's redraw sent `ESC[?2004h` and a raw SI (0x0F). ConPTY then sent `BS` and the typed letter.

Windows 10's console host (the 19041 branch, which every Windows 10 build uses) keeps most C0 control characters as cells. They show as the code page 437 glyphs, so SI is ☼; the host neither runs nor drops them. What happens next depends on the code page:

- **437:** ConPTY sends the glyph, and the terminal stays in step.
- **65001 (UTF-8):** Claude Code and other current tools select this code page. ConPTY forwards the **raw** control character and still counts it as one column.

xterm.js treats these characters as controls that take no column. SI and SO switch character sets, VT and FF move down a line, and the rest are ignored. So after one of them, the terminal sits a column to the left of where ConPTY thinks it is, and ConPTY's next relative move (here `BS`) lands one cell off.

These results come from the inbox ConPTY on Windows 10 19045, in code page 65001:

| Bytes | ConPTY output |
|---|---|
| 0x01–0x06, 0x0B, 0x0C, 0x0E–0x1A, 0x1C–0x1F | Raw, counted as one column |
| NUL, BEL, BS, TAB, LF, CR, ESC, DEL | No cell |

### Change

- **New `ConPtyControlCells`** (`windows/src/TerminalDeck.Platform.Windows/ConPtyControlCells.cs`) lists those bytes and rewrites them to a space.
- **`ConPtyProcess.Pump`** applies it to each chunk in place, on Windows builds below 22000 only.
  - A C0 byte never occurs inside a UTF-8 sequence, so chunk boundaries don't matter.
  - Escape sequences, BEL-terminated OSC and UTF-8 text pass through unchanged.
- **Other Windows versions are left alone.** Newer console hosts are reported to drop these controls, but I couldn't test that.

A blank is used rather than the ☼ glyph. The app meant the control to be invisible, and the cell is normally redrawn within milliseconds; with a blank there's nothing to flash.

### How it was tested

This was tested on Windows 10 22H2 (19045) with a Debug x64 build.

New tests are in `TerminalDeck.Windows.Tests` (`Tests/ConPtyControlCellTests.cs`):

- the exact byte map over all 256 values;
- escapes, line controls and UTF-8 text unchanged;
- end to end: `cmd` under `ConPtyTerminalFactory` runs `chcp 65001` and PowerShell writes `TDCELL` + SI + `END`. The terminal must receive `TDCELL END` and no raw SI. **This test fails without the change.** The existing `TerminalIoTests` still passes.

I also ran the app with a scratch `--user-data-dir`. A small Node script mimics Claude Code's input line: it writes `ab `, pauses, writes `ESC[?2004h` plus SI, then `\b` plus `c`.

| Keeper | Terminal shows |
|---|---|
| main | `CELLTEST abc END` (the space is eaten, as reported) |
| this branch | `CELLTEST ab c END` |

Not tested: Windows 11 (unchanged by design).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
