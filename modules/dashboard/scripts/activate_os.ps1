# activate_os.ps1 - detects the Windows Server version and applies the matching
# product key, then activates.
#   Windows Server 2022 -> WX4NM-KYWYW-QJJR4-XV3QB-6VM33
#   Windows Server 2025 -> D764K-2NDRG-47T6Q-P8T8W-YP6DF
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [string]$Key2022 = "WX4NM-KYWYW-QJJR4-XV3QB-6VM33",
    [string]$Key2025 = "D764K-2NDRG-47T6Q-P8T8W-YP6DF"
)

# Force UTF-8 so the GUI (Python) decodes Russian/system text correctly.
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
    [void][Win32Codepage]::SetConsoleOutputCP(65001)
    [void][Win32Codepage]::SetConsoleCP(65001)
} catch { }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Error "Administrator rights are required. Run as Administrator."; exit 1 }

$ErrorActionPreference = "Continue"

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$caption = $os.Caption
try { $build = [int]$os.BuildNumber } catch { $build = 0 }
Write-Host ("Operating system: {0} (build {1})" -f $caption, $build)

# Server 2025 = build 26100, Server 2022 = build 20348.
$key = $null
$label = $null
if ($caption -match "2025" -or $build -ge 26100) {
    $key = $Key2025; $label = "Windows Server 2025"
} elseif ($caption -match "2022" -or ($build -ge 20348 -and $build -lt 26100)) {
    $key = $Key2022; $label = "Windows Server 2022"
}

if (-not $key) {
    Write-Error "Could not determine Windows Server version (2022/2025). Aborting activation."
    exit 1
}

$slmgr = Join-Path $env:SystemRoot "System32\slmgr.vbs"

Write-Host ("Detected: {0}. Applying product key: {1}" -f $label, $key)
& cscript.exe //nologo $slmgr /ipk $key

Write-Host "Activating Windows..."
& cscript.exe //nologo $slmgr /ato

Write-Host ""
Write-Host "License status:"
& cscript.exe //nologo $slmgr /dli
