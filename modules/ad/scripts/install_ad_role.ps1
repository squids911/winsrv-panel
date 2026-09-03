# install_ad_role.ps1 - installs the AD DS role (and management tools).
# NOTE: keep ASCII-only.

# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $isAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator rights are required."
    exit 1
}

Write-Host "Installing AD Domain Services role..."
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Write-Host ""
Write-Host "AD DS role installed. You can now promote this server to a Domain Controller."
Write-Host "It is recommended to assign a static IP and DNS first."
