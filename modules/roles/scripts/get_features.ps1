# get_features.ps1 - lists ALL roles and features (from Get-WindowsFeature) as JSON.
# The GUI parses this to build the full selection menu.
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
$ErrorActionPreference = "Continue"

$items = @(Get-WindowsFeature | Where-Object { $_.Name -and $_.FeatureType } | ForEach-Object {
    [PSCustomObject]@{
        Name        = $_.Name
        DisplayName = $_.DisplayName
        FeatureType = $_.FeatureType
        Installed   = ($_.InstallState -eq 1)
        Description = $_.Description
        Path        = $_.Path
    }
})

# Force a JSON array even when there is a single item.
$json = ConvertTo-Json -InputObject @($items) -Depth 3
Write-Output $json
