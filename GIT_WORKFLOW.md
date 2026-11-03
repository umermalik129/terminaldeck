# Git workflow: fork, upstream and private notes

## The three places code lives

| Name | URL | What goes there |
|---|---|---|
| `upstream` | `https://github.com/asadev/terminaldeck` | The original repo. We **never push** here; changes arrive only as PRs. Its push URL is set to `DISABLED-use-a-PR-from-origin`, so an accidental `git push upstream` fails. |
| `origin` | `https://github.com/umermalik129/terminaldeck` | Your fork. Feature branches get pushed here, and so does `dev-notes`. |
| `dev-notes` branch | origin only | These notes and the session logs. It is an **orphan** branch with no history shared with `main`, so it cannot be merged into a PR by accident. GitHub will not even open a PR from it, because the histories are unrelated. |

The fork is **public** (it is a fork of a public repo), so anything pushed to
`dev-notes` can be read by anyone. Never put tokens, keys or personal data in notes.

## How the folders are laid out on disk

```
C:\Users\admin\Projects\terminaldeck\            <- main worktree (main or a feature branch)
C:\Users\admin\Projects\terminaldeck\.dev-notes\ <- second worktree, always on dev-notes
```

- `.dev-notes/` is a `git worktree` of the same repository, so you commit there
  and it does not touch the branch checked out in the main folder.
- `.dev-notes/` is listed in `.git/info/exclude`, which is local-only and never
  committed. That means it does not appear in `git status` of the main
  worktree, and `git add -A` there will not pick it up. The repo's `.gitignore`
  is untouched, so upstream sees no change.
- Watch out: `git clean -fdx` in the main worktree may delete ignored folders.
  Commit and push notes first (`save-notes.ps1`). Committed notes are safe in
  `.git` even if the folder goes away; restore it with
  `git worktree prune; git worktree add .dev-notes dev-notes`.

## Daily flow

### 1. Start a change from fresh upstream

```powershell
.\.dev-notes\tools\start-feature.ps1 fix/windows-something
```

The script refuses to run if the main worktree is dirty. Otherwise it runs
`git fetch upstream` and then `git switch -c fix/windows-something --no-track upstream/main`.

Base PR branches on `upstream/main`. Never base them on `dev-notes`, and avoid
basing them on a stale `origin/main`.

### 2. Build, run as Debug, look at it

See [WINDOWS_DEV.md](WINDOWS_DEV.md).

### 3. Commit and push to the fork

```powershell
git add <files>
git commit -m "Windows: short imperative summary"
git push -u origin fix/windows-something
```

### 4. Open the PR against upstream

```powershell
# Opens a draft PR from umermalik129:<branch> into asadev:main
gh pr create --repo asadev/terminaldeck --base main --head umermalik129:fix/windows-something --draft --title "..." --body-file pr-body.md
# or review it in the browser first:
gh pr create --repo asadev/terminaldeck --base main --head umermalik129:fix/windows-something --web
```

Upstream's PR template is `.github/PULL_REQUEST_TEMPLATE.md`. Fill in
*What / Why / How to check / Checks / Did you look at it / Origin of the code*.
They care a lot about "did you look at it": attach a before/after screenshot
for anything visible. Keep `pr-body.md` outside the repo, or put it in
`.dev-notes/prs/`.

Follow-up commits pushed to the same branch on origin update the PR automatically.

### 5. Save the session notes (fork only)

```powershell
.\.dev-notes\tools\save-notes.ps1 "notes: 2026-11-03 fix/windows-something"
```

This commits everything in `.dev-notes/` and pushes `dev-notes` to origin only.

### 6. Keep the fork's main in sync

```powershell
gh repo sync umermalik129/terminaldeck --branch main      # GitHub-side fast-forward from upstream
git switch main; git pull --ff-only origin main
```

The fork's `main` should stay **identical** to upstream's main. Never commit to it directly.

## Optional safety hook

`tools/pre-push` refuses three things: any push to upstream, pushing
`dev-notes` anywhere except origin, and pushing a branch that contains
`.dev-notes/` files or `dev-notes` history. Install it once:

```powershell
Copy-Item .dev-notes\tools\pre-push .git\hooks\pre-push
```

Hooks live in the shared `.git/hooks`, so one copy covers both worktrees.
Bypass it with `git push --no-verify` if you ever need to.

## Upstream's history style

Upstream currently has a single squashed release commit (`169cd5e Terminal Deck
for Mac and Windows 0.20.2`). Expect the maintainer to squash-merge PRs. If
`upstream/main` moves while a PR is open, rebase your branch:

```powershell
git fetch upstream
git rebase upstream/main
git push --force-with-lease origin <branch>
```
