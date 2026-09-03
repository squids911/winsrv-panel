# extend_volume.ps1 - extends a partition/volume by drive letter to its max size.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DriveLetter
)
# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

if (-not $DriveLetter) { throw "DriveLetter is required." }

$dl = $DriveLetter.Trim().TrimEnd(':')

Write-Host ("Extending volume '{0}:' to maximum supported size..." -f $dl)
$supported = Get-PartitionSupportedSize -DriveLetter $dl -ErrorAction Stop
Resize-Partition -DriveLetter $dl -Size $supported.SizeMax -ErrorAction Stop

Write-Host ""
Write-Host "Volume extended."
Get-Volume -DriveLetter $dl -ErrorAction SilentlyContinue |
    Select-Object DriveLetter, FileSystem, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}} |
    Format-Table -AutoSize
