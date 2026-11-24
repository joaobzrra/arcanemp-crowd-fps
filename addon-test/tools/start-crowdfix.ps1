# Asks for a preset, then waits for the ArcaneMP game (Forge or ArcaneMP launcher) and loads UE4SS + CrowdFix.
# Nothing is installed: closing the game unloads everything. If CrowdFix is already loaded, only the preset
# changes (CrowdFix re-reads settings.txt every few seconds).
param([ValidateSet('', '1', '2', '3', '4')][string]$Preset = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dll = Join-Path $root 'ue4ss\UE4SS.dll'
$settings = Join-Path $root 'ue4ss\Mods\CrowdFix\settings.txt'
if (-not (Test-Path -LiteralPath $dll)) { Write-Host "UE4SS.dll not found at $dll" -ForegroundColor Red; exit 1 }

# Preset = distance (cm) beyond which other players animate with fewer updates.
$presets = [ordered]@{
    '1' = @{ Name = 'Ultra Performance'; Cm = 1000; Note = 'weak PCs; players beyond 10 m move less smoothly' }
    '2' = @{ Name = 'Performance';       Cm = 1500; Note = '' }
    '3' = @{ Name = 'Balanced';          Cm = 2000; Note = '' }
    '4' = @{ Name = 'Quality';           Cm = 2500; Note = 'tested default; no visible difference' }
}
$text = if (Test-Path -LiteralPath $settings) { [IO.File]::ReadAllText($settings) } else { "enabled=1`r`ndistance=2500`r`ninterpolate=1`r`nanimrate=2`r`n" }
$current = if ($text -match '(?m)^\s*distance\s*=\s*(\d+)') { [int]$matches[1] } else { 2500 }
$default = ($presets.Keys | Where-Object { $presets[$_].Cm -eq $current } | Select-Object -First 1); if (-not $default) { $default = '4' }
if (-not $Preset) {
    Write-Host 'CrowdFix preset / Modo:'
    foreach ($k in $presets.Keys) {
        $p = $presets[$k]; $mark = if ($k -eq $default) { ' (current)' } else { '' }
        Write-Host ("  {0}. {1,-18} {2,2} m{3}  {4}" -f $k, $p.Name, ($p.Cm / 100), $mark, $p.Note)
    }
    $answer = Read-Host "Choose 1-4 (Enter = $default)"
    $Preset = if ($answer -and $presets.Contains($answer.Trim())) { $answer.Trim() } else { $default }
}
$chosen = $presets[$Preset]
$text = if ($text -match '(?m)^\s*distance\s*=') { $text -replace '(?m)^(\s*distance\s*=\s*)\d+', "`${1}$($chosen.Cm)" } else { $text.TrimEnd() + "`r`ndistance=$($chosen.Cm)`r`n" }
[IO.File]::WriteAllText($settings, $text, (New-Object Text.UTF8Encoding($false)))
Write-Host ("Preset: {0} ({1} m)" -f $chosen.Name, ($chosen.Cm / 100)) -ForegroundColor Cyan

Add-Type -Namespace CF -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern System.IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError=true)] public static extern System.IntPtr VirtualAllocEx(System.IntPtr h, System.IntPtr addr, System.UIntPtr size, uint type, uint protect);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool WriteProcessMemory(System.IntPtr h, System.IntPtr addr, byte[] buf, System.UIntPtr size, out System.UIntPtr written);
[DllImport("kernel32.dll", CharSet=CharSet.Ansi)] public static extern System.IntPtr GetProcAddress(System.IntPtr mod, string name);
[DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr GetModuleHandle(string name);
[DllImport("kernel32.dll", SetLastError=true)] public static extern System.IntPtr CreateRemoteThread(System.IntPtr h, System.IntPtr attr, System.UIntPtr stack, System.IntPtr start, System.IntPtr param, uint flags, System.IntPtr id);
[DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(System.IntPtr h, uint ms);
[DllImport("kernel32.dll")] public static extern bool GetExitCodeThread(System.IntPtr h, out uint code);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(System.IntPtr h);
'@

function Get-Game {
    Get-Process -Name ArcaneMPLauncher -ErrorAction SilentlyContinue | Where-Object {
        # The window title carries trailing spaces ('Hogwarts Legacy  '), so compare it trimmed.
        $_.MainWindowTitle.Trim() -eq 'Hogwarts Legacy' -and $_.MainModule.ModuleName -ieq 'HogwartsLegacy.exe'
    } | Select-Object -First 1
}

Write-Host 'Waiting for Hogwarts Legacy (ArcaneMP) to open... (start the game now if it is not running)'
$deadline = (Get-Date).AddMinutes(15)
$game = $null
while (-not $game -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2; $game = Get-Game }
if (-not $game) { Write-Host 'Game not found after 15 minutes. Nothing was changed.' -ForegroundColor Yellow; exit 1 }
if ($game.Modules | Where-Object { $_.ModuleName -ieq 'UE4SS.dll' }) { Write-Host 'CrowdFix is already loaded in this game: the new preset applies within a few seconds.' -ForegroundColor Green; exit 0 }

Write-Host 'Game found. Waiting 30 s for the main menu to finish loading...'
Start-Sleep -Seconds 30
$game = Get-Game
if (-not $game) { Write-Host 'The game closed. Nothing was changed.' -ForegroundColor Yellow; exit 1 }

$h = [CF.Native]::OpenProcess(0x043A, $false, $game.Id)
if ($h -eq [IntPtr]::Zero) { Write-Host 'Could not open the game process (try running as administrator).' -ForegroundColor Red; exit 1 }
$bytes = [Text.Encoding]::Unicode.GetBytes((Resolve-Path -LiteralPath $dll).Path + [char]0)
$mem = [CF.Native]::VirtualAllocEx($h, [IntPtr]::Zero, [UIntPtr][uint64]$bytes.Length, 0x3000, 0x04)
$w = [UIntPtr]::Zero
[void][CF.Native]::WriteProcessMemory($h, $mem, $bytes, [UIntPtr][uint64]$bytes.Length, [ref]$w)
$ll = [CF.Native]::GetProcAddress([CF.Native]::GetModuleHandle('kernel32.dll'), 'LoadLibraryW')
$t = [CF.Native]::CreateRemoteThread($h, [IntPtr]::Zero, [UIntPtr]::Zero, $ll, $mem, 0, [IntPtr]::Zero)
if ($t -eq [IntPtr]::Zero) { [void][CF.Native]::CloseHandle($h); Write-Host 'Could not load CrowdFix.' -ForegroundColor Red; exit 1 }
[void][CF.Native]::WaitForSingleObject($t, 60000)
$code = 0; [void][CF.Native]::GetExitCodeThread($t, [ref]$code)
[void][CF.Native]::CloseHandle($t); [void][CF.Native]::CloseHandle($h)
if ($code -eq 0) { Write-Host 'Loading failed.' -ForegroundColor Red; exit 1 }
Write-Host 'CrowdFix loaded. Log: ' (Join-Path $root 'ue4ss\UE4SS.log') -ForegroundColor Green
Write-Host 'Settings: ' (Join-Path $root 'ue4ss\Mods\CrowdFix\settings.txt')
