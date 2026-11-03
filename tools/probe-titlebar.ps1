# Read-only: asks the dev window's InputNonClientPointerSource child what each title-bar point is.
param([string]$DataDir = 'C:\TD\dev\data')
Add-Type -Namespace TdProbe -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
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
$r = New-Object TdProbe.Win+RECT; [void][TdProbe.Win]::GetWindowRect($top, [ref]$r)
$ri = New-Object TdProbe.Win+RECT; [void][TdProbe.Win]::GetWindowRect($inp, [ref]$ri)
"window ({0},{1}) {2}x{3}; non-client input child ({4},{5}) {6}x{7}" -f $r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top), $ri.Left, $ri.Top, ($ri.Right - $ri.Left), ($ri.Bottom - $ri.Top)
$names = @{ -1 = 'HTTRANSPARENT'; 0 = 'HTNOWHERE'; 1 = 'HTCLIENT'; 2 = 'HTCAPTION'; 8 = 'HTMINBUTTON'; 9 = 'HTMAXBUTTON'; 20 = 'HTCLOSE'; 12 = 'HTTOP' }
$points = @(@(60, 20, 'sidebar toggle icon'), @(200, 20, 'empty, above sidebar'), @(316, 20, '"Sessions" header'), @(600, 20, 'empty strip, middle'), @(1000, 20, 'empty strip, right'), @(1157, 16, 'minimize'), @(1249, 16, 'close'))
$w = $r.Right - $r.Left
foreach ($dx in 200, 186, 170, 160, 150, 140) { $points += , @(($w - $dx), 20, "width-$dx (drag column?)") }
foreach ($pt in $points) {
    $x = $r.Left + $pt[0]; $y = $r.Top + $pt[1]
    $res = [int][TdProbe.Win]::SendMessage($inp, 0x84, [IntPtr]::Zero, [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF)))
    "{0,-24} -> {1,3} {2}" -f $pt[2], $res, $names[$res]
}
