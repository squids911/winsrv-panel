# activate_licensing.ps1
# Activates the Remote Desktop (RDS) Licensing server on the local machine
# using the "Automatic" connection method (reason = 5, first-time activation).
#
# Primary path uses the documented RDS PowerShell provider (RDS:\LicenseServer).
# If that fails, it falls back to WMI/CIM (Win32_TSLicenseServer).
#
# NOTE: Keep this file ASCII-only (English messages).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$FirstName = "1",

    [Parameter(Mandatory = $false)]
    [string]$LastName = "1",

    [Parameter(Mandatory = $false)]
    [string]$Company = "1",

    [Parameter(Mandatory = $false)]
    [string]$CountryRegion = "Belarus",

    [Parameter(Mandatory = $false)]
    [ValidateSet("AUTO", "WEB", "PHONE")]
    [string]$ConnectionMethod = "AUTO",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 5)]
    [int]$Reason = 5
)

$ErrorActionPreference = "Stop"

# --- Admin check -------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $isAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator rights are required."
    exit 1
}

# --- Licensing service must exist ------------------------------------------
if (-not (Get-Service -Name TermServLicensing -ErrorAction SilentlyContinue)) {
    Write-Error "The 'Remote Desktop Services > Remote Desktop Licensing' role is NOT installed (TermServLicensing service not found)."
    Write-Error "Install the role first (Roles & Components tab)."
    exit 1
}
Start-Service -Name TermServLicensing -ErrorAction SilentlyContinue

# --- RDS provider path (documented method) ----------------------------------
$activated = $false
try {
    Import-Module RemoteDesktopServices -ErrorAction Stop

    Write-Host "Setting organization info (FirstName/LastName/Company/CountryRegion)..." -ForegroundColor Yellow
    Set-Item -Path "RDS:\LicenseServer\Configuration\FirstName" -Value $FirstName
    Set-Item -Path "RDS:\LicenseServer\Configuration\LastName" -Value $LastName
    Set-Item -Path "RDS:\LicenseServer\Configuration\Company" -Value $Company
    Set-Item -Path "RDS:\LicenseServer\Configuration\CountryRegion" -Value $CountryRegion

    Write-Host ("Activating license server (ConnectionMethod={0}, Reason={1})..." -f $ConnectionMethod, $Reason) -ForegroundColor Yellow
    Set-Item -Path "RDS:\LicenseServer\ActivationStatus" -Value 1 -ConnectionMethod $ConnectionMethod -Reason $Reason

    $status = (Get-Item -Path "RDS:\LicenseServer\ActivationStatus").CurrentValue
    Write-Host ("ActivationStatus = {0}" -f $status) -ForegroundColor Green
    $activated = $true
} catch {
    Write-Host ("RDS provider failed ({0}). Falling back to WMI/CIM..." -f $_.Exception.Message) -ForegroundColor Yellow
}

# --- WMI fallback ------------------------------------------------------------
# Reliable in Windows PowerShell 5.1 (powershell.exe). Note: this path uses
# ActivateServerAutomatic (implicit first-time activation).
if (-not $activated) {
    try {
        $ls = Get-WmiObject -Class Win32_TSLicenseServer -ErrorAction Stop
        $ls.FirstName     = $FirstName
        $ls.LastName      = $LastName
        $ls.Company       = $Company
        $ls.CountryRegion = $CountryRegion
        $ls.Put() | Out-Null

        $null = Invoke-WmiMethod -Class Win32_TSLicenseServer -MethodName ActivateServerAutomatic

        $status = (Get-WmiObject -Class Win32_TSLicenseServer).ActivationStatus
        Write-Host ("ActivationStatus = {0}" -f $status) -ForegroundColor Green
    } catch {
        Write-Error ("Activation failed: {0}" -f $_.Exception.Message)
        exit 1
    }
}

Write-Host ""
Write-Host "License server activation finished." -ForegroundColor Cyan
