# list_users.ps1 - lists local users, groups and members of a target group.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Group = ""
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

Write-Host "== Local Users =="
Get-LocalUser -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "== Local Groups =="
Get-LocalGroup -ErrorAction SilentlyContinue | Format-Table -AutoSize

if ($Group -and $Group.Trim() -ne "") {
    Write-Host ("== Members of group '{0}' ==" -f $Group)
    Get-LocalGroupMember -Group $Group -ErrorAction SilentlyContinue |
        Format-Table -AutoSize
}
