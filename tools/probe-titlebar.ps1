# Read-only: asks the dev window which title-bar points drag the window.
#
# It finds every button in the title-bar row through UI Automation, then asks the
# window's InputNonClientPointerSource child what each point is. Passthrough
# regions are holes in that child's window region, so Windows never sends it a hit
# test there and the click goes to the XAML content: a point outside the region
# counts as HTCLIENT. Inside it, the answer to WM_NCHITTEST decides.
#   - at each button's centre: expected HTCLIENT (the click reaches the button)
#   - in each empty gap between them: expected HTCAPTION (drag, double-click, Snap)
# Exit code 1 if any point is not what it should be.
#
#   .dev-notes\tools\probe-titlebar.ps1
#   .dev-notes\tools\probe-titlebar.ps1 -DataDir C:\TD\dev\data2
param([string]$DataDir = 'C:\TD\dev\data', [int]$TitleDip = 40)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -Namespace TdProbe -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
[DllImport("user32.dll")] public static extern int GetWindowRgn(IntPtr h, IntPtr rgn);
[DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int a, int b, int c, int d);
[DllImport("gdi32.dll")] public static extern bool PtInRegion(IntPtr rgn, int x, int y);
[DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
public struct RECT { public int Left, Top, Right, Bottom; }
public static IntPtr FindDescendant(IntPtr parent, string cls) {
  IntPtr found = IntPtr.Zero;
  EnumChildWindows(parent, (h, l) => { var sb = new System.Text.StringBuilder(256); GetClassName(h, sb, 256); if (sb.ToString() == cls) { found = h; return false; } return true; }, IntPtr.Zero);
  return found;
}
'@
$proc = Get-CimInstance Win32_Process -Filter "Name='TerminalDeck.App.exe'" | Where-Object { $_.CommandLine -like "*$DataDir*" }
if (-not $proc) { throw "No dev TerminalDeck.App for $DataDir" }
$top = (Get-Process -Id $proc.ProcessId).MainWindowHandle
$inp = [TdProbe.Win]::FindDescendant($top, 'InputNonClientPointerSource')
if ($inp -eq [IntPtr]::Zero) { throw 'No InputNonClientPointerSource child window' }
$r = New-Object TdProbe.Win+RECT; [void][TdProbe.Win]::GetWindowRect($top, [ref]$r)
$scale = [TdProbe.Win]::GetDpiForWindow($top) / 96.0
$barBottom = $r.Top + [int]($TitleDip * $scale)
$y = $r.Top + [int](($TitleDip / 2) * $scale)
"window ({0},{1}) {2}x{3}, scale {4}, probing y={5}" -f $r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top), $scale, ($y - $r.Top)

$names = @{ -1 = 'HTTRANSPARENT'; 0 = 'HTNOWHERE'; 1 = 'HTCLIENT'; 2 = 'HTCAPTION'; 8 = 'HTMINBUTTON'; 9 = 'HTMAXBUTTON'; 12 = 'HTTOP'; 20 = 'HTCLOSE' }
$ri = New-Object TdProbe.Win+RECT; [void][TdProbe.Win]::GetWindowRect($inp, [ref]$ri)
function Hit([int]$x, [int]$y) {
    if ($x -lt $ri.Left -or $x -ge $ri.Right -or $y -lt $ri.Top -or $y -ge $ri.Bottom) { return 1 }
    $rgn = [TdProbe.Win]::CreateRectRgn(0, 0, 0, 0)
    try { if ([TdProbe.Win]::GetWindowRgn($inp, $rgn) -gt 1 -and -not [TdProbe.Win]::PtInRegion($rgn, $x - $ri.Left, $y - $ri.Top)) { return 1 } }
    finally { [void][TdProbe.Win]::DeleteObject($rgn) }
    [int][TdProbe.Win]::SendMessage($inp, 0x84, [IntPtr]::Zero, [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF)))
}

# Buttons whose box sits in the title-bar row and on screen.
$ua = [Windows.Automation.AutomationElement]::FromHandle($top)
$cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
$buttons = foreach ($e in $ua.FindAll([Windows.Automation.TreeScope]::Descendants, $cond)) {
    $b = $e.Current.BoundingRectangle
    if ($b.IsEmpty -or $b.Width -lt 1 -or $e.Current.IsOffscreen) { continue }
    if ($b.Top -ge $barBottom -or $b.Bottom -le $r.Top -or $b.Top -gt $y -or $b.Bottom -lt $y) { continue }
    if ($e.Current.ClassName -eq '' -and $e.Current.AutomationId -match '^(Minimize|Maximize|Close)$') { continue }
    [pscustomobject]@{ Name = $e.Current.Name; Left = [int]$b.Left; Right = [int]$b.Right }
}
$buttons = @($buttons | Sort-Object Left)

$rows = @()
foreach ($b in $buttons) {
    $res = Hit ([int](($b.Left + $b.Right) / 2)) $y
    $rows += [pscustomobject]@{ Where = "button: $($b.Name)"; X = [int](($b.Left + $b.Right) / 2) - $r.Left; Got = $names[$res]; Want = 'HTCLIENT'; OK = $res -eq 1 }
}
# Gaps between buttons, from the left border to the system caption buttons (~138 DIP).
# UI Automation reports a tab as its label only, and narrow unselected tabs hide
# their close button, so a gap inside the tab strip is really part of a tab
# (clickable); every other gap is empty title bar (drag).
$toolbar = '^(Toggle sidebar|New terminal tab|New browser tab|Scroll tabs left|Scroll tabs right|Accounts|Move back to main window)$'
$tabs = @($buttons | Where-Object { $_.Name -notmatch $toolbar })
$stripL = ($tabs | Measure-Object Left -Minimum).Minimum; $stripR = ($tabs | Measure-Object Right -Maximum).Maximum
$captionLeft = $r.Right - [int](138 * $scale)
$edges = @(@{ L = $r.Left; R = $r.Left + [int](8 * $scale) }) + @($buttons | ForEach-Object { @{ L = $_.Left; R = $_.Right } }) + @(@{ L = $captionLeft; R = $r.Right })
$covered = $edges | Sort-Object { $_.L }
$cursor = $covered[0].R
foreach ($e in $covered | Select-Object -Skip 1) {
    if ($e.L - $cursor -ge [int](8 * $scale)) {
        $mid = [int](($cursor + $e.L) / 2); $res = Hit $mid $y
        $span = "$($cursor - $r.Left)-$($e.L - $r.Left)"
        if ($tabs.Count -and $mid -gt $stripL -and $mid -lt $stripR) { $rows += [pscustomobject]@{ Where = "inside a tab, beside its label $span"; X = $mid - $r.Left; Got = $names[$res]; Want = 'HTCLIENT'; OK = $res -eq 1 } }
        else { $rows += [pscustomobject]@{ Where = "empty gap $span"; X = $mid - $r.Left; Got = $names[$res]; Want = 'HTCAPTION'; OK = $res -eq 2 } }
    }
    $cursor = [Math]::Max($cursor, $e.R)
}
$minX = $r.Right - [int](115 * $scale); $closeX = $r.Right - [int](23 * $scale)
$rows += [pscustomobject]@{ Where = 'system minimize'; X = $minX - $r.Left; Got = $names[(Hit $minX ($r.Top + [int](16 * $scale)))]; Want = 'HTMINBUTTON'; OK = (Hit $minX ($r.Top + [int](16 * $scale))) -eq 8 }
$rows += [pscustomobject]@{ Where = 'system close'; X = $closeX - $r.Left; Got = $names[(Hit $closeX ($r.Top + [int](16 * $scale)))]; Want = 'HTCLOSE'; OK = (Hit $closeX ($r.Top + [int](16 * $scale))) -eq 20 }
$rows | Sort-Object X | Format-Table Where, X, Got, Want, OK -AutoSize | Out-String -Width 200
$bad = @($rows | Where-Object { -not $_.OK }).Count
"{0} of {1} points as expected" -f ($rows.Count - $bad), $rows.Count
if ($bad) { exit 1 }
