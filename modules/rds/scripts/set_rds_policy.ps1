# set_rds_policy.ps1
# Configures the LOCAL Group Policy settings for RDS licensing on the RD Session
# Host (equivalent to gpedit.msc):
#
#   Computer Configuration > Administrative Templates > Windows Components >
#   Remote Desktop Services > Remote Desktop Session Host > Licensing
#
#   - "Use the specified Remote Desktop license servers"  -> LicenseServers (REG_SZ)
#   - "Set the Remote Desktop licensing mode"             -> LicensingMode (REG_DWORD)
#
# Registry key: HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services
#   LicenseServers = "localhost"
#   LicensingMode  = 2 (Per Device)  /  4 (Per User)
#
# NOTE: When a LOCAL policy is set, it takes precedence over the RDMS
#       "Licensing Core" configuration, so we write ONLY the policy values here.
# NOTE: Keep this file ASCII-only (English messages).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LicenseServers = "localhost",

    [Parameter(Mandatory = $false)]
    [ValidateSet(2, 4)]
    [int]$LicensingMode = 2
)
# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

# --- Admin check -------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $isAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator rights are required."
    exit 1
}

$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"

New-Item -Path $policyPath -Force | Out-Null

# "Use the specified Remote Desktop license servers" -> LicenseServers (REG_SZ, comma-separated)
New-ItemProperty -Path $policyPath -Name "LicenseServers" -Value $LicenseServers `
    -PropertyType String -Force | Out-Null

# "Set the Remote Desktop licensing mode" -> LicensingMode (REG_DWORD: 2 = Per Device, 4 = Per User)
New-ItemProperty -Path $policyPath -Name "LicensingMode" -Value $LicensingMode `
    -PropertyType DWord -Force | Out-Null

$modeText = switch ($LicensingMode) {
    2 { "Per Device" }
    4 { "Per User" }
    default { "?" }
}

Write-Host "Local RDS licensing policy applied:" -ForegroundColor Green
Write-Host ("  LicenseServers = {0}" -f $LicenseServers)
Write-Host ("  LicensingMode  = {0} ({1})" -f $LicensingMode, $modeText)
Write-Host ("  Registry key   = {0}" -f $policyPath)

Write-Host ""
Write-Host "Hint: run 'gpupdate /force' and restart the server for changes to take effect." -ForegroundColor Yellow
