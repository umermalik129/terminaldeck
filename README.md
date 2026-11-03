# dev-notes (private working notes for umermalik129/terminaldeck)

This is an **orphan branch**. It shares no history with `main` and is never
merged or PR'd upstream. It holds developer notes and per-session logs for
working on the fork. Code changes go on feature branches cut from
`upstream/main`.

| File | What |
|---|---|
| [PROJECT_NOTES.md](PROJECT_NOTES.md) | Architecture and conventions of the repo, with the Windows app in depth |
| [WINDOWS_DEV.md](WINDOWS_DEV.md) | Set up this machine, build, run as Debug, debug with breakpoints, test, clean up |
| [GIT_WORKFLOW.md](GIT_WORKFLOW.md) | Fork, upstream and PR flow, and how these notes stay out of PRs |
| [sessions/](sessions/) | One file per working session (`YYYY-MM-DD-topic.md`); start from `_TEMPLATE.md` |
| `tools/start-feature.ps1` | New PR branch from fresh `upstream/main` |
| `tools/run-windows-debug.ps1` | Build Debug x64 and launch against `C:\TD\dev\data` (`-StopOnly`, `-Clean`, ...) |
| `tools/save-notes.ps1` | Commit these notes and push `dev-notes` to origin only |
| `tools/pre-push` | Optional git hook that blocks notes leaking upstream |

## Checkout on a new machine

```powershell
git clone https://github.com/umermalik129/terminaldeck.git
cd terminaldeck
git remote add upstream https://github.com/asadev/terminaldeck.git
git remote set-url --push upstream DISABLED-use-a-PR-from-origin
git fetch origin dev-notes
git worktree add .dev-notes dev-notes
Add-Content .git\info\exclude "/.dev-notes/"
```
