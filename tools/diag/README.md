# Diagnostics kept from session 2026-11-03

Local instrumentation only. Never commit any of this to a PR branch.

## Typing and timing logs

- `TdTiming.cs`: drop into `windows/src/TerminalDeck.App/`. It writes
  `%TEMP%\td-timing-<pid>.log`. `Mask()` turns printable text into `.`, so
  typed or shown words never reach the log; control characters and escape
  sequences stay readable.
- `typing-diag.patch`: hooks in `SessionPane.cs` that log terminal input and
  output through `TdTiming`. Apply with `git apply` on a scratch branch. The
  `TD_TYPING_PROBE` env var also starts a typing probe when the page is ready.

## ConPTY probe

`conpty-probe/probe.cs` runs a command under the inbox ConPTY (kernel32
`CreatePseudoConsole`) and prints what ConPTY sends, with control characters
spelled out. Put it in a fresh `dotnet new console` project and run it as
`probe node idle-redraw.js` from this folder.

- `idle-redraw.js` mimics Claude Code's idle redraw (`ESC[?2004h` plus SI).
  A terminal in step with ConPTY ends with `ab c`; one column off ends with `abc`.
- `child.js`, `c0.js`, `nul0.js`: other C0 control cases.

This is how the Windows 10 cause of the typing glitch was found (session log
Part 11, PR #7).
