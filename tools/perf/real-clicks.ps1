# Real mouse clicks on the data2 test window: browser tab, then (optionally) a
# click inside the browser page, then a terminal tab; checks the terminal shows.
param([int]$Rounds = 8)
. C:\TD\scratch\tools\td2.ps1
if (-not ('Td2.Mouse' -as [type])) {
Add-Type -Namespace Td2 -Name Mouse -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@
}
if (-not ('Td2.At' -as [type])) {
Add-Type -Namespace Td2 -Name At -MemberDefinition '[StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; } [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(P p); [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags); [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);'
}
$w = Get-Td2Window
# Refuses to click anywhere that is not the test window.
function Click([int]$x, [int]$y) {
    $p = New-Object Td2.At+P; $p.X = $x; $p.Y = $y
    $under = [Td2.At]::GetAncestor([Td2.At]::WindowFromPoint($p), 2)
    if ($under -ne $w) { throw "Refusing to click at ${x},${y}: that point is not on the test window." }
    [void][Td2.Mouse]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 60; [Td2.Mouse]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 70; [Td2.Mouse]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero)
}
$saved = New-Object Td2.Mouse+POINT; [void][Td2.Mouse]::GetCursorPos([ref]$saved)
$prevForeground = [Td2.Fg]::Get()
try {
    if ([Td2.At]::IsIconic($w)) { [void][Td2.Native]::ShowWindow($w, 9) } # SW_RESTORE
    [void][Td2.Native]::SetWindowPos($w, [IntPtr](-1), 200, 80, 1400, 900, 0x0040) # HWND_TOPMOST for the test, SHOWWINDOW, on the primary display
    [void][Td2.Mouse]::SetForegroundWindow($w)
    Start-Sleep -Milliseconds 800
    if ([Td2.At]::IsIconic($w)) { throw 'The test window is still minimized; not clicking.' }
    $root = Get-Td2Root $w
    function Showing([string]$title) { $c = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty), "Session title: $title"; $null -ne $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c) }
    $tabs = Get-Td2Buttons $w | Where-Object { $_.Y -lt 130 }
    $browser = $tabs | Where-Object { $_.Name -like 'B1*' } | Select-Object -First 1
    $claude = $tabs | Where-Object { $_.Name -like 'Claude Code, *' } | Select-Object -First 1
    $shell = $tabs | Where-Object { $_.Name -like 'admin, PowerShell*' } | Select-Object -First 1
    if (-not $browser -or -not $claude -or -not $shell) { throw 'Tabs not found on the test window; not clicking.' }
    function Mid($b) { @([int]($b.X + $b.W / 2), [int]($b.Y + $b.H / 2)) }
    $results = @()
    foreach ($i in 1..$Rounds) {
        $intoPage = $i -le ($Rounds / 2)
        $target = if ($i % 2) { @{ B = $claude; T = 'Claude Code' } } else { @{ B = $shell; T = 'admin' } }
        $p = Mid $browser; Click $p[0] $p[1]; Start-Sleep -Milliseconds 600
        if ($intoPage) { Click 900 450; Start-Sleep -Milliseconds 400 } # inside the browser page (window spans 200-1600, 80-980)
        $p = Mid $target.B; Click $p[0] $p[1]; Start-Sleep -Milliseconds 700
        $ok = Showing $target.T
        if (-not $ok) { Save-Td2Shot $w "C:\TD\scratch\shots\real-fail-$i.png" | Out-Null }
        $results += '{0}: browser{1} -> {2}: {3}' -f $i, $(if ($intoPage) { ' + click in page' } else { '' }), $target.T, $(if ($ok) { 'ok' } else { 'NOT SELECTED' })
    }
    $results
} finally {
    [void][Td2.Native]::SetWindowPos($w, [IntPtr](-2), 0, 0, 0, 0, 0x0013) # HWND_NOTOPMOST (NOSIZE|NOMOVE|NOACTIVATE)
    Move-Td2 $w
    [void][Td2.Mouse]::SetCursorPos($saved.X, $saved.Y)
    if ($prevForeground -ne [IntPtr]::Zero) { [void][Td2.Mouse]::SetForegroundWindow($prevForeground) }
}
