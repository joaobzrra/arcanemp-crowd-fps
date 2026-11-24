param([int]$Minutes = 10, [int]$IntervalSec = 5, [int]$FpsShotSec = 15, [int]$ViewShotSec = 60)
# Read-only watcher for a live ArcaneMP session (any server). Writes only to its own output folder.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -Namespace LW -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")] public static extern System.IntPtr OpenThread(uint access, bool inherit, uint id);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(System.IntPtr h);
[DllImport("kernel32.dll")] public static extern int GetThreadDescription(System.IntPtr h, out System.IntPtr desc);
[DllImport("kernel32.dll")] public static extern System.IntPtr LocalFree(System.IntPtr p);
'@
[void][LW.Native]::SetProcessDPIAware()

$out = Join-Path (Split-Path $PSScriptRoot) ("live-" + (Get-Date -Format 'yyyy-MM-dd-HHmm'))
$shots = Join-Path $out 'shots'; New-Item -ItemType Directory -Force $shots | Out-Null
$csv = Join-Path $out 'samples.csv'
'time,ue4ss,procCpuPctOneCore,thread1,thread2,thread3,thread4,gpuPct,gpuW,vramMB,gpuC,gpuMHz,procPrivGB,procWsGB,sysRamPct,newSpawns,crowdfix,fpsShot,viewShot' | Out-File $csv -Encoding utf8

$names = @{}
function Get-TName([int]$id) {
    if ($names.ContainsKey($id)) { return $names[$id] }
    $n = '?'; $h = [LW.Native]::OpenThread(0x0800, $false, [uint32]$id)
    if ($h -ne [IntPtr]::Zero) {
        $p = [IntPtr]::Zero
        if ([LW.Native]::GetThreadDescription($h, [ref]$p) -ge 0 -and $p -ne [IntPtr]::Zero) {
            $s = [Runtime.InteropServices.Marshal]::PtrToStringUni($p); [void][LW.Native]::LocalFree($p)
            if ($s) { $n = $s }
        }
        [void][LW.Native]::CloseHandle($h)
    }
    $names[$id] = $n; return $n
}
function Find-Game { Get-Process ArcaneMPLauncher -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle.Trim() -eq 'Hogwarts Legacy' } | Select-Object -First 1 }
function Get-ThreadTimes($p) { $h = @{}; foreach ($t in $p.Threads) { try { $h[$t.Id] = $t.TotalProcessorTime.TotalMilliseconds } catch {} }; $h }

$clog = Get-ChildItem "$env:LOCALAPPDATA\ForgeLauncher\hogwartsmp\*\logs\ArcaneMP.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$clogPos = $clog.Length
function Read-NewLog {
    $fs = [IO.File]::Open($clog.FullName, 'Open', 'Read', 'ReadWrite')
    try { if ($fs.Length -lt $script:clogPos) { $script:clogPos = 0 }
          [void]$fs.Seek($script:clogPos, 'Begin'); $sr = New-Object IO.StreamReader($fs); $txt = $sr.ReadToEnd(); $script:clogPos = $fs.Length; $txt }
    finally { $fs.Dispose() }
}
function Save-Shot([string]$file, [int]$x, [int]$y, [int]$w, [int]$h, [int]$scaleW) {
    $bmp = New-Object Drawing.Bitmap $w, $h; $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size); $g.Dispose()
    if ($scaleW -gt 0 -and $scaleW -lt $w) { $sh = [int]($h * $scaleW / $w); $sm = New-Object Drawing.Bitmap $bmp, $scaleW, $sh; $bmp.Dispose(); $bmp = $sm }
    $bmp.Save($file, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

$p = Find-Game
if (-not $p) { "game not found"; exit 1 }
$scr = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$prevT = Get-ThreadTimes $p; $prevCpu = $p.TotalProcessorTime.TotalMilliseconds; $prevAt = Get-Date
$end = (Get-Date).AddMinutes($Minutes); $lastFps = [datetime]::MinValue; $lastView = [datetime]::MinValue
"watching pid $($p.Id) until $($end.ToString('HH:mm:ss')) -> $out"
while ((Get-Date) -lt $end) {
    Start-Sleep -Seconds $IntervalSec
    $p = Find-Game; if (-not $p) { "game closed at $(Get-Date -Format HH:mm:ss)"; break }
    $now = Get-Date; $dt = ($now - $prevAt).TotalMilliseconds
    $cur = Get-ThreadTimes $p
    $top = $cur.Keys | ForEach-Object { [pscustomobject]@{ Id = $_; Pct = (($cur[$_] - $(if ($prevT.ContainsKey($_)) { $prevT[$_] } else { $cur[$_] })) / $dt * 100) } } |
        Sort-Object Pct -Descending | Select-Object -First 4 | ForEach-Object { "{0}:{1:N0}" -f ((Get-TName $_.Id) -replace '[,:]', '_'), $_.Pct }
    while (@($top).Count -lt 4) { $top = @($top) + '' }
    $cpuMs = $p.TotalProcessorTime.TotalMilliseconds; $proc = [math]::Round(($cpuMs - $prevCpu) / $dt * 100)
    $prevT = $cur; $prevCpu = $cpuMs; $prevAt = $now
    $gpu = @('', '', '', '', '')
    try { $gpu = ((& nvidia-smi --query-gpu=utilization.gpu,power.draw,memory.used,temperature.gpu,clocks.gr --format=csv,noheader,nounits | Select-Object -First 1) -split ',') | ForEach-Object { $_.Trim() } } catch {}
    $os = Get-CimInstance Win32_OperatingSystem; $sysRam = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100)
    $ue = [bool]($p.Modules | Where-Object { $_.ModuleName -ieq 'UE4SS.dll' })
    $new = Read-NewLog; $spawns = ([regex]::Matches($new, 'SpawnCccProxy: spawned at')).Count
    $cf = ''
    if ($ue) { $u = $p.Modules | Where-Object { $_.ModuleName -ieq 'UE4SS.dll' } | Select-Object -First 1
        $ulog = Join-Path (Split-Path $u.FileName) 'UE4SS.log'
        $l = Select-String -Path $ulog -Pattern 'CrowdFix\] enabled' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($l) { $cf = ($l.Line -replace '^.*players ', '' -replace ',', ';') } }
    $fs = ''; $vs = ''
    if (($now - $lastFps).TotalSeconds -ge $FpsShotSec) { $fs = "fps-{0:HHmmss}.png" -f $now; try { Save-Shot (Join-Path $shots $fs) ($scr.Right - 260) $scr.Top 260 90 0 } catch { $fs = 'fail' }; $lastFps = $now }
    if (($now - $lastView).TotalSeconds -ge $ViewShotSec) { $vs = "view-{0:HHmmss}.png" -f $now; try { Save-Shot (Join-Path $shots $vs) $scr.Left $scr.Top $scr.Width $scr.Height 640 } catch { $vs = 'fail' }; $lastView = $now }
    ('{0:HH:mm:ss},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},{17},{18}' -f $now, [int]$ue, $proc, $top[0], $top[1], $top[2], $top[3],
        $gpu[0], $gpu[1], $gpu[2], $gpu[3], $gpu[4], [math]::Round($p.PrivateMemorySize64 / 1GB, 2), [math]::Round($p.WorkingSet64 / 1GB, 2), $sysRam, $spawns, $cf, $fs, $vs) | Out-File $csv -Encoding utf8 -Append
}
"done -> $csv"
