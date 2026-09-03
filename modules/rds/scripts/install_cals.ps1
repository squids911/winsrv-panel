# install_cals.ps1
# Installs Remote Desktop Services Client Access Licenses (RDS CALs) on the
# local license server using Win32_TSLicenseKeyPack.InstallAgreementLicenseKeyPack.
#
# Defaults match the task:
#   AgreementType   = 1 (Enterprise volume license agreement)
#   AgreementNumber = 6565793
#   ProductVersion  = 8 (Windows Server 2025; 7 = 2022, 6 = 2019, 5 = 2016)
#   ProductType     = 0 (Per Device)
#   LicenseCount    = 1000
#
# NOTE: Keep this file ASCII-only (English messages).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$AgreementType = 1,

    [Parameter(Mandatory = $false)]
    [string]$AgreementNumber = "6565793",

    [Parameter(Mandatory = $false)]
    [int]$ProductVersion = 8,

    [Parameter(Mandatory = $false)]
    [ValidateSet(0, 1)]
    [int]$ProductType = 0,

    [Parameter(Mandatory = $false)]
    [int]$LicenseCount = 1000
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

if (-not (Get-Service -Name TermServLicensing -ErrorAction SilentlyContinue)) {
    Write-Error "The 'Remote Desktop Licensing' role is NOT installed."
    exit 1
}
Start-Service -Name TermServLicensing -ErrorAction SilentlyContinue

Write-Host ("Installing RDS CALs: AgreementType={0}, Number={1}, ProductVersion={2}, ProductType={3}, Count={4}" -f `
    $AgreementType, $AgreementNumber, $ProductVersion, $ProductType, $LicenseCount) -ForegroundColor Yellow

$invokeArgs = @{
    AgreementType    = [uint32]$AgreementType
    sAgreementNumber = [string]$AgreementNumber
    ProductVersion   = [uint32]$ProductVersion
    ProductType      = [uint32]$ProductType
    LicenseCount     = [uint32]$LicenseCount
}

$result = Invoke-CimMethod -ClassName Win32_TSLicenseKeyPack -MethodName InstallAgreementLicenseKeyPack -Arguments $invokeArgs

$returnValue = $result.ReturnValue
Write-Host ("ReturnValue = {0}  (0 = success)" -f $returnValue)

if ($returnValue -ne 0) {
    Write-Error ("Failed to install the license key pack. ReturnValue={0}" -f $returnValue)
    exit 1
}

if ($null -ne $result.KeyPackId) {
    Write-Host ("KeyPackId = {0}" -f $result.KeyPackId) -ForegroundColor Green
}

# --- Summarize installed key packs ------------------------------------------
Write-Host ""
Write-Host "Installed license key packs on this server:" -ForegroundColor Cyan
Get-CimInstance -ClassName Win32_TSLicenseKeyPack |
    Select-Object KeyPackId, ProductVersion, ProductType, TypeAndModel, TotalLicenses, AvailableLicenses |
    Format-Table -AutoSize | Out-String | Write-Host

Write-Host ""
Write-Host "RDS CAL installation finished." -ForegroundColor Cyan
