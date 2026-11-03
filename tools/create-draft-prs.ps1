# Opens one draft PR on asadev/terminaldeck per pushed fork branch.
# Title = the "## " heading of .dev-notes/prs/<branch with / as ->.md, body = the rest.
# Skips a branch that already has an open PR. Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File .dev-notes\tools\create-draft-prs.ps1 [-DryRun]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$prs = Join-Path (Split-Path -Parent $PSScriptRoot) 'prs'
$branches = 'fix/windows-titlebar-drag', 'fix/windows-terminal-smooth-text', 'fix/windows-focus-terminal', 'fix/windows-smooth-tab-switch',
    'fix/windows-toolbar-icons-ring', 'feat/windows-terminal-shell', 'fix/windows-conpty-control-cells', 'fix/windows-session-ended-notice'
$bodies = Join-Path ([IO.Path]::GetTempPath()) 'td-pr-bodies'
New-Item -ItemType Directory -Force $bodies | Out-Null
foreach ($branch in $branches) {
    $name = $branch -replace '/', '-'
    $lines = [IO.File]::ReadAllLines((Join-Path $prs "$name.md"))
    if ($lines[0] -notmatch '^## ') { Write-Warning "${branch}: description has no '## ' title, skipped"; continue }
    $title = $lines[0].Substring(3)
    $bodyFile = Join-Path $bodies "$name.md"
    [IO.File]::WriteAllText($bodyFile, ((($lines | Select-Object -Skip 1) -join "`n").TrimStart("`n") + "`n"))
    $existing = gh pr list --repo asadev/terminaldeck --head $branch --state open --json url --jq '.[0].url'
    if ($existing) { "$branch -> already open: $existing"; continue }
    if ($DryRun) { "$branch -> would open: $title"; continue }
    $url = gh pr create --repo asadev/terminaldeck --base main --head "umermalik129:$branch" --draft --title $title --body-file $bodyFile
    "$branch -> $url"
}
