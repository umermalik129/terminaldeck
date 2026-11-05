# Clicks the browser tab, then a terminal tab, many times in the data2 test app,
# and checks after each terminal click that a terminal pane is showing.
param([int]$Rounds = 20, [int]$MinGap = 50, [int]$MaxGap = 800)
. C:\TD\scratch\tools\td2.ps1
$w = Get-Td2Window
$root = Get-Td2Root $w
function Tab([string]$like) { Get-Td2Buttons $w | Where-Object { $_.Y -lt 75 -and $_.Name -like $like } | Select-Object -First 1 }
function Click($b) { $b.Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
function Showing([string]$title) {
    $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty), "Session title: $title"
    $null -ne $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}
$browser = Tab 'B1*'; $claude = Tab 'Claude Code, *'; $shell = Tab 'admin, PowerShell*'
if (-not $browser -or -not $claude -or -not $shell) { throw 'tabs not found' }
$rand = New-Object Random 7
$failures = 0
foreach ($i in 1..$Rounds) {
    $target = if ($i % 2) { @{ Tab = $claude; Title = 'Claude Code'; Kind = 'same group' } } else { @{ Tab = $shell; Title = 'admin'; Kind = 'other group' } }
    Click $browser
    $gap = $rand.Next($MinGap, $MaxGap); Start-Sleep -Milliseconds $gap
    Click $target.Tab
    Start-Sleep -Milliseconds 900
    $ok = Showing $target.Title
    if (-not $ok) { $failures++; Save-Td2Shot $w "C:\TD\scratch\shots\repro-fail-$i.png" | Out-Null }
    '{0,2}: browser -> {1,-11} ({2}) after {3,3} ms: {4}' -f $i, $target.Title, $target.Kind, $gap, $(if ($ok) { 'ok' } else { 'NOT SELECTED' })
}
"failures: $failures of $Rounds"
