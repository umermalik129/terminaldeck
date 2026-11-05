# Helpers for driving the data2 test instance only (never the dev or installed app).
#   . C:\TD\scratch\tools\td2.ps1; $w = Get-Td2Window; Move-Td2 $w; Save-Td2Shot $w C:\TD\scratch\shots\x.png
#   Get-Td2Buttons $w | ft; Invoke-Td2 $w 'Name substring'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
if (-not ('Td2.Native' -as [type])) {
Add-Type -Namespace Td2 -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
}
$script:Td2Data = 'C:\TD\dev\data2'

function Get-Td2Process {
    Get-CimInstance Win32_Process -Filter "Name='TerminalDeck.App.exe'" |
        Where-Object { $_.CommandLine -match [regex]::Escape($script:Td2Data) + '(["\\\s]|$)' } | Select-Object -First 1
}
function Get-Td2Window {
    $p = Get-Td2Process; if (-not $p) { throw 'data2 instance is not running' }
    $h = (Get-Process -Id $p.ProcessId).MainWindowHandle
    if ($h -eq 0) { throw 'data2 window not ready' }
    [IntPtr]$h
}
# One pixel column stays on screen (left edge of the primary display) and the
# window goes to the bottom of the z-order: Windows.Graphics.Capture returns an
# empty item for a window that is entirely off-screen.
function Move-Td2([IntPtr]$h, [int]$x = -1399, [int]$y = 40, [int]$width = 1400, [int]$height = 900) {
    [void][Td2.Native]::SetWindowPos($h, [IntPtr]1, $x, $y, $width, $height, 0x0010) # HWND_BOTTOM, NOACTIVATE
}
function Save-Td2Shot([IntPtr]$h, [string]$path) {
    $r = New-Object Td2.Native+RECT; [void][Td2.Native]::GetWindowRect($h, [ref]$r)
    $bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
    [void][Td2.Native]::PrintWindow($h, $dc, 2) # PW_RENDERFULLCONTENT
    $g.ReleaseHdc($dc); $g.Dispose()
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $path
}
function Stop-Td2App([switch]$IncludeKeeper) {
    $names = @('TerminalDeck.App.exe', 'msedgewebview2.exe'); if ($IncludeKeeper) { $names += 'TerminalDeck.Keeper.exe' }
    foreach ($n in $names) {
        Get-CimInstance Win32_Process -Filter "Name='$n'" | Where-Object { $_.CommandLine -match [regex]::Escape($script:Td2Data) + '(["\\\s]|$)' } |
            ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { } }
    }
    Start-Sleep -Milliseconds 800
}
$script:Td2Config = 'Debug'
function Build-Td2 {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($script:Td2Config -ne 'Debug') { dotnet build C:\TD\wt\v021\windows\src\TerminalDeck.Keeper\TerminalDeck.Keeper.csproj -c $script:Td2Config -p:Platform=x64 -v:q -nologo 2>&1 | Out-Null }
    $out = dotnet build C:\TD\wt\v021\windows\src\TerminalDeck.App\TerminalDeck.App.csproj -c $script:Td2Config -p:Platform=x64 -v:q -nologo 2>&1
    $out | Where-Object { $_ -match ' error |warning CS|Warn|Error\(s\)' } | Select-Object -First 15
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }
}
function Start-Td2([switch]$KeepFocus) {
    $exe = "C:\TD\wt\v021\windows\src\TerminalDeck.App\bin\x64\$($script:Td2Config)\net10.0-windows10.0.19041.0\TerminalDeck.App.exe"
    $toolVars = '^(NO_COLOR|FORCE_COLOR|NODE_DISABLE_COLORS|CLAUDECODE|CLAUDE_CODE_.+|CLAUDE_PID|GIT_EDITOR|GIT_ASKPASS|GIT_TERMINAL_PROMPT)$'
    foreach ($name in @(Get-ChildItem env: | Where-Object { $_.Name -match $toolVars } | ForEach-Object Name)) {
        if (-not [Environment]::GetEnvironmentVariable($name, 'User') -and -not [Environment]::GetEnvironmentVariable($name, 'Machine')) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    }
    $env:TD_DEV = '1'
    Start-Process -FilePath $exe -ArgumentList '--user-data-dir', "`"$($script:Td2Data)`"" -WorkingDirectory (Split-Path $exe) | Out-Null
    $w = $null; for ($i = 0; $i -lt 40 -and -not $w; $i++) { try { $w = Get-Td2Window } catch { Start-Sleep -Milliseconds 500 } }
    # A fresh launch takes the foreground. Minimizing hands activation back to the
    # window the user had; restoring with SW_SHOWNOACTIVATE keeps it in the back.
    # (A minimize-then-SW_SHOWNOACTIVATE hand-back left the WinUI window minimized; removed.)
    Move-Td2 $w; $w
}
function Get-Td2Root([IntPtr]$h) { [System.Windows.Automation.AutomationElement]::FromHandle($h) }
function Get-Td2Buttons([IntPtr]$h) {
    $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty), ([System.Windows.Automation.ControlType]::Button)
    (Get-Td2Root $h).FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond) | ForEach-Object {
        $b = $_.Current.BoundingRectangle
        if ($b.IsEmpty -or [double]::IsInfinity($b.X)) { return }
        [pscustomobject]@{ Name = $_.Current.Name; X = [int]$b.X; Y = [int]$b.Y; W = [int]$b.Width; H = [int]$b.Height; Element = $_ }
    }
}
function Invoke-Td2([IntPtr]$h, [string]$match) {
    $b = Get-Td2Buttons $h | Where-Object { $_.Name -like "*$match*" } | Select-Object -First 1
    if (-not $b) { throw "No button matching '$match'" }
    $b.Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $b.Name
}
