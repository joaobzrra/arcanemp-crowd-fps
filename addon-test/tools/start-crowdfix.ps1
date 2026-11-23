# Waits for the ArcaneMP game (Forge or ArcaneMP launcher), then loads UE4SS + CrowdFix into it.
# Nothing is installed: closing the game unloads everything.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dll = Join-Path $root 'ue4ss\UE4SS.dll'
if (-not (Test-Path -LiteralPath $dll)) { Write-Host "UE4SS.dll not found at $dll" -ForegroundColor Red; exit 1 }

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
if ($game.Modules | Where-Object { $_.ModuleName -ieq 'UE4SS.dll' }) { Write-Host 'CrowdFix is already loaded in this game.' -ForegroundColor Green; exit 0 }

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
