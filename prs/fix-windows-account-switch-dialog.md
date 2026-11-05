## Windows: open the Switch account dialog from the account chip

### Problem

Clicking the account chip in a session header (the email under the session title) did nothing except show "The window action could not finish. Try again." whenever at least one account existed. The dialog had never opened in that case; it only worked with no accounts at all.

`ShowAccountAsync` (`Views/ShellWindow.xaml.cs`) created one `feedback` TextBlock. It added it to every account row and then again below the list. A WinUI element can have only one parent, so the second `Add` threw `COMException 0x800F1000` ("No installed components were detected") before the dialog was shown. `WorkspaceSurface.Guard` caught it and showed only the generic notice, so nothing reached `logs/errors.log`.

### Change

- `ShowAccountAsync` adds the feedback line once, under the account rows and above "Manage accounts…". It stays collapsed until it has text, so an idle dialog has no gap.
- `WorkspaceSurface.Guard` logs exceptions it does not expect (anything other than `ArgumentException` or `InvalidOperationException`) to `logs/errors.log` through `UiRecovery.Log`. The notice is unchanged.

### How it was tested

This was tested on Windows 10 22H2 (19045) with a Debug x64 build and a scratch `--user-data-dir`. The test session was a Claude Code terminal session with one signed-in account.

| | Clicking the account chip |
|---|---|
| Before | Notice "The window action could not finish. Try again." With the logging change, `errors.log` shows `COMException (0x800F1000)` at `ShowAccountAsync`, line 437 |
| After | The Switch account dialog opens: "Default · <email>", "Current account", "Manage accounts…", Done. Nothing is logged |

Not tested: switching between two signed-in accounts (only one account was available), and the chip on a chat session, which opens the chat's own picker and is unchanged.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
