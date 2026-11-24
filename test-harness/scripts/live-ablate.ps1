param(
    # Each step is "label|cmd;cmd;..." (commands for CrowdDiag's cmd.txt; empty = measure only).
    [Parameter(Mandatory)][string[]]$Steps,
    [Parameter(Mandatory)][string]$Ue4ss,   # the UE4SS folder loaded in the game (holds UE4SS.log and Mods\CrowdDiag)
    [int]$Settle = 10,
    [int]$Measure = 40,
    [string]$OutDir = ''
)
# Ablation driver for a session with no local server: per step, send CrowdDiag commands + 'count', wait $Settle s,
# then measure $Measure s. FPS comes from the [CrowdFps] lines CrowdInv prints every 5 s (engine frame counter):
# frames summed / seconds summed over the lines inside the window. CPU ms per frame per thread =
# thread CPU time over the window / frames in the window.
$ErrorActionPreference = 'Continue'
if (-not ('LA.Native' -as [type])) {
Add-Type -Namespace LA -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr OpenThread(uint access, bool inherit, uint id);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(System.IntPtr h);
[DllImport("kernel32.dll")] public static extern int GetThreadDescription(System.IntPtr h, out System.IntPtr desc);
[DllImport("kernel32.dll")] public static extern System.IntPtr LocalFree(System.IntPtr p);
'@
}
$cmdFile = Join-Path $Ue4ss 'Mods\CrowdDiag\cmd.txt'
$ulog = Join-Path $Ue4ss 'UE4SS.log'
if (-not $OutDir) { $OutDir = Join-Path (Get-Location) ('live-ablation-' + (Get-Date -Format 'yyyy-MM-dd-HHmm')) }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$csv = Join-Path $OutDir 'results.csv'
if (-not (Test-Path $csv)) { 'label,start,end,fps,frameMs,fpsLines,gameMs,renderMs,rhiMs,gamePct,renderPct,rhiPct,procPct,gpuPct,others,diag' | Out-File $csv -Encoding utf8 }

$names = @{}
function Get-TName([int]$id) {
    if ($names.ContainsKey($id)) { return $names[$id] }
    $n = '?'; $h = [LA.Native]::OpenThread(0x0800, $false, [uint32]$id)
    if ($h -ne [IntPtr]::Zero) {
        $p = [IntPtr]::Zero
        if ([LA.Native]::GetThreadDescription($h, [ref]$p) -ge 0 -and $p -ne [IntPtr]::Zero) {
            $s = [Runtime.InteropServices.Marshal]::PtrToStringUni($p); [void][LA.Native]::LocalFree($p)
            if ($s) { $n = $s }
        }
        [void][LA.Native]::CloseHandle($h)
    }
    $names[$id] = $n; return $n
}
function Find-Game { Get-Process ArcaneMPLauncher -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle.Trim() -eq 'Hogwarts Legacy' } | Select-Object -First 1 }
function Get-ThreadTimes($p) { $h = @{}; foreach ($t in $p.Threads) { try { $h[$t.Id] = $t.TotalProcessorTime.TotalMilliseconds } catch {} }; $h }
function Read-LogFrom([long]$mark) {
    $fs = [IO.File]::Open($ulog, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($mark, 'Begin')
    $t = (New-Object IO.StreamReader($fs)).ReadToEnd(); $fs.Dispose(); $t -split "`r?`n"
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
    $diagLines = Read-LogFrom $mark | Where-Object { $_ -match '\[CrowdDiag\]' } | ForEach-Object { ($_ -replace '^.*\[CrowdDiag\] ', '').Trim() }

    $g = Find-Game; if (-not $g) { "GAME DIED during settle of '$label'. CrowdDiag: $($diagLines -join ' / ')"; break }
    $mark2 = (Get-Item $ulog).Length
    $t0 = Get-ThreadTimes $g; $cpu0 = $g.TotalProcessorTime.TotalMilliseconds; $at0 = Get-Date
    Start-Sleep -Seconds $Measure
    $g = Find-Game; if (-not $g) { "GAME DIED during measure of '$label'. CrowdDiag: $($diagLines -join ' / ')"; break }
    $t1 = Get-ThreadTimes $g; $cpu1 = $g.TotalProcessorTime.TotalMilliseconds; $at1 = Get-Date
    $dt = ($at1 - $at0).TotalMilliseconds
    $gpu = ''; try { $gpu = (& nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | Select-Object -First 1).Trim() } catch {}

    # Frame counter lines printed inside the window. The first one may cover up to 5 s before the window: skip it.
    $fl = @(Read-LogFrom $mark2 | ForEach-Object { if ($_ -match '\[CrowdFps\] fps [\d.]+ frames (\d+) dt ([\d.]+)') { [pscustomobject]@{ Frames = [int]$Matches[1]; Dt = [double]$Matches[2] } } })
    if ($fl.Count -gt 2) { $fl = $fl[1..($fl.Count - 1)] }
    if ($fl.Count -eq 0) { "no [CrowdFps] lines for '$label'"; continue }
    $fps = ($fl | Measure-Object Frames -Sum).Sum / ($fl | Measure-Object Dt -Sum).Sum; $frameMs = 1000 / $fps

    $rows = foreach ($id in $t1.Keys) { if ($t0.ContainsKey($id)) { [pscustomobject]@{ Name = (Get-TName $id); Pct = ($t1[$id] - $t0[$id]) / $dt * 100 } } }
    $rows = $rows | Sort-Object Pct -Descending
    function Pct([string]$pattern) { $r = $rows | Where-Object { $_.Name -match $pattern } | Select-Object -First 1; if ($r) { $r.Pct } else { 0 } }
    $gt = Pct '^CrBrowserMain$'; $rt = Pct '^RenderThread'; $rhi = Pct '^RHIThread'
    $workers = ($rows | Where-Object { $_.Name -match '^TaskGraphThread' } | Measure-Object Pct -Sum).Sum
    $others = 'workers={0:N0}%' -f $workers
    $procPct = ($cpu1 - $cpu0) / $dt * 100
    ('{0},{1:HH:mm:ss},{2:HH:mm:ss},{3:N1},{4:N2},{5},{6:N2},{7:N2},{8:N2},{9:N1},{10:N1},{11:N1},{12:N0},{13},{14},{15}' -f $label, $at0, $at1, $fps, $frameMs, $fl.Count,
        ($gt / 100 * $frameMs), ($rt / 100 * $frameMs), ($rhi / 100 * $frameMs), $gt, $rt, $rhi, $procPct, $gpu, $others, (($diagLines -join ' / ') -replace ',', ';')) | Out-File $csv -Encoding utf8 -Append
    ('{0,-20} {1:HH:mm:ss}-{2:HH:mm:ss} fps {3,5:N1} | game {4,5:N2} ms ({5,3:N0}%) render {6,5:N2} ms ({7,3:N0}%) rhi {8,5:N2} ms ({9,3:N0}%) | gpu {10}% | {11}' -f $label, $at0, $at1, $fps,
        ($gt / 100 * $frameMs), $gt, ($rt / 100 * $frameMs), $rt, ($rhi / 100 * $frameMs), $rhi, $gpu, $others)
    "    diag: $($diagLines -join ' / ')"
}
"results -> $csv"
