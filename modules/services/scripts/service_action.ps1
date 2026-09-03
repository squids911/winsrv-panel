# service_action.ps1 - start / stop / restart / status for a service.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Start", "Stop", "Restart", "Status")]
    [string]$Action = "Status"
)
# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

if (-not $Name) { throw "Service name is required." }

switch ($Action) {
    "Start" {
        Start-Service -Name $Name
        Write-Host ("Started         : {0}" -f $Name)
    }
    "Stop" {
        Stop-Service -Name $Name
        Write-Host ("Stopped         : {0}" -f $Name)
    }
    "Restart" {
        Restart-Service -Name $Name
        Write-Host ("Restarted       : {0}" -f $Name)
    }
    "Status" {
        Get-Service -Name $Name | Format-Table -AutoSize
    }
}
