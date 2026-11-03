## Windows: choose the terminal shell; name tabs after their project or folder

### Problem

- Terminal tabs always started Windows PowerShell 5.1 (`powershell.exe -NoLogo -NoProfile`), with no way to pick PowerShell 7 or Command Prompt.
- A new terminal tab was titled with its shell ("PowerShell"), so several terminals looked alike, and the title didn't say where each one works.

### Change

**Shell choice**

- **Settings → General** gets a "Terminal shell" option:
  - Windows PowerShell, the default;
  - PowerShell 7, selectable only when `pwsh.exe` is on PATH or under `Program Files\PowerShell\7`;
  - Command Prompt.
- **New terminals the user opens** (the + button, the New session picker, project menus) record the choice in the new `SessionDefinition.Shell`. All of these go through `StartShellForProjectAsync`.
  - A tab keeps its shell when the setting changes or the keeper restarts.
  - Agents, MCP tools and proofs still start Windows PowerShell, which their commands are written for.
- **`WindowsProviderLaunchPlanner`** starts:
  - `cmd.exe` from System32;
  - `pwsh.exe` with `-NoLogo -NoProfile`, like Windows PowerShell;
  - or, when PowerShell 7 is missing, explains that instead.
- **`SessionDefinition.Validate`** allows `Shell` only on local terminals, and only with known values. Sessions and settings saved before this change read as Windows PowerShell.

**Tab names and icons**

- Terminals the user opens are named after their project, or after their folder outside a project ("admin" for `C:\Users\admin`).
- The tab and the sidebar row show the real icon of the program the terminal runs. `ShellIcons` reads it once from the program file and shares it.
- The sidebar subtitle and the picker name the shell ("Command Prompt", "PowerShell 7").
- Sessions that don't record a shell (older or remote terminals) keep the generic terminal glyph.

### How it was tested

This was tested on Windows 10 22H2 (19045) with a Debug x64 build and a scratch `--user-data-dir`:

- **New tests:** `TerminalShellTests`, 12 passing (labels, validation, old JSON, round trip). The set of failing `TerminalDeck.Core.Tests` is the same as on main; those failures already happen on Windows.
- **Command Prompt:** with it selected, + opens `cmd.exe`, the tab reads "admin" with the Command Prompt icon, and the sidebar says "Command Prompt".
- **Back to Windows PowerShell:** new tabs open PowerShell with its icon, and existing tabs keep their shell.
- **PowerShell 7:** the option is disabled when `pwsh.exe` isn't installed, as on this machine.

Not tested: PowerShell 7 installed, Windows 11, remote terminals.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
