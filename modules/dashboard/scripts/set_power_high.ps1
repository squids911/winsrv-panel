# set_power_high.ps1 - sets the "High performance" power plan.
# NOTE: keep ASCII-only.

# Force UTF-8 so the GUI (Python) decodes Russian/system text correctly.
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
    [void][Win32Codepage]::SetConsoleOutputCP(65001)
    [void][Win32Codepage]::SetConsoleCP(65001)
} catch { }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Error "Administrator rights are required. Run as Administrator."; exit 1 }

$ErrorActionPreference = "Continue"

$powercfg = Join-Path $env:SystemRoot "System32\powercfg.exe"
# GUID of the built-in "High performance" scheme.
$highPerf = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

# Make sure the scheme exists (it can be hidden on some builds), then activate.
& $powercfg /duplicatescheme $highPerf | Out-Null
& $powercfg /setactive $highPerf

Write-Host "Active power plan set to High performance."
& $powercfg /getactivescheme
