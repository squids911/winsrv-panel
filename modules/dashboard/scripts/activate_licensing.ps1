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
# Force UTF-8 so the GUI (Python) decodes Russian/system text correctly.
# Also switch the console code page to UTF-8 so native tools (e.g. slmgr via cscript) emit UTF-8.
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

$ErrorActionPreference = "Stop"

# --- Admin check -------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $isAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator rights are required."
    exit 1
}

# --- Country/region candidates --------------------------------------------------
# The RDS provider and Win32_TSLicenseServer validate the country against the
# OS-localized list, so on a Russian-MUI server "Belarus" is rejected. Try the
# localized spelling as well (source stays ASCII via UTF-8 byte literals).
$countryCandidates = @(
    $CountryRegion,
    ([System.Text.Encoding]::UTF8.GetString([byte[]](0xD0,0x91,0xD0,0xB5,0xD0,0xBB,0xD0,0xB0,0xD1,0x80,0xD1,0x83,0xD1,0x81,0xD1,0x8C)))
)

# --- Licensing service must exist (auto-install the role if missing) -------
if (-not (Get-Service -Name TermServLicensing -ErrorAction SilentlyContinue)) {
    Write-Host "Remote Desktop Licensing role not found - installing RDS-Licensing..." -ForegroundColor Yellow
    try {
        $res = Install-WindowsFeature -Name @("RDS-Licensing") -ErrorAction Stop
        Write-Host ("  Install-WindowsFeature RDS-Licensing: Success={0}, RestartNeeded={1}" -f $res.Success, $res.RestartNeeded)
    } catch {
        Write-Error ("Failed to install RDS-Licensing role: " + $_.Exception.Message)
        exit 1
    }
    if (-not (Get-Service -Name TermServLicensing -ErrorAction SilentlyContinue)) {
        Write-Error "RDS-Licensing role installed but TermServLicensing service still not found (restart may be required)."
        exit 1
    }
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

    $countrySet = $false
    foreach ($c in $countryCandidates) {
        try {
            Set-Item -Path "RDS:\LicenseServer\Configuration\CountryRegion" -Value $c
            $countrySet = $true
            Write-Host ("  CountryRegion set to: {0}" -f $c) -ForegroundColor Green
            break
        } catch {
            Write-Host ("  CountryRegion candidate rejected: {0}" -f $c) -ForegroundColor Yellow
        }
    }
    if (-not $countrySet) { Write-Host "  WARNING: no CountryRegion candidate accepted - keeping the current value." -ForegroundColor Yellow }

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
        $countrySet = $false
        foreach ($c in $countryCandidates) {
            $ls.CountryRegion = $c
            try {
                $ls.Put() | Out-Null
                $countrySet = $true
                Write-Host ("  CountryRegion set to: {0}" -f $c) -ForegroundColor Green
                break
            } catch {
                Write-Host ("  CountryRegion candidate rejected: {0}" -f $c) -ForegroundColor Yellow
            }
        }
        if (-not $countrySet) {
            # Last resort: commit org info WITHOUT touching CountryRegion.
            $ls2 = Get-WmiObject -Class Win32_TSLicenseServer -ErrorAction Stop
            $ls2.FirstName = $FirstName
            $ls2.LastName  = $LastName
            $ls2.Company   = $Company
            $ls2.Put() | Out-Null
            Write-Host "  WARNING: CountryRegion left unchanged." -ForegroundColor Yellow
        }

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
