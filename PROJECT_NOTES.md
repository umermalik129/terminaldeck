# Terminal Deck: developer notes (fork: umermalik129/terminaldeck)

Terminal Deck is a desktop workspace for AI coding agents. It runs Claude Code,
Codex CLI and Gemini CLI sessions side by side, with an embedded browser,
projects, tasks, servers, MCP tools for the agents, and a phone companion
connected through a relay. It is MIT-licensed. The maintainer is Asad Iqbal
(`asadev`). Upstream is `asadev/terminaldeck`, and at the time of writing it
has **one squashed commit** (`169cd5e`, v0.20.2, 2026-10-31).

Focus of this fork: **Windows-side changes**, sent upstream as PRs.

## The repo at a glance

There are three products, built from four codebases:

| Folder | Files | What | Language / stack |
|---|---|---|---|
| `windows/` | ~735 | **Native Windows app.** This is our focus. | C# 14, .NET 10, WinUI 3 (Windows App SDK 1.8), WebView2 |
| `macos/` | ~3150 | Native Mac app (`TerminalDeckNative` Swift package and its helpers) | Swift 6.2, SwiftUI, AppKit, WebKit |
| `src/` | ~2050 | The Electron app (main, preload, renderer), plus web pages the Mac app serves (`src/native-web`) and the headless/server host (`src/headless`) | TypeScript, React 19, Vite 7, electron-vite, xterm.js 6, node-pty, better-sqlite3 |
| `pwa/` | ~110 | Phone and browser client | TypeScript, React, Vite |
| `scripts/`, `build/`, `vendor/`, `native/win-confine/` | | Build and release helpers, artwork, the vendored `staysfixed` tarball, and `tdconfine.c` (a Windows confinement helper the Electron Windows build uses) | |
| `packages/name-claim/` | | An npm name reservation with no code | |

The native Windows app **does not consume** anything built from the root
TypeScript (pwa, headless or electron `out/`). The phone talks to it through
the hosted relay (`wss://relay.terminaldeck.dev`).

## The native Windows app (`windows/`)

### Projects

| Project | Kind | Role |
|---|---|---|
| `src/TerminalDeck.Core` | `net10.0` library, BouncyCastle | Platform-independent logic: sessions and the keeper wire protocol, projects, agents, tasks, servers, the MCP catalogue, Hoot, receiver, accounts, the relay, and the Noise "sealed channel" phone link. It builds on any OS. |
| `src/TerminalDeck.Platform.Windows` | `net10.0-windows10.0.19041.0` library | Windows services: ConPTY session workers, starting and attaching the keeper (`KeeperConnection.cs`, `DetachedProcess.cs`), named pipes, DPAPI, Credential Manager, OpenSSH, chat workers, and AI CLI launch planning (`WindowsProviderLaunchPlanner.cs`). **Read its `README.md` first**: it explains the lifetimes. |
| `src/TerminalDeck.Keeper` | Exe | A long-lived supervisor that **outlives the window**. It has three modes: supervisor (`--user-data-dir`), session worker (`--worker <key>`) and chat worker (`--chat-worker <key>`). There is one supervisor per data folder, enforced by a mutex. After building, it copies ToolBridge and Askpass next to itself. |
| `src/TerminalDeck.ToolBridge` | Exe | A stdio-to-HTTP MCP adapter. AI CLIs inside chats start it as their `deck-tools` MCP server, and it calls the app's local tool server (`App/Integration/AppToolServer.cs`). |
| `src/TerminalDeck.App` | WinExe, WinUI 3, **unpackaged** (`WindowsPackageType=None`), x64 and ARM64 | The UI. It starts in `App.xaml.cs` (`OnLaunched`) and the main window is `Views/ShellWindow`. `Integration/AppRuntime.cs` wires it together. The terminal is xterm.js in a WebView2 (`Views/SessionPane.cs` maps `terminal.deck.invalid` to `Assets/terminal`). |
| `tools/terminal-assets` | Node, esbuild | Builds `App/Assets/terminal/*`. The output is committed. |
| `tools/team-import` | Console | `td-team-import.exe --data-root <dir> [--plan team.json] [--old-app <dir>]` |
| `tests/*` | Mixed | xunit test projects, Windows-only integration tests, and "Proof" screenshot harnesses. See [WINDOWS_DEV.md](WINDOWS_DEV.md#6-tests). |

`TerminalDeck.slnx` contains only Core, Platform.Windows, App, Keeper and
Core.Tests. ToolBridge and the other test projects are built through project
references or by their own `.csproj`.

### How the processes fit together

```
TerminalDeck.App.exe  (WinUI window; single instance per data folder)
  │ named pipe Hello -> reuse, or take startup.lock and spawn detached
  ▼
<app>\keeper\<bundle-id>\TerminalDeck.Keeper.exe --user-data-dir <root>      (supervisor; survives app exit)
  ├── TerminalDeck.Keeper.exe --worker <key>        one per terminal session; owns its ConPTY and replay buffer
  └── TerminalDeck.Keeper.exe --chat-worker <key>   chat sessions; the AI CLI starts:
        └── tools-bridge\TerminalDeck.ToolBridge.exe --root <root> --chat <id>  ──HTTP──> App's local tool server
```

- `keeper-location.txt` next to the app exe names the current bundle id. Each
  build writes a new UTC-timestamped `keeper\<id>\` folder.
- After a rebuild, the app reattaches to whatever keeper is **already running**.
  That keeper is old code until you stop it.
- Isolation is per data folder: `namespace = sha256(upper(path))[..24]` scopes
  the instance key, the keeper mutex `Local\terminaldeck-keeper-<ns>`, the pipes
  `terminaldeck-chats-<ns>` and `terminaldeck-hoot-tools-<ns>`, and the
  Credential Manager targets `Terminal Deck/<ns>/...`.

### Data folder

- The default is `%LOCALAPPDATA%\TerminalDeck`, which
  `installed-data-root.json` can redirect. If a `terminaldeck-stable-channel`
  marker file sits next to the exe, the folder is forced to
  `%LOCALAPPDATA%\TerminalDeckStable`.
- In dev mode (`TD_DEV=1` or `TD_TEST=1`), `--user-data-dir <abs>` is
  **required** and the installed folders are refused.
- Layout: `state\*.json`, `keeper\` (locks, `supervisor.identity.json`,
  `workers\`), `accounts\<HomeId>\<provider>` (pointed to by
  `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `GEMINI_CLI_HOME`), `mcp\`
  (`actions.jsonl` is the audit trail), `chats\`, `logs\errors.log`, `tools\`
  and `receiver\`.

### Conventions upstream enforces (Windows side)

- `Directory.Build.props` sets `TreatWarningsAsErrors`, Nullable,
  ImplicitUsings and `LangVersion 14.0`. Builds must stay warning-free.
- Line endings are always LF (`.gitattributes` uses `* text=auto eol=lf`).
  This machine has `core.autocrlf=true` globally; `.gitattributes` overrides it,
  but make sure your editor does not save CRLF.
- Style is dense: long one-liners, records, and `sealed` everywhere. Match the
  surrounding code.
- "Proof" code is compiled into the shipped App (`App/Verification/*`) and
  switched on by `TD_*_PROOF` environment variables. Don't break those code
  paths, and don't leave the variables set.
- The PR template asks for **"did you look at it"**, meaning screenshots for
  visible changes, and for **origin of the code**: write code fresh, and never
  paste code from other projects.
- `Platform.Windows/README.md` notes that vendor docs were consulted but the
  implementations are original. Keep it that way.

### Gaps in the public repo

- **`windows/docs/` is missing.** The MCP contract JSONs embedded by
  `TerminalDeck.Core.csproj` and the docs that READMEs cite
  (`WIN-PROGRESS.md`, `WIN-PARITY-REQUESTS.md`) are not in the public tree. The
  build is expected to fail until that is fixed. See
  [WINDOWS_DEV.md §2](WINDOWS_DEV.md#2-known-blocker-missing-mcp-contract-files)
  for a local workaround. This is a good first upstream issue.
- No CI workflows ship in `.github/`; only issue and PR templates do.
- Many scripts assume the maintainer's lab PC: the `C:\TD\...` layout,
  `tools/win/*`, lane branches like `lane/win-v3b`, and a bare repo at
  `C:/TD/td-windows.git`.
- `windows/tools/terminal-assets` tests use a hard-coded macOS Chrome path.

## The Electron app at the root

`npm run dev` (electron-vite) runs the Electron app: `src/main`,
`src/preload` and `src/renderer`. `npm run dist:win` builds the NSIS
installer and a portable exe for Windows, both including
`native/win-confine/tdconfine.exe`. The changelog says
Windows downloads have stayed on **0.15.0** since the native Windows app
started. Recent releases are Mac only.

The PR template's strict rules apply here:
- Colours come from `src/renderer/styles/tokens.css`.
- Shortcuts go only in `src/renderer/keymap.ts`.
- The product name is defined only in `src/shared/brand.ts`.
- Each main-process feature exports one `registerXIpc(ipcMain)`.
- If the preload changes, update `.harness/stub.ts`. The `.harness/` folder is not in the public repo either.

Checks: `npm ci`, `npm run typecheck`, `npm test`. `npm test` is vitest
followed by two electron checks. `vitest.config.ts` explains the longer
Windows timeouts. `npm ci` also runs `electron-builder install-app-deps`,
which rebuilds node-pty and better-sqlite3 for Electron and may need the VS C++
build tools.

## The Mac app (`macos/`)

It is a Swift package, so it is macOS only. You cannot build it on this machine.
It is worth reading as the **reference implementation**: Windows aims for
parity with it, and `macos/TerminalDeckNative/Sources/TerminalDeckBackend/*Contracts*.swift`
and `*Catalogue*.swift` define the MCP tool catalogue that Windows mirrors.

## Where to look first for a Windows change

| You want to change | Start in |
|---|---|
| The window, tabs, panes, title bar, Mica | `App/Views/ShellWindow.xaml(.cs)`, `App/Views/Windows/*` (`WindowMaterials.cs`) |
| The terminal surface | `App/Views/SessionPane.cs` and `tools/terminal-assets` (rebuild assets) |
| The embedded browser | `App/Views/BrowserPane*` |
| Session lifetime, reattach, ConPTY | `Platform.Windows/SessionWorkerServer.cs`, `ConPtyTerminalFactory.cs`, `DurableSessionProcessKeeper.cs`, `Keeper/WindowsKeeperRuntime.cs` |
| Launching Claude, Codex or Gemini | `Platform.Windows/WindowsProviderLaunchPlanner.cs`, `Platform.Windows/Chats/WindowsChatLaunchPlanner.cs` |
| MCP tools agents can call | `Core/Mcp/McpCatalogue.cs`, `McpManager.cs`, `App/Integration/AppToolServer.cs`, `ToolBridge/Program.cs` |
| Startup, arguments, data folder | `App/App.xaml.cs`, `Core/Storage/AppDataRoot.cs`, `StableChannel.cs`, `InstalledDataRoot.cs` |
| Error logging | `App/Diagnostics/AppErrorLog.cs` (writes `logs/errors.log`), and `UiRecovery` |
| Updates | `App/Services/WindowsUpdateStatus.cs` (MSIX and App Installer aware) |
| Phone link | `Core/Remote/*`, `App/Integration/RemoteService.cs` |
