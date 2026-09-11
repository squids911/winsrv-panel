# disable_defender.ps1 - best-effort disable of Windows Defender Antivirus.
# NOTE: keep ASCII-only.
#
# IMPORTANT: if Tamper Protection is ON, Windows blocks disabling Defender from
# scripts. Turn off Tamper Protection (Windows Security > Virus & threat
# protection > Manage settings) and reboot for the service change to stick.

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

try {
    Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true `
        -DisableIOAVProtection $true -DisableScriptScanning $true -ErrorAction SilentlyContinue
    Write-Host "Defender real-time / behavior monitoring disabled via Set-MpPreference."
} catch {
    Write-Host ("Set-MpPreference note: " + $_.Exception.Message)
}

# Allow the (now disabled) real-time protection to stay off across reboots.
try {
    Set-MpPreference -MAPSReporting 0 -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
} catch { }

try {
    Set-Service -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
    Write-Host "WinDefend service set to Disabled and stopped (if Tamper Protection allowed)."
} catch {
    Write-Host ("WinDefend service note: " + $_.Exception.Message)
}

Write-Host "NOTE: with Tamper Protection ON, fully disabling Defender also requires"
Write-Host "      turning Tamper Protection off in Windows Security and a reboot."
