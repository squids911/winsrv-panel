# create_collection.ps1 - creates a new RD Session Collection.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CollectionName,

    [Parameter(Mandatory = $true)]
    [string]$SessionHost,

    [Parameter(Mandatory = $true)]
    [string]$ConnectionBroker,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [switch]$GrantAdminPrivilege
)

$ErrorActionPreference = "Stop"

if (-not $CollectionName) { throw "CollectionName is required." }
if (-not $SessionHost) { throw "SessionHost is required." }
if (-not $ConnectionBroker) { throw "ConnectionBroker is required." }

Write-Host ("Creating collection '{0}' on broker '{1}'..." -f $CollectionName, $ConnectionBroker)
if ($GrantAdminPrivilege) {
    New-RDSessionCollection -CollectionName $CollectionName -SessionHost @($SessionHost) `
        -ConnectionBroker $ConnectionBroker -CollectionDescription $Description `
        -GrantAdministrativePrivilege -ErrorAction Stop
} else {
    New-RDSessionCollection -CollectionName $CollectionName -SessionHost @($SessionHost) `
        -ConnectionBroker $ConnectionBroker -CollectionDescription $Description `
        -ErrorAction Stop
}

Write-Host ""
Write-Host "Collection created."
