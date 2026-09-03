# activate_windows.ps1 - applies a product key (optional) and activates Windows.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProductKey = ""
)
# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

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
