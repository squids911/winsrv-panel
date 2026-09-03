# create_collection.ps1 - creates a new RD Session Collection.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CollectionName,

    [Parameter(Mandatory = $true)]
    [string]$SessionHost,

    [Parameter(Mandatory = $true)]
    [string]$ConnectionBroker,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [switch]$GrantAdminPrivilege
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

if (-not $CollectionName) { throw "CollectionName is required." }
if (-not $SessionHost) { throw "SessionHost is required." }
if (-not $ConnectionBroker) { throw "ConnectionBroker is required." }

Write-Host ("Creating collection '{0}' on broker '{1}'..." -f $CollectionName, $ConnectionBroker)
if ($GrantAdminPrivilege) {
    New-RDSessionCollection -CollectionName $CollectionName -SessionHost @($SessionHost) `
        -ConnectionBroker $ConnectionBroker -CollectionDescription $Description `
        -GrantAdministrativePrivilege -ErrorAction Stop
} else {
    New-RDSessionCollection -CollectionName $CollectionName -SessionHost @($SessionHost) `
        -ConnectionBroker $ConnectionBroker -CollectionDescription $Description `
        -ErrorAction Stop
}

Write-Host ""
Write-Host "Collection created."
