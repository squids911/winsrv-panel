# install_roles.ps1
# Installs the selected Windows Server roles / features via ServerManager.
# Usage (from the GUI):
#   powershell -NoProfile -ExecutionPolicy Bypass -File install_roles.ps1 -Features RDS-Licensing RDS-RD-Server
#
# NOTE: Keep this file ASCII-only (English messages) so Windows PowerShell 5.1
#       reads it correctly regardless of locale/codepage.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Features,

    [switch]$IncludeManagementTools
)

$ErrorActionPreference = "Continue"

# --- Admin check -------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $isAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator rights are required. Launch this tool as Administrator (right-click -> Run as administrator)."
    exit 1
}

# --- Install each requested role/feature ------------------------------------
Write-Host "Requested features: $($Features -join ', ')" -ForegroundColor Cyan

foreach ($feature in $Features) {
    $feature = $feature.Trim()
    if ([string]::IsNullOrWhiteSpace($feature)) { continue }

    Write-Host ""
    Write-Host ("Installing feature: {0}" -f $feature) -ForegroundColor Yellow
    try {
        $params = @{ Name = $feature; ErrorAction = "Stop" }
        if ($IncludeManagementTools) { $params.IncludeManagementTools = $true }

        $res = Install-WindowsFeature @params

        $restart = $res.RestartNeeded
        if ($res.Success) {
            Write-Host ("  OK  : {0}  (RestartNeeded: {1})" -f $feature, $restart) -ForegroundColor Green
        } else {
            Write-Host ("  Done: {0}  (message: {1})" -f $feature, $res.Message) -ForegroundColor Yellow
        }
    } catch {
        Write-Host ("  FAIL: {0}  -> {1}" -f $feature, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Feature installation finished." -ForegroundColor Cyan
