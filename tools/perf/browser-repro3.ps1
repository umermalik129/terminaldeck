# Unattached browser tab (W2, window in browser mode) -> terminal tab, via UI
# Automation; checks at 150 ms and 900 ms whether the terminal pane is showing.
param([int]$Rounds = 10, [string]$BrowserLike = 'W2*')
. C:\TD\scratch\tools\td2.ps1
$w = Get-Td2Window
$root = Get-Td2Root $w
function Tab([string]$like) { Get-Td2Buttons $w | Where-Object { $_.Y -lt 75 -and $_.Name -like $like } | Select-Object -First 1 }
function Click($b) { $b.Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
function Showing([string]$title) {
    $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty), "Session title: $title"
    $null -ne $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}
$browser = Tab $BrowserLike; $claude = Tab 'Claude Code, *'; $shell = Tab 'admin, PowerShell*'
if (-not $browser -or -not $claude -or -not $shell) { throw 'tabs not found' }
$late = 0; $never = 0
foreach ($i in 1..$Rounds) {
    $target = if ($i % 2) { @{ Tab = $claude; Title = 'Claude Code' } } else { @{ Tab = $shell; Title = 'admin' } }
    Click $browser; Start-Sleep -Milliseconds 800
    Click $target.Tab; Start-Sleep -Milliseconds 150
    $soon = Showing $target.Title
    Start-Sleep -Milliseconds 750
    $later = Showing $target.Title
    if (-not $soon -and $later) { $late++ }; if (-not $later) { $never++ }
    '{0,2}: {1} -> {2,-11}: at 150 ms {3}, at 900 ms {4}' -f $i, $BrowserLike.TrimEnd('*'), $target.Title, $(if ($soon) { 'shown' } else { 'NOT shown' }), $(if ($later) { 'shown' } else { 'NOT shown' })
}
"late: $late, never: $never, of $Rounds"
