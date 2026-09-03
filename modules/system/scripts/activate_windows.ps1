# activate_windows.ps1 - applies a product key (optional) and activates Windows.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProductKey = ""
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

$slmgr = "$env:SystemRoot\System32\slmgr.vbs"

if ($ProductKey -and $ProductKey.Trim() -ne "") {
    Write-Host ("Setting product key: {0}" -f $ProductKey)
    cscript.exe //nologo $slmgr /ipk $ProductKey
} else {
    Write-Host "No product key provided - attempting activation only."
}

Write-Host "Activating Windows..."
cscript.exe //nologo $slmgr /ato

Write-Host ""
Write-Host "License status:"
cscript.exe //nologo $slmgr /dli
