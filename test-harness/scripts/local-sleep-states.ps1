param(
    [Parameter(Mandatory)][string]$Ue4ss,                              # UE4SS folder loaded in the TEST client
    [int]$Wait = 22,                                                   # seconds per state: one component map + one sweep
    [int[]]$CustomSleepCm = @()                                        # e.g. 5000,2000: test these sleep distances instead of the two presets
)
# State check of CrowdFix v3's sleep step on the private server (CrowdFix loaded as its own mod).
# Walks through: off, Performance (200 m), Ultra Performance (100 m), back to Performance (wake), off.
# After each state it reads the avatars back from outside the mod (Scripts\sleep_readback_ro.lua, tag [CrowdSleep]):
# how many are hidden / not ticking, and how many are on the wrong side of the limit.
$settings = Join-Path $Ue4ss 'Mods\CrowdFix\settings.txt'
$cmd = Join-Path $Ue4ss 'Mods\CrowdDiag\cmd.txt'
$scripts = Join-Path $Ue4ss 'Mods\CrowdDiag\Scripts'
$ulog = Join-Path $Ue4ss 'UE4SS.log'
function Read-From([long]$mark) {
    $fs = [IO.File]::Open($ulog, 'Open', 'Read', 'ReadWrite'); try { [void]$fs.Seek($mark, 'Begin'); (New-Object IO.StreamReader($fs)).ReadToEnd() -split "`r?`n" } finally { $fs.Dispose() }
}
$states = @(
    @{ label = 'off';                        enabled = 0; uro = 2500; sleep = 0;     limit = 0 },
    @{ label = 'Performance (200 m)';        enabled = 1; uro = 1500; sleep = 20000; limit = 200 },
    @{ label = 'Ultra Performance (100 m)';  enabled = 1; uro = 1000; sleep = 10000; limit = 100 },
    @{ label = 'back to Performance (200 m)'; enabled = 1; uro = 1500; sleep = 20000; limit = 200 },
    @{ label = 'off again';                  enabled = 0; uro = 2500; sleep = 0;     limit = 0 }
)
if ($CustomSleepCm.Count) {
    $states = @(@{ label = 'off'; enabled = 0; uro = 2500; sleep = 0; limit = 0 })
    foreach ($cm in $CustomSleepCm) { $states += @{ label = "sleep beyond $($cm / 100) m"; enabled = 1; uro = 2500; sleep = $cm; limit = [int]($cm / 100) } }
    $states += @{ label = 'off again'; enabled = 0; uro = 2500; sleep = 0; limit = 0 }
}
foreach ($s in $states) {
    $mark = (Get-Item $ulog).Length
    Set-Content -Path $settings -Encoding ascii -Value "enabled=$($s.enabled)", "distance=$($s.uro)", 'interpolate=1', 'animrate=2', 'shadows=0', 'cloth=0', 'fardistance=5000', 'farinterval=0.2', "sleepdistance=$($s.sleep)"
    Start-Sleep -Seconds $Wait
    $limitLua = if ($s.limit -gt 0) { "CrowdSleepLimitM = $($s.limit)" } else { 'CrowdSleepLimitM = nil' }
    Set-Content -Path (Join-Path $scripts 'sleep_limit_tmp.lua') -Encoding ascii -Value $limitLua
    Set-Content -Path $cmd -Encoding ascii -Value 'lua sleep_limit_tmp.lua', 'lua sleep_readback_ro.lua', 'lua interval_readback_ro.lua'
    Start-Sleep -Seconds 4
    $new = Read-From $mark
    "== $($s.label)   [$(Get-Date -Format HH:mm:ss)]"
    $st = @($new | Where-Object { $_ -match '\[CrowdFix\] enabled=' })
    if ($st.Count) {
        '   fix:      ' + ($st[-1] -replace '^.*\[CrowdFix\] ', '')
        '   slowest add-on step in this state: ' + (($st | ForEach-Object { if ($_ -match 'slowestStep=([\d.]+)ms') { [double]$Matches[1] } } | Measure-Object -Maximum).Maximum) + ' ms'
    }
    $new | Where-Object { $_ -match '\[CrowdSleep\]|\[CrowdIvl\]|\[CrowdFix\] (sleep check|far check|error)' } | ForEach-Object { '   ' + ($_ -replace '^\[[^\]]*\] \[Lua\] ', '') }
    $fps = @($new | ForEach-Object { if ($_ -match '\[CrowdFps\] fps ([\d.]+)') { [double]$Matches[1] } })
    if ($fps.Count) { '   fps lines: ' + ($fps -join ' ') }
}
$g = Get-Process ArcaneMPLauncher -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle.Trim() -eq 'Hogwarts Legacy' }
"game alive: $([bool]$g); add-on error lines in the whole log: $(@(Select-String -Path $ulog -Pattern '\[CrowdFix\] error').Count)"
