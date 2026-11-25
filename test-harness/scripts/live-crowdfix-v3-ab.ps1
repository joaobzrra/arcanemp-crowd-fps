param(
    [Parameter(Mandatory)][string]$Ue4ss,      # UE4SS folder loaded in the game (the kit with CrowdDiag + CrowdInv)
    [Parameter(Mandatory)][string]$Settings,   # settings.txt the CrowdFix v3 build under test reads
    [Parameter(Mandatory)][string]$OutDir,
    [string]$FarInterval = '0.2',              # seconds between animation updates beyond 50 m while a preset is on (0.1 = 10 per second)
    [int]$Settle = 15,
    [int]$Measure = 40
)
# A-B of CrowdFix v3's presets: off / Performance (sleep beyond 200 m) / off / Ultra Performance (sleep beyond
# 100 m) / off. Per step: write the preset to $Settings, then settle + measure with live-ablate.ps1, then print the
# build's own status line and how many player bodies the ArcaneMP client built during the step (a rise while a
# preset is on would mean sleeping makes the client rebuild players).
$ulog = Join-Path $Ue4ss 'UE4SS.log'
$driver = Join-Path $PSScriptRoot 'live-ablate.ps1'
$clog = Get-ChildItem "$env:LOCALAPPDATA\ForgeLauncher\hogwartsmp\*\logs\ArcaneMP.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
function Set-Fix([int]$enabled, [int]$uro, [int]$sleep) {
    Set-Content -Path $Settings -Encoding ascii -Value "enabled=$enabled", "distance=$uro", 'interpolate=1', 'animrate=2', 'fardistance=5000', "farinterval=$FarInterval", "sleepdistance=$sleep"
}
function Read-From([string]$file, [long]$mark) {
    $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite'); try { if ($fs.Length -lt $mark) { $mark = 0 }; [void]$fs.Seek($mark, 'Begin'); (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
# ONE CrowdFix instance only: it is loaded here if this game does not have it yet (never next to another build).
$cmd = Join-Path $Ue4ss 'Mods\CrowdDiag\cmd.txt'
Set-Fix 0 2500 0
if (-not (Select-String -Path $ulog -Pattern '\[CrowdFix\] loaded' -Quiet)) {
    Set-Content -Path $cmd -Value 'lua crowdfix_main.lua' -Encoding ascii
    Start-Sleep -Seconds 6
}
$loaded = @(Select-String -Path $ulog -Pattern '\[CrowdFix\] loaded')
if ($loaded.Count -ne 1) { throw "expected exactly one CrowdFix instance in this game, found $($loaded.Count) 'loaded' lines" }
'CrowdFix in the game: ' + ($loaded[0].Line -replace '^.*\[CrowdFix\] ', '')
$plan = @(
    @{ label = 'off 1';                         enabled = 0; uro = 2500; sleep = 0 },
    @{ label = 'Performance (sleep 200 m)';      enabled = 1; uro = 1500; sleep = 20000 },
    @{ label = 'off 2';                          enabled = 0; uro = 2500; sleep = 0 },
    @{ label = 'Ultra Performance (sleep 100 m)'; enabled = 1; uro = 1000; sleep = 10000 },
    @{ label = 'off 3';                          enabled = 0; uro = 2500; sleep = 0 }
)
foreach ($p in $plan) {
    Set-Fix $p.enabled $p.uro $p.sleep
    $cmark = if ($clog) { (Get-Item $clog.FullName).Length } else { 0 }
    $umark = (Get-Item $ulog).Length
    & $driver -Ue4ss $Ue4ss -OutDir $OutDir -Settle $Settle -Measure $Measure -Steps ($p.label + '|') | Where-Object { $_ -notmatch '^results ->' }
    $new = (Read-From $ulog $umark) -split "`r?`n"
    $status = $new | Where-Object { $_ -match '\[CrowdFix\] enabled=.*sleepdistance=' }
    if ($status) {
        '    fix:  ' + (($status | Select-Object -Last 1) -replace '^.*\[CrowdFix\] ', '')
        $slow = ($status | ForEach-Object { if ($_ -match 'slowestStep=([\d.]+)ms') { [double]$Matches[1] } } | Measure-Object -Maximum).Maximum
        "    slowest add-on step during this step: $slow ms"
    }
    $err = @($new | Where-Object { $_ -match '\[CrowdFix\] error' })
    if ($err.Count) { "    ADD-ON ERRORS: $($err.Count); first: " + ($err[0] -replace '^.*\[CrowdFix\] ', '') }
    if ($clog) { "    player bodies built by the client during this step: " + ([regex]::Matches((Read-From $clog.FullName $cmark), 'SpawnCccProxy: spawned at')).Count }
}
Set-Fix 0 2500 0
'--- check lines:'
Select-String -Path $ulog -Pattern '\[CrowdFix\] (sleep check|far check|loaded \(v3\))' | Select-Object -Last 4 | ForEach-Object { ($_.Line -replace '^.*\[CrowdFix\] ', '') }
"{0:HH:mm:ss} left OFF" -f (Get-Date)
