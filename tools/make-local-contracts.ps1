# Recreate the MCP contract files that upstream's public tree is missing
# (windows/docs/contracts/*.json, embedded by TerminalDeck.Core.csproj:5-7).
# Without them the build fails with CS1566.
#
#   deck-tools-static-source.json       REAL: regenerated from the in-repo Swift sources
#                                       by upstream's windows/scripts/capture-source-contracts.py,
#                                       run from a temp copy with its source path fixed
#                                       (it expects ../td-native-shell/macos/..., which only
#                                       exists on the maintainer's machine).
#   deck-tools-runtime-source.json      EMPTY STUB: nothing in the repo generates it.
#   deck-tools-windows-integration.json EMPTY STUB: nothing in the repo generates it.
#
# The whole windows/docs/ folder is kept out of git through .git/info/exclude, so these files
# can never land in a PR. Once upstream publishes windows/docs/, delete the local copy
# and drop the exclude line.
#
# Usage:  .dev-notes\tools\make-local-contracts.ps1 [-Force]   (-Force also overwrites existing stubs)
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$win = Join-Path $repo 'windows'
$contracts = Join-Path $win 'docs\contracts'

if (git -C $repo ls-files -- windows/docs) {
    Write-Host 'windows/docs is tracked now (upstream published it). Nothing to do; remove the /windows/docs/ exclude line.'
    return
}

$exclude = Join-Path $repo '.git\info\exclude'
if (-not (Select-String -Path $exclude -SimpleMatch '/windows/docs/' -Quiet)) {
    Add-Content $exclude "# Local-only: MCP contract stubs/regenerated files (windows/docs is missing upstream)`n/windows/docs/" -Encoding ascii
}

$py = Get-Content (Join-Path $win 'scripts\capture-source-contracts.py') -Raw
$py = $py.Replace("root = Path(__file__).resolve().parents[1]", "root = Path(r'$win')")
$py = $py.Replace("'td-native-shell/macos/TerminalDeckNative/Sources/TerminalDeckBackend'", "'macos/TerminalDeckNative/Sources/TerminalDeckBackend'")
$py = $py.Replace("text = (source / filename).read_text()", "text = (source / filename).read_text(encoding='utf-8')")
$py = $py.Replace("target.write_text(json.dumps(output, indent=2, ensure_ascii=False) + '\n')", "target.write_text(json.dumps(output, indent=2, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')")
if ($py -notmatch "macos/TerminalDeckNative/Sources/TerminalDeckBackend'" -or $py -notmatch [regex]::Escape("Path(r'$win')")) {
    throw 'capture-source-contracts.py changed upstream; update the replacements in this script.'
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "td-capture-contracts-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    $script = Join-Path $tmp 'capture.py'
    [IO.File]::WriteAllText($script, $py)
    python -I $script
    if ($LASTEXITCODE -ne 0) { throw 'capture-source-contracts.py failed.' }
} finally { Remove-Item -Recurse -Force $tmp }

foreach ($n in 'deck-tools-runtime-source', 'deck-tools-windows-integration') {
    $f = Join-Path $contracts "$n.json"
    if ($Force -or -not (Test-Path $f)) {
        [IO.File]::WriteAllText($f, "{`"note`":`"LOCAL STUB - not in upstream's public tree. Do not commit.`",`"entries`":[]}`n")
        Write-Host "Wrote empty stub $n.json"
    }
}
Get-ChildItem $contracts | ForEach-Object { '{0,-40} {1,8:N0} bytes' -f $_.Name, $_.Length }
