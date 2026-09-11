# set_profiles_d.ps1 - moves the default user-profile location to D:\Users.
# Creates the target folder if missing and rewrites ProfilesDirectory in:
#   HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\ProfilesDirectory
# NOTE: keep ASCII-only.
# NOTE: applies to NEW profiles. Existing profiles are not migrated automatically.

[CmdletBinding()]
param(
    [string]$Target = "D:\Users"
)

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

$ErrorActionPreference = "Stop"

if (-not (Test-Path "D:\")) {
    Write-Error "Drive D: not found. Aborting (ProfilesDirectory left unchanged)."
    exit 1
}

if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    Write-Host ("Created folder: {0}" -f $Target)
} else {
    Write-Host ("Folder already exists: {0}" -f $Target)
}

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$old = (Get-ItemProperty -Path $regPath -Name "ProfilesDirectory" -ErrorAction SilentlyContinue).ProfilesDirectory
Set-ItemProperty -Path $regPath -Name "ProfilesDirectory" -Value $Target
$new = (Get-ItemProperty -Path $regPath -Name "ProfilesDirectory").ProfilesDirectory

Write-Host ("ProfilesDirectory: {0}  ->  {1}" -f $old, $new)
Write-Host "NOTE: takes effect for NEW user profiles. A reboot is recommended."
