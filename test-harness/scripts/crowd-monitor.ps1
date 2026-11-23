param(
    [int]$WaitHours = 6,
    [int]$MaxMinutes = 25,
    [int]$IntervalSec = 5,
    [int]$ShotEverySec = 15,
    [Parameter(Mandatory)][string]$ServerLog,   # <server folder>\logs\hogwarts-mp.log
    [string]$OutDir = "$PSScriptRoot\crowd-run"
)

# Waits for a player to finish loading on the local crowd-test server, then records, until the
# server logs SCHEDULE DONE (or MaxMinutes): game thread loads, process CPU, GPU load/power/VRAM
# every IntervalSec, and a screenshot of the top-right corner (Steam overlay FPS) every ShotEverySec.
# Read-only apart from its own output folder.

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -Namespace W -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][W.Dpi]::SetProcessDPIAware()

New-Item -ItemType Directory -Force $OutDir | Out-Null
$csv = Join-Path $OutDir 'samples.csv'
$shots = Join-Path $OutDir 'shots'
New-Item -ItemType Directory -Force $shots | Out-Null

function Find-Game {
    Get-Process -Name 'ArcaneMPLauncher','HogwartsLegacy' -ErrorAction SilentlyContinue |
        Sort-Object PrivateMemorySize64 -Descending | Select-Object -First 1
}
function LogLines { Get-Content $ServerLog -Tail 400 -ErrorAction SilentlyContinue }

# 1. Wait for loadingFinished in the server log (written after this script started).
$startMark = Get-Date
$deadline = $startMark.AddHours($WaitHours)
"waiting for a player to load in (until $($deadline.ToString('HH:mm')))"
$loaded = $false
while (-not $loaded -and (Get-Date) -lt $deadline) {
    $hit = LogLines | Select-String 'schedule armed' | Select-Object -Last 1
    if ($hit) {
        $ts = [datetime]::ParseExact($hit.Line.Substring(1, 19), 'yyyy-MM-dd HH:mm:ss', $null)
        if ($ts -ge $startMark.AddSeconds(-5)) { $loaded = $true; "player loaded at $ts" }
    }
    if (-not $loaded) { Start-Sleep -Seconds 10 }
}
if (-not $loaded) { "nobody loaded in before the deadline"; exit 1 }

# 2. Record.
"time,phase,proc_cpu_pct,t1_pct,t2_pct,t3_pct,gpu_pct,gpu_w,vram_mib,private_gb,shot" | Out-File $csv -Encoding utf8
$p = Find-Game
if (-not $p) { "game process not found"; exit 1 }
"tracking $($p.ProcessName) pid $($p.Id)"
$prevCpu = $p.TotalProcessorTime; $prevT = Get-Date
$end = (Get-Date).AddMinutes($MaxMinutes)
$lastShot = [datetime]::MinValue
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$cropW = [int]($screen.Width * 0.22); $cropH = [int]($screen.Height * 0.14)
while ((Get-Date) -lt $end) {
    Start-Sleep -Seconds $IntervalSec
    $p = Find-Game
    if (-not $p) { "game gone at $(Get-Date -Format HH:mm:ss)"; break }
    $now = Get-Date
    $cpu = $p.TotalProcessorTime
    $procPct = [math]::Round((($cpu - $prevCpu).TotalMilliseconds / ($now - $prevT).TotalMilliseconds) * 100, 0)
    $prevCpu = $cpu; $prevT = $now
    $top = @(0, 0, 0)
    try {
        $top = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Thread -Filter "Name LIKE '$($p.ProcessName)/%'" |
            Sort-Object PercentProcessorTime -Descending | Select-Object -First 3 | ForEach-Object { $_.PercentProcessorTime })
        while ($top.Count -lt 3) { $top += 0 }
    } catch {}
    $gpu = @('', '', '')
    try { $gpu = ((& nvidia-smi --query-gpu=utilization.gpu,power.draw,memory.used --format=csv,noheader,nounits | Select-Object -First 1) -split ',') | ForEach-Object { $_.Trim() } } catch {}
    $phaseLine = LogLines | Select-String 'PHASE START|schedule armed|SCHEDULE DONE' | Select-Object -Last 1
    $phase = if ($phaseLine) { ($phaseLine.Line -replace '^.*(PHASE START |schedule armed.*|SCHEDULE DONE)', '$1').Trim() -replace ',', ';' } else { '' }
    $shotName = ''
    if (($now - $lastShot).TotalSeconds -ge $ShotEverySec) {
        try {
            $bmp = New-Object System.Drawing.Bitmap $cropW, $cropH
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($screen.Right - $cropW, $screen.Top, 0, 0, $bmp.Size)
            $shotName = "{0:HHmmss}.png" -f $now
            $bmp.Save((Join-Path $shots $shotName), [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose(); $bmp.Dispose()
            $lastShot = $now
        } catch { $shotName = 'capture-failed' }
    }
    ("{0:HH:mm:ss},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}" -f $now, $phase, $procPct, $top[0], $top[1], $top[2],
        $gpu[0], $gpu[1], $gpu[2], [math]::Round($p.PrivateMemorySize64 / 1GB, 2), $shotName) | Out-File $csv -Encoding utf8 -Append
    if ($phase -like 'SCHEDULE DONE*') { "schedule finished"; break }
}
"done; samples in $csv, shots in $shots"
