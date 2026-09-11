# disable_dep.ps1 - disables Data Execution Prevention system-wide.
# NOTE: keep ASCII-only. A REBOOT is required for the change to take effect.

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

# nx AlwaysOff = DEP disabled for all processes.
& "$env:SystemRoot\System32\bcdedit.exe" /set "{current}" nx AlwaysOff
if ($LASTEXITCODE -eq 0) {
    Write-Host "DEP set to AlwaysOff (disabled). REBOOT required to take effect."
} else {
    Write-Error ("bcdedit failed with exit code " + $LASTEXITCODE)
    exit 1
}
