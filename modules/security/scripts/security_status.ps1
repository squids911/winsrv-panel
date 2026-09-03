# security_status.ps1 - quick security summary (extensible example).
# NOTE: keep ASCII-only.

# Force UTF-8 so the GUI (Python) decodes Russian/system text correctly.
# Also switch the console code page to UTF-8 so native tools (e.g. slmgr via cscript) emit UTF-8.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
try {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class Win32Codepage {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleOutputCP(uint cp);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleCP(uint cp);
}
'@ -ErrorAction Stop
    [Win32Codepage]::SetConsoleOutputCP(65001)
    [Win32Codepage]::SetConsoleCP(65001)
} catch { }
Write-Host "== Security quick summary =="

$ts = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
$rdp = if ($null -ne $ts -and $ts.fDenyTSConnections -eq 0) { 'Enabled' } else { 'Disabled' }
Write-Host ("Remote Desktop (RDP) : {0}" -f $rdp)

Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("Firewall profile    : {0} = {1}" -f $_.Name, $_.Enabled)
}

Write-Host "Members of 'Remote Desktop Users':"
Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host ("  {0}" -f $_.Name) }
