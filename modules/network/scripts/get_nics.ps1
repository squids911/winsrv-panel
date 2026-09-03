# get_nics.ps1 - lists network adapters with IPv4 / gateway / DNS.
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
Get-NetIPConfiguration -All | Where-Object { $_.IPv4Address } | ForEach-Object {
    [PSCustomObject]@{
        Adapter = $_.InterfaceAlias
        IP      = ($_.IPv4Address.IPAddress -join ', ')
        Gateway = ($_.IPv4DefaultGateway.NextHop -join ', ')
        DNS     = ($_.DNSServer.ServerAddresses -join ', ')
    }
} | Format-Table -AutoSize
