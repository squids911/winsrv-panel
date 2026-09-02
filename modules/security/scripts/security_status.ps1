# security_status.ps1 — quick security summary (extensible example).
# NOTE: keep ASCII-only.

Write-Host "== Security quick summary =="

$ts = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
$rdp = if ($null -ne $ts -and $ts.fDenyTSConnections -eq 0) { 'Enabled' } else { 'Disabled' }
Write-Host ("Remote Desktop (RDP) : {0}" -f $rdp)

Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("Firewall profile    : {0} = {1}" -f $_.Name, $_.Enabled)
}

Write-Host "Members of 'Remote Desktop Users':"
Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host ("  {0}" -f $_.Name) }
