# Commit everything in .dev-notes and push the dev-notes branch to the fork (origin) only.
# Usage:  .dev-notes\tools\save-notes.ps1 "notes: session 2026-11-03 title bar fix"
param([string]$Message = "notes: update $(Get-Date -Format 'yyyy-MM-dd HH:mm')")

$ErrorActionPreference = 'Stop'
$notes = Split-Path -Parent $PSScriptRoot

$branch = git -C $notes rev-parse --abbrev-ref HEAD
if ($branch -ne 'dev-notes') { throw "Expected $notes to be on dev-notes, found '$branch'." }

git -C $notes add -A
git -C $notes diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host 'Nothing to commit in dev-notes.' }
else {
    git -C $notes commit -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'commit failed' }
}

git -C $notes push -u origin dev-notes:dev-notes
if ($LASTEXITCODE -ne 0) { throw 'push to origin failed' }
