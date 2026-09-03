# get_system_info.ps1 - reports basic server information.
# NOTE: keep ASCII-only.

# Force UTF-8 so the GUI (Python) decodes Russian/system text correctly.
# Also switch the console code page to UTF-8 so native tools (e.g. slmgr via cscript) emit UTF-8.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
try {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class Win32Codepage {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleOutputCP(uint cp);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleCP(uint cp);
}
'@ -ErrorAction Stop
    [Win32Codepage]::SetConsoleOutputCP(65001)
    [Win32Codepage]::SetConsoleCP(65001)
} catch { }
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
