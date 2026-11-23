param([int]$Seconds = 10, [int]$Top = 8)
# Names the busiest threads of the running game (Windows thread descriptions set by UE)
# and reports each one's CPU use over the window, as % of one core.
if (-not ('TP.Native' -as [type])) {
Add-Type -Namespace TP -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr OpenThread(uint access, bool inherit, uint id);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(System.IntPtr h);
[DllImport("kernel32.dll")] public static extern int GetThreadDescription(System.IntPtr h, out System.IntPtr desc);
[DllImport("kernel32.dll")] public static extern System.IntPtr LocalFree(System.IntPtr p);
'@
}
function Get-ThreadName([int]$id) {
    $h = [TP.Native]::OpenThread(0x0800, $false, [uint32]$id)
    if ($h -eq [IntPtr]::Zero) { return '?' }
    $p = [IntPtr]::Zero
    $name = '?'
    if ([TP.Native]::GetThreadDescription($h, [ref]$p) -ge 0 -and $p -ne [IntPtr]::Zero) {
        $name = [Runtime.InteropServices.Marshal]::PtrToStringUni($p); [void][TP.Native]::LocalFree($p)
    }
    [void][TP.Native]::CloseHandle($h)
    if ([string]::IsNullOrEmpty($name)) { '(unnamed)' } else { $name }
}
$g = Get-Process -Name ArcaneMPLauncher -ErrorAction Stop | Sort-Object PrivateMemorySize64 -Descending | Select-Object -First 1
$t0 = @{}; foreach ($t in $g.Threads) { try { $t0[$t.Id] = $t.TotalProcessorTime.TotalMilliseconds } catch {} }
Start-Sleep -Seconds $Seconds
$g.Refresh()
$rows = foreach ($t in $g.Threads) {
    try { $ms = $t.TotalProcessorTime.TotalMilliseconds } catch { continue }
    if ($t0.ContainsKey($t.Id)) { [pscustomobject]@{ Id = $t.Id; Pct = [math]::Round(($ms - $t0[$t.Id]) / ($Seconds * 10), 1) } }
}
$rows | Sort-Object Pct -Descending | Select-Object -First $Top | ForEach-Object { "{0,6}%  tid {1,-6} {2}" -f $_.Pct, $_.Id, (Get-ThreadName $_.Id) }
"total threads $($g.Threads.Count); window $Seconds s; pid $($g.Id)"
