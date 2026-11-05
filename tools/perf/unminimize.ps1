# Restores the data2 test window from minimized without activating it, at the
# usual 1 px-on-screen position (SetWindowPlacement, showCmd SW_SHOWNOACTIVATE).
. C:\TD\scratch\tools\td2.ps1
if (-not ('Td2.Place' -as [type])) {
Add-Type -Namespace Td2 -Name Place -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT { public int length, flags, showCmd; public POINT min, max; public RECT normal; }
[DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
[DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
'@
}
$w = Get-Td2Window
$p = New-Object Td2.Place+WINDOWPLACEMENT; $p.length = [Runtime.InteropServices.Marshal]::SizeOf($p)
[void][Td2.Place]::GetWindowPlacement($w, [ref]$p)
$p.showCmd = 4 # SW_SHOWNOACTIVATE
$p.normal.Left = -1399; $p.normal.Top = 40; $p.normal.Right = 1; $p.normal.Bottom = 940
[void][Td2.Place]::SetWindowPlacement($w, [ref]$p)
Start-Sleep -Milliseconds 500
Move-Td2 $w
"iconic=$([Td2.Place]::IsIconic($w))"
