# enable_rdp.ps1 - enables Remote Desktop (RDP) and opens the firewall rule.
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

$tsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
Set-ItemProperty -Path $tsPath -Name "fDenyTSConnections" -Value 0

# Network Level Authentication (recommended).
$rdpTcp = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-ItemProperty -Path $rdpTcp -Name "UserAuthentication" -Value 1 -ErrorAction SilentlyContinue

# Open the firewall for Remote Desktop.
try {
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop
    Write-Host "Firewall rules for 'Remote Desktop' enabled."
} catch {
    & "$env:SystemRoot\System32\netsh.exe" advfirewall firewall set rule group="remote desktop" new enable=Yes | Out-Null
    Write-Host "Firewall rules for 'remote desktop' enabled (netsh fallback)."
}

$state = (Get-ItemProperty -Path $tsPath -Name "fDenyTSConnections").fDenyTSConnections
if ($state -eq 0) {
    Write-Host "Remote Desktop (RDP) is now ENABLED."
} else {
    Write-Error "Could not enable Remote Desktop."
    exit 1
}
