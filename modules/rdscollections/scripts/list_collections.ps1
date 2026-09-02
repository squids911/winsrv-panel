# list_collections.ps1 - lists RD Session Collections on a Connection Broker.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConnectionBroker
)

$ErrorActionPreference = "Stop"

Write-Host ("RD Session Collections on Connection Broker '{0}':" -f $ConnectionBroker)
Get-RDSessionCollection -ConnectionBroker $ConnectionBroker -ErrorAction SilentlyContinue |
    Select-Object CollectionName, CollectionDescription, CollectionType,
                  ResourceType, Computername |
    Format-Table -AutoSize
