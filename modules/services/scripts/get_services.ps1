# get_services.ps1 - lists services.
# NOTE: keep ASCII-only.
# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
Get-Service | Sort-Object Name | Format-Table -AutoSize
