# list_collections.ps1 - lists RD Session Collections on a Connection Broker.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConnectionBroker
)
# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

Write-Host ("RD Session Collections on Connection Broker '{0}':" -f $ConnectionBroker)
Get-RDSessionCollection -ConnectionBroker $ConnectionBroker -ErrorAction SilentlyContinue |
    Select-Object CollectionName, CollectionDescription, CollectionType,
                  ResourceType, Computername |
    Format-Table -AutoSize
