# Start a PR branch from the latest upstream/main (never from dev-notes).
# Usage (from anywhere):  .dev-notes\tools\start-feature.ps1 fix/win-title-bar
param([Parameter(Mandatory = $true)][string]$Name)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$dirty = git -C $repo status --porcelain
if ($dirty) { throw "Main worktree has uncommitted changes. Commit or stash them first:`n$dirty" }

git -C $repo fetch upstream
if ($LASTEXITCODE -ne 0) { throw 'git fetch upstream failed' }

git -C $repo switch -c $Name --no-track upstream/main
if ($LASTEXITCODE -ne 0) { throw "Could not create branch $Name" }

Write-Host ""
Write-Host "On '$Name', based on upstream/main ($(git -C $repo rev-parse --short upstream/main))."
Write-Host "When ready:  git push -u origin $Name"
Write-Host "Then PR:     gh pr create --repo asadev/terminaldeck --base main --head umermalik129:$Name --draft"
