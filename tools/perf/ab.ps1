# A/B of the deferred tab-switch bookkeeping in one Release build: alternates a
# run with TD_NODEFER=1 (old order) and one without, restarting the data2 app each time.
param([int]$Pairs = 3, [int]$Rounds = 3)
. C:\TD\scratch\tools\td2.ps1
$script:Td2Config = 'Release'
$probe = 'C:\TD\scratch\tabprobe\bin\Release\net10.0-windows10.0.19041.0\TabProbe.exe'
$results = @()
foreach ($pair in 1..$Pairs) {
    foreach ($variant in 'old', 'new') {
        Stop-Td2App
        $env:TD_NODEFER = if ($variant -eq 'old') { '1' } else { $null }
        $w = Start-Td2; $env:TD_NODEFER = $null
        Start-Sleep -Seconds 12
        $p = (Get-Td2Process).ProcessId
        # Warm up: show every tab once so first-show costs are out of the sample.
        & $probe --pid $p --sequence 1,2,3,4,0 --rounds 1 --settle 600 | Out-Null
        $out = & $probe --pid $p --sequence 1,0,2,3,0,4,1,2 --rounds $Rounds 2>&1
        foreach ($line in $out) {
            if ($line -match '-> tab \d+: invoke\s+([\d.]+) ms \| strip\s+([\d.]+) ms \| content first\s+([\d.]+) ms settled\s+([\d.]+) ms') {
                $results += [pscustomobject]@{ Variant = $variant; Invoke = [double]$Matches[1]; Strip = [double]$Matches[2]; First = [double]$Matches[3]; Settled = [double]$Matches[4] }
            }
        }
    }
}
function Stat($xs, $q) { $s = @($xs | Sort-Object); $s[[Math]::Min($s.Count - 1, [Math]::Floor($q * $s.Count))] }
foreach ($variant in 'old', 'new') {
    $r = @($results | Where-Object Variant -eq $variant)
    '{0}: n={1}  strip median {2:F1} | content first median {3:F1} | settled median {4:F1} p90 {5:F1} max {6:F1} | invoke median {7:F1}' -f $variant, $r.Count,
        (Stat $r.Strip 0.5), (Stat $r.First 0.5), (Stat $r.Settled 0.5), (Stat $r.Settled 0.9), ($r.Settled | Measure-Object -Maximum).Maximum, (Stat $r.Invoke 0.5)
}
