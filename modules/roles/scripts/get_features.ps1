# get_features.ps1 - lists ALL roles and features (from Get-WindowsFeature) as JSON.
# The GUI parses this to build the full selection menu.
# NOTE: keep ASCII-only.

# Force UTF-8 output so the GUI (Python) decodes Russian/system text correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
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
