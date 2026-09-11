# disable_dep.ps1 - sets DEP to "Turn on DEP for essential Windows programs and
# services only" (bcdedit nx OptOut). This is the Windows setting:
#   System Properties > Advanced > Performance > Data Execution Prevention >
#   "Turn on DEP for essential Windows programs and services only".
#
# NOTE: keep ASCII-only. A REBOOT is required for the change to take effect.
#
# On UEFI machines with Secure Boot ON, the 'nx' BCD element is protected and
# cannot be modified from Windows ("The value is protected by Secure Boot
# policy"). That is a firmware restriction, not a script bug - we detect it and
# print a clear instruction instead of a scary error.

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

# Detect Secure Boot state (UEFI). Confirm-SecureBootUEFI throws on legacy BIOS.
$secureBoot = $false
try { $secureBoot = [bool](Confirm-SecureBootUEFI) } catch { $secureBoot = $false }

# nx OptOut = DEP on for essential Windows programs and services only.
$out = & "$env:SystemRoot\System32\bcdedit.exe" /set "{current}" nx OptOut 2>&1
$code = $LASTEXITCODE
$outText = ($out | Out-String)

if ($code -eq 0) {
    Write-Host "DEP set to OptOut (essential Windows programs and services only)."
    Write-Host "REBOOT required to take effect."
    exit 0
}

if ($secureBoot -or ($outText -match "Secure Boot")) {
    Write-Host "WARNING: DEP setting was NOT changed."
    Write-Host "The 'nx' boot setting is protected by Secure Boot (UEFI)."
    Write-Host "To change DEP:"
    Write-Host "  1) Reboot into the firmware/UEFI (BIOS) setup."
    Write-Host "  2) Turn OFF Secure Boot."
    Write-Host "  3) Boot into Windows and run this operation again."
    exit 0
}

Write-Error ("bcdedit failed (exit {0}): {1}" -f $code, $outText.Trim())
exit 1
