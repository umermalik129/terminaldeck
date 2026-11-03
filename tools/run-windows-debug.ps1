# Build the native Windows app and launch it against a scratch data folder,
# so a dev run never touches %LOCALAPPDATA%\TerminalDeck (the installed app's data).
#
#   .dev-notes\tools\run-windows-debug.ps1                 # build Debug x64, restart app + keeper, launch
#   .dev-notes\tools\run-windows-debug.ps1 -NoBuild        # just relaunch
#   .dev-notes\tools\run-windows-debug.ps1 -KeepKeeper     # keep keeper/sessions alive (test reattach)
#   .dev-notes\tools\run-windows-debug.ps1 -StopOnly       # stop app + keeper (e.g. before F5 in Visual Studio)
#   .dev-notes\tools\run-windows-debug.ps1 -Clean          # stop everything, delete scratch data + its credentials
#   .dev-notes\tools\run-windows-debug.ps1 -DataDir C:\TD\dev\data2   # a second, isolated instance
#
# Works in Windows PowerShell 5.1 and PowerShell 7.
param(
    [string]$DataDir = 'C:\TD\dev\data',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [ValidateSet('x64', 'ARM64')][string]$Platform = 'x64',
    [switch]$NoBuild,
    [switch]$KeepKeeper,
    [switch]$StopOnly,
    [switch]$Clean,
    [switch]$CrashDiagnostics
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$win = Join-Path $repo 'windows'

if (-not ($DataDir -match '^[A-Za-z]:\\')) { throw "-DataDir must be an absolute path like C:\TD\dev\data (got '$DataDir')." }
$DataDir = [IO.Path]::GetFullPath($DataDir).TrimEnd('\')
$local = [Environment]::GetFolderPath('LocalApplicationData')
foreach ($forbidden in @((Join-Path $local 'TerminalDeck'), (Join-Path $env:USERPROFILE 'AppData\Local\TerminalDeckStable'))) {
    if ($DataDir.StartsWith($forbidden, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to use the installed app's data folder: $DataDir" }
}

# Same namespace id the app derives (Core/Storage/AppDataRoot.cs): sha256(upper(path))[..24]
function Get-TdNamespace([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($path.ToUpperInvariant()))
    (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 24)
}
$ns = Get-TdNamespace $DataDir

function Stop-TdProcesses([switch]$IncludeKeeper) {
    # WebView2 children carry --user-data-dir=<DataDir>\browser\..., so the same filter matches only ours.
    $names = @('TerminalDeck.App.exe', 'msedgewebview2.exe')
    if ($IncludeKeeper) { $names += 'TerminalDeck.Keeper.exe', 'TerminalDeck.ToolBridge.exe' }
    $pids = @()
    foreach ($n in $names) {
        Get-CimInstance Win32_Process -Filter "Name='$n'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match ([regex]::Escape($DataDir) + '(["\\\s]|$)') } |
            ForEach-Object { $pids += $_.ProcessId }
    }
    $identity = Join-Path $DataDir 'keeper\supervisor.identity.json'
    if ($IncludeKeeper -and (Test-Path $identity)) {
        $sup = (Get-Content $identity -Raw | ConvertFrom-Json).Pid
        $p = Get-Process -Id $sup -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -eq 'TerminalDeck.Keeper') { $pids += $sup }
    }
    foreach ($id in ($pids | Select-Object -Unique)) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        # WebView2 children exit on their own once the app is gone; that race is fine.
        if ($p) { Write-Host "Stopping $($p.ProcessName) ($id)"; try { Stop-Process -Id $id -Force -ErrorAction Stop } catch [Microsoft.PowerShell.Commands.ProcessCommandException] { } }
    }
}

if ($Clean) {
    Stop-TdProcesses -IncludeKeeper
    Add-Type -Namespace TdDev -Name Cred -MemberDefinition '[DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)] public static extern bool CredDelete(string target, int type, int flags);'
    foreach ($suffix in 'keeper/auth-v2', 'remote-host', 'remote-identity') {
        $target = "Terminal Deck/$ns/$suffix"
        if ([TdDev.Cred]::CredDelete($target, 1, 0)) { Write-Host "Deleted credential $target" }
    }
    # Exiting processes can hold files for a moment (WebView2 metrics, the keeper's locks).
    for ($try = 1; (Test-Path $DataDir) -and $try -le 10; $try++) {
        try { Remove-Item -Recurse -Force $DataDir -ErrorAction Stop; Write-Host "Deleted $DataDir" }
        catch { if ($try -eq 10) { throw "Could not delete ${DataDir}: $($_.Exception.Message)" }; Start-Sleep -Milliseconds 500 }
    }
    return
}

# A running app locks its exe, and a running keeper keeps serving old code after a rebuild.
Stop-TdProcesses -IncludeKeeper:(-not $KeepKeeper)
if ($StopOnly) { return }

$appProj = Join-Path $win 'src\TerminalDeck.App\TerminalDeck.App.csproj'
if (-not $NoBuild) {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        # Terminal opened before the SDK was installed: pick up the new PATH from the registry.
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    # -p:Platform is required: CopyKeeper reads ../TerminalDeck.Keeper/bin/$(Platform)/$(Configuration)/...
    dotnet build $appProj -c $Configuration "-p:Platform=$Platform"
    if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)." }
}

$outDir = Join-Path $win "src\TerminalDeck.App\bin\$Platform\$Configuration\net10.0-windows10.0.19041.0"
$exe = Get-ChildItem -Path $outDir -Recurse -Filter 'TerminalDeck.App.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) { throw "TerminalDeck.App.exe not found under $outDir. Build first." }

New-Item -ItemType Directory -Force $DataDir | Out-Null
# The app, its keeper and every terminal or AI session inherit this process's
# environment. Started from a tool shell (Claude Code sets NO_COLOR=1,
# GIT_EDITOR=true, GIT_TERMINAL_PROMPT=0, CLAUDECODE, CLAUDE_CODE_*), terminals
# lose colour, git commit gets an editor that exits at once, and a nested claude
# thinks it is a child session. Launch with the user's normal environment.
$toolVars = '^(NO_COLOR|FORCE_COLOR|NODE_DISABLE_COLORS|CLAUDECODE|CLAUDE_CODE_.+|CLAUDE_PID|GIT_EDITOR|GIT_ASKPASS|GIT_TERMINAL_PROMPT)$'
foreach ($name in @(Get-ChildItem env: | Where-Object { $_.Name -match $toolVars } | ForEach-Object Name)) {
    if (-not [Environment]::GetEnvironmentVariable($name, 'User') -and -not [Environment]::GetEnvironmentVariable($name, 'Machine')) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
}
$env:TD_DEV = '1'
if ($CrashDiagnostics) { $env:TD_CRASH_DIAGNOSTICS = '1' }
Write-Host "Launching $($exe.FullName)"
Write-Host "  data:      $DataDir  (namespace $ns)"
Write-Host "  error log: $DataDir\logs\errors.log"
Start-Process -FilePath $exe.FullName -ArgumentList '--user-data-dir', "`"$DataDir`"" -WorkingDirectory $exe.DirectoryName
