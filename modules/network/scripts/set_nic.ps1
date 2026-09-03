# set_nic.ps1 - sets a static IPv4 address / gateway / DNS on an adapter.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Adapter,

    [Parameter(Mandatory = $false)]
    [string]$IPAddress,

    [Parameter(Mandatory = $false)]
    [string]$PrefixLength = "24",

    [Parameter(Mandatory = $false)]
    [string]$Gateway = "",

    [Parameter(Mandatory = $false)]
    [string]$Dns = ""
)
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

$ErrorActionPreference = "Stop"

if (-not $Adapter) { throw "Adapter name is required." }
if (-not $IPAddress) { throw "IP address is required." }

$existing = Get-NetIPAddress -InterfaceAlias $Adapter -AddressFamily IPv4 -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host ("Removing existing IPv4 on '{0}'..." -f $Adapter)
    $existing | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host ("Setting IPv4 {0}/{1} on '{2}'..." -f $IPAddress, $PrefixLength, $Adapter)
New-NetIPAddress -InterfaceAlias $Adapter -IPAddress $IPAddress -PrefixLength ([int]$PrefixLength) -ErrorAction Stop

if ($Gateway -and $Gateway.Trim() -ne "") {
    Write-Host ("Setting default gateway {0}..." -f $Gateway)
    New-NetRoute -InterfaceAlias $Adapter -DestinationPrefix "0.0.0.0/0" -NextHop $Gateway -ErrorAction Stop
}

if ($Dns -and $Dns.Trim() -ne "") {
    Write-Host ("Setting DNS servers: {0}" -f $Dns)
    Set-DnsClientServerAddress -InterfaceAlias $Adapter -ServerAddresses @($Dns) -ErrorAction Stop
}

Write-Host ""
Write-Host "Network settings applied."
