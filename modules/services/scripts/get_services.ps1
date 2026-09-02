# get_services.ps1 — lists services.
# NOTE: keep ASCII-only.
Get-Service | Sort-Object Name | Format-Table -AutoSize
