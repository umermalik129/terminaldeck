# Opens one PR on asadev/terminaldeck per pushed fork branch (draft unless -Ready).
# Title = the "## " heading of .dev-notes/prs/<branch with / as ->.md, body = the rest.
# Skips a branch that already has an open PR. Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File .dev-notes\tools\create-draft-prs.ps1 -Branches fix/a,fix/b [-Ready] [-DryRun]
# Branches must be named explicitly: upstream closes PRs once it ports them into a
# release, so an old list would open closed PRs again.
param([Parameter(Mandatory)][string[]]$Branches, [switch]$Ready, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
# powershell -File passes "a,b" as one string.
$Branches = @($Branches | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$prs =Join-Path (Split-Path -Parent $PSScriptRoot) 'prs'
$bodies = Join-Path ([IO.Path]::GetTempPath()) 'td-pr-bodies'
New-Item -ItemType Directory -Force $bodies | Out-Null
foreach ($branch in $Branches) {
    $name = $branch -replace '/', '-'
    $lines = [IO.File]::ReadAllLines((Join-Path $prs "$name.md"))
    if ($lines[0] -notmatch '^## ') { Write-Warning "${branch}: description has no '## ' title, skipped"; continue }
    $title = $lines[0].Substring(3)
    $bodyFile = Join-Path $bodies "$name.md"
    [IO.File]::WriteAllText($bodyFile, ((($lines | Select-Object -Skip 1) -join "`n").TrimStart("`n") + "`n"))
    $existing = (gh pr list --repo asadev/terminaldeck --head $branch --state open --json url | ConvertFrom-Json) | Select-Object -First 1
    if ($existing) { "$branch -> already open: $($existing.url)"; continue }
    if ($DryRun) { "$branch -> would open$(if (-not $Ready) { ' (draft)' }): $title"; continue }
    $draft = if ($Ready) { @() } else { @('--draft') }
    $url = gh pr create --repo asadev/terminaldeck --base main --head "umermalik129:$branch" @draft --title $title --body-file $bodyFile
    "$branch -> $url"
}
