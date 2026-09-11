# disable_dep.ps1 - disables Data Execution Prevention system-wide.
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

# nx AlwaysOff = DEP disabled for all processes. Capture output to inspect it.
$out = & "$env:SystemRoot\System32\bcdedit.exe" /set "{current}" nx AlwaysOff 2>&1
$code = $LASTEXITCODE
$outText = ($out | Out-String)

if ($code -eq 0) {
    Write-Host "DEP set to AlwaysOff (disabled). REBOOT required to take effect."
    exit 0
}

if ($secureBoot -or ($outText -match "Secure Boot")) {
    Write-Host "WARNING: DEP was NOT disabled."
    Write-Host "The 'nx' boot setting is protected by Secure Boot (UEFI)."
    Write-Host "To disable DEP:"
    Write-Host "  1) Reboot into the firmware/UEFI (BIOS) setup."
    Write-Host "  2) Turn OFF Secure Boot."
    Write-Host "  3) Boot into Windows and run this operation again."
    Write-Host "(Leaving DEP enabled is the safer default; disable it only if required.)"
    exit 0
}

Write-Error ("bcdedit failed (exit {0}): {1}" -f $code, $outText.Trim())
exit 1
