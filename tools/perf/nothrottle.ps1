# Opts one process out of Windows power throttling (EcoQoS and timer-resolution
# throttling), as if it were in the foreground. Used only on the data2 test app.
param([Parameter(Mandatory)][int]$ProcessId)
if (-not ('Td2.Power' -as [type])) {
Add-Type -Namespace Td2 -Name Power -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct State { public uint Version, ControlMask, StateMask; }
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetProcessInformation(IntPtr process, int infoClass, ref State info, int size);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
'@
}
$handle = [Td2.Power]::OpenProcess(0x0200, $false, $ProcessId) # PROCESS_SET_INFORMATION
if ($handle -eq [IntPtr]::Zero) { throw "OpenProcess failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$state = New-Object Td2.Power+State
$state.Version = 1; $state.ControlMask = 0x1; $state.StateMask = 0 # EXECUTION_SPEED off (IGNORE_TIMER_RESOLUTION is Windows 11 only)
$ok = [Td2.Power]::SetProcessInformation($handle, 4, [ref]$state, 12) # ProcessPowerThrottling
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); [void][Td2.Power]::CloseHandle($handle)
if (-not $ok) { throw "SetProcessInformation failed: $err" }
"power throttling off for $ProcessId"

