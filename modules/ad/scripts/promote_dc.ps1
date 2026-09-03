# promote_dc.ps1 - promotes the server to a Domain Controller (new forest).
# DESTRUCTIVE: requires a reboot afterwards. Requires a static IP/DNS.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,

    [Parameter(Mandatory = $false)]
    [string]$NetbiosName,

    [Parameter(Mandatory = $true)]
    [string]$SafeModePassword
)
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

if (-not $DomainName) { throw "DomainName is required." }
if (-not $SafeModePassword) { throw "SafeModePassword (DSRM) is required." }

Write-Host ("Installing AD DS role...")
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null

Write-Host ("Promoting server to new forest '{0}'..." -f $DomainName)
Import-Module ADDSDeployment

$secpass = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

$params = @{
    DomainName                    = $DomainName
    SafeModeAdministratorPassword = $secpass
    InstallDns                    = $true
    Force                         = $true
    NoRebootOnCompletion          = $true
}
if ($NetbiosName) { $params.DomainNetbiosName = $NetbiosName }

Install-ADDSForest @params

Write-Host ""
Write-Host "Promotion prepared. A REBOOT is required to complete DC promotion."
Write-Host "After reboot, log on with domain credentials and verify with: Get-ADDomain"
