# service_action.ps1 - start / stop / restart / status for a service.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Start", "Stop", "Restart", "Status")]
    [string]$Action = "Status"
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

if (-not $Name) { throw "Service name is required." }

switch ($Action) {
    "Start" {
        Start-Service -Name $Name
        Write-Host ("Started         : {0}" -f $Name)
    }
    "Stop" {
        Stop-Service -Name $Name
        Write-Host ("Stopped         : {0}" -f $Name)
    }
    "Restart" {
        Restart-Service -Name $Name
        Write-Host ("Restarted       : {0}" -f $Name)
    }
    "Status" {
        Get-Service -Name $Name | Format-Table -AutoSize
    }
}
