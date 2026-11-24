param(
    # Each step is "label|cmd;cmd;..." (commands for CrowdDiag's cmd.txt; empty = measure only).
    [Parameter(Mandatory)][string[]]$Steps,
    [int]$Settle = 20,
    [int]$Measure = 70,
    [string]$OutDir = ''
)
# Ablation driver for the test client: per step, send CrowdDiag commands + 'count', wait $Settle s,
# then measure $Measure s: FPS (server log "sample ... ticks/s" lines inside the window) and CPU use of
# the busiest named threads. Reports CPU ms per frame per thread = thread % of one core x frame time.
$ErrorActionPreference = 'Continue'
if (-not ('AB.Native' -as [type])) {
Add-Type -Namespace AB -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr OpenThread(uint access, bool inherit, uint id);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(System.IntPtr h);
[DllImport("kernel32.dll")] public static extern int GetThreadDescription(System.IntPtr h, out System.IntPtr desc);
[DllImport("kernel32.dll")] public static extern System.IntPtr LocalFree(System.IntPtr p);
'@
}
# Set these three to your own layout: the test client's UE4SS folder, the local server's log, the output root.
$ue4ss = $env:CROWDTEST_UE4SS      # folder that holds UE4SS.log and Mods\CrowdDiag
$slog = $env:CROWDTEST_SERVER_LOG  # the local server's hogwarts-mp.log
if (-not $ue4ss -or -not $slog) { 'Set CROWDTEST_UE4SS and CROWDTEST_SERVER_LOG first.'; exit 1 }
$cmdFile = Join-Path $ue4ss 'Mods\CrowdDiag\cmd.txt'
$ulog = Join-Path $ue4ss 'UE4SS.log'
if (-not $OutDir) { $OutDir = Join-Path (Get-Location) ('ablation-' + (Get-Date -Format 'yyyy-MM-dd-HHmm')) }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$csv = Join-Path $OutDir 'results.csv'
if (-not (Test-Path $csv)) { 'label,start,end,fps,frameMs,samples,gapP50,gapMax,gameMs,renderMs,rhiMs,gamePct,renderPct,rhiPct,procPct,gpuPct,others,count' | Out-File $csv -Encoding utf8 }

$names = @{}
function Get-TName([int]$id) {
    if ($names.ContainsKey($id)) { return $names[$id] }
    $n = '?'; $h = [AB.Native]::OpenThread(0x0800, $false, [uint32]$id)
    if ($h -ne [IntPtr]::Zero) {
        $p = [IntPtr]::Zero
        if ([AB.Native]::GetThreadDescription($h, [ref]$p) -ge 0 -and $p -ne [IntPtr]::Zero) {
            $s = [Runtime.InteropServices.Marshal]::PtrToStringUni($p); [void][AB.Native]::LocalFree($p)
            if ($s) { $n = $s }
        }
        [void][AB.Native]::CloseHandle($h)
    }
    $names[$id] = $n; return $n
}
function Find-Game { Get-Process ArcaneMPLauncher -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle.Trim() -eq 'Hogwarts Legacy' } | Select-Object -First 1 }
function Get-ThreadTimes($p) { $h = @{}; foreach ($t in $p.Threads) { try { $h[$t.Id] = $t.TotalProcessorTime.TotalMilliseconds } catch {} }; $h }
function Get-Samples([datetime]$from, [datetime]$to) {
    Get-Content $slog -Tail 3000 | ForEach-Object {
        if ($_ -match '^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.\d+\].*sample .*? ticks/s ([\d.]+) maxGapMs ([\d.]+)') {
            $t = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
            if ($t -ge $from -and $t -le $to) { [pscustomobject]@{ Fps = [double]$Matches[2]; Gap = [double]$Matches[3] } }
        }
    }
}

foreach ($step in $Steps) {
    $label, $cmds = $step -split '\|', 2
    $g = Find-Game
    if (-not $g) { "GAME NOT RUNNING at step '$label' - stopping"; break }
    $lines = @(); if ($cmds) { $lines += ($cmds -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $lines += 'count'
    $mark = (Get-Item $ulog).Length
    Set-Content -Path $cmdFile -Value $lines -Encoding ascii
    Start-Sleep -Seconds $Settle
    # CrowdDiag output written since the commands were sent (proof the switch took).
    $fs = [IO.File]::Open($ulog, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($mark, 'Begin')
    $diag = (New-Object IO.StreamReader($fs)).ReadToEnd(); $fs.Dispose()
    $diagLines = ($diag -split "`r?`n") | Where-Object { $_ -match '\[CrowdDiag\]' } | ForEach-Object { ($_ -replace '^.*\[CrowdDiag\] ', '').Trim() }
    $countLine = ($diagLines | Where-Object { $_ -like 'count:*' } | Select-Object -Last 1)

    $g = Find-Game; if (-not $g) { "GAME DIED during settle of '$label'. CrowdDiag: $($diagLines -join ' / ')"; break }
    $t0 = Get-ThreadTimes $g; $cpu0 = $g.TotalProcessorTime.TotalMilliseconds; $at0 = Get-Date
    Start-Sleep -Seconds $Measure
    $g = Find-Game; if (-not $g) { "GAME DIED during measure of '$label'. CrowdDiag: $($diagLines -join ' / ')"; break }
    $t1 = Get-ThreadTimes $g; $cpu1 = $g.TotalProcessorTime.TotalMilliseconds; $at1 = Get-Date
    $dt = ($at1 - $at0).TotalMilliseconds
    $gpu = ''; try { $gpu = (& nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | Select-Object -First 1).Trim() } catch {}

    $rows = foreach ($id in $t1.Keys) { if ($t0.ContainsKey($id)) { [pscustomobject]@{ Name = (Get-TName $id); Pct = ($t1[$id] - $t0[$id]) / $dt * 100 } } }
    $rows = $rows | Sort-Object Pct -Descending
    $sm = @(Get-Samples $at0.AddSeconds(1) $at1)
    if ($sm.Count -eq 0) { "no FPS samples for '$label'"; continue }
    $fps = ($sm | Measure-Object Fps -Average).Average; $frameMs = 1000 / $fps
    $gaps = $sm.Gap | Sort-Object; $gapP50 = $gaps[[int][math]::Floor($gaps.Count / 2)]; $gapMax = $gaps[-1]
    function Pct([string]$pattern) { $r = $rows | Where-Object { $_.Name -match $pattern } | Select-Object -First 1; if ($r) { $r.Pct } else { 0 } }
    $gt = Pct '^CrBrowserMain$'; $rt = Pct '^RenderThread'; $rhi = Pct '^RHIThread'
    $others = ($rows | Where-Object { $_.Name -notmatch '^(CrBrowserMain$|RenderThread|RHIThread)' } | Select-Object -First 4 | ForEach-Object { '{0}={1:N0}%' -f ($_.Name -replace '[,;]', '_'), $_.Pct }) -join ' '
    $procPct = ($cpu1 - $cpu0) / $dt * 100
    ('{0},{1:HH:mm:ss},{2:HH:mm:ss},{3:N1},{4:N2},{5},{6},{7},{8:N2},{9:N2},{10:N2},{11:N1},{12:N1},{13:N1},{14:N0},{15},{16},{17}' -f $label, $at0, $at1, $fps, $frameMs, $sm.Count, $gapP50, $gapMax,
        ($gt / 100 * $frameMs), ($rt / 100 * $frameMs), ($rhi / 100 * $frameMs), $gt, $rt, $rhi, $procPct, $gpu, $others, ($countLine -replace ',', ';')) | Out-File $csv -Encoding utf8 -Append
    ('{0,-22} {1:HH:mm:ss}-{2:HH:mm:ss} fps {3,5:N1} frame {4,5:N2} ms | game {5,5:N2} ms ({6,3:N0}%) render {7,5:N2} ms ({8,3:N0}%) rhi {9,5:N2} ms ({10,3:N0}%) | gpu {11}% | gap p50 {12} | {13}' -f $label, $at0, $at1, $fps, $frameMs,
        ($gt / 100 * $frameMs), $gt, ($rt / 100 * $frameMs), $rt, ($rhi / 100 * $frameMs), $rhi, $gpu, $gapP50, $others)
    "    diag: $($diagLines -join ' / ')"
}
"results -> $csv"
