# create_user.ps1 - creates a local user and optionally adds it to a group.
# NOTE: keep ASCII-only. Password is NOT persisted anywhere by this script.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$FullName = "",

    [Parameter(Mandatory = $true)]
    [string]$Password,

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

if (-not $Name) { throw "Name is required." }
if (-not $Password) { throw "Password is required." }

# Create the user
$secpass = ConvertTo-SecureString $Password -AsPlainText -Force
$params = @{ Name = $Name; Password = $secpass; PasswordNeverExpires = $true; AccountNeverExpires = $true }
if ($FullName) { $params.FullName = $FullName }

New-LocalUser @params -ErrorAction Stop
Write-Host ("Local user created: {0}" -f $Name)

# Add to group if requested
if ($Group -and $Group.Trim() -ne "") {
    try {
        Add-LocalGroupMember -Group $Group -Member $Name -ErrorAction Stop
        Write-Host ("Added '{0}' to group '{1}'." -f $Name, $Group)
    } catch {
        Write-Host ("Could not add '{0}' to group '{1}': {2}" -f $Name, $Group, $_.Exception.Message) -ForegroundColor Yellow
    }
}
