# get_system_info.ps1 — reports basic server information.
# NOTE: keep ASCII-only.

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem

Write-Host ("ComputerName : {0}" -f $cs.Name)
Write-Host ("Domain       : {0}" -f $cs.Domain)
Write-Host ("Manufacturer : {0}" -f $cs.Manufacturer)
Write-Host ("Model        : {0}" -f $cs.Model)
Write-Host ("OS           : {0}" -f $os.Caption)
Write-Host ("Version      : {0} (build {1})" -f $os.Version, $os.BuildNumber)
Write-Host ""

Write-Host "Activation:"
cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli
