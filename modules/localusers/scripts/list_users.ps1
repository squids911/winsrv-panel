# list_users.ps1 - lists local users, groups and members of a target group.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Group = ""
)

$ErrorActionPreference = "Stop"

Write-Host "== Local Users =="
Get-LocalUser -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host "== Local Groups =="
Get-LocalGroup -ErrorAction SilentlyContinue | Format-Table -AutoSize

if ($Group -and $Group.Trim() -ne "") {
    Write-Host ("== Members of group '{0}' ==" -f $Group)
    Get-LocalGroupMember -Group $Group -ErrorAction SilentlyContinue |
        Format-Table -AutoSize
}
