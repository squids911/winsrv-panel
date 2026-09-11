# activate_os.ps1 - detects Windows Server VERSION and EDITION, installs the
# matching GVLK product key and activates - all through WMI (SoftwareLicensing*),
# which returns proper Unicode (no slmgr/cscript code-page mojibake).
#
# Keys (public Microsoft GVLK / KMS client setup keys):
#   2022 Datacenter : WX4NM-KYWYW-QJJR4-XV3QB-6VM33   (provided)
#   2022 Standard   : VDYBN-27WPP-V4HQT-9VMD4-VMK7H
#   2025 Datacenter : D764K-2NDRG-47T6Q-P8T8W-YP6DF   (provided)
#   2025 Standard   : TVRH6-WHNXV-R9WG3-9XRFY-MY832
#
# NOTE: GVLK keys activate against a KMS host. If no KMS server is reachable,
#       activation returns 0xC004F034 - that is an environment issue, not a bug.
# NOTE: keep ASCII-only.

[CmdletBinding()]
param(
    [string]$Key2022Datacenter = "WX4NM-KYWYW-QJJR4-XV3QB-6VM33",
    [string]$Key2022Standard   = "VDYBN-27WPP-V4HQT-9VMD4-VMK7H",
    [string]$Key2025Datacenter = "D764K-2NDRG-47T6Q-P8T8W-YP6DF",
    [string]$Key2025Standard   = "TVRH6-WHNXV-R9WG3-9XRFY-MY832",
    [string]$KmsServer         = ""
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

# --- detect version + edition ------------------------------------------------
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$caption = $os.Caption
try { $build = [int]$os.BuildNumber } catch { $build = 0 }
Write-Host ("Operating system: {0} (build {1})" -f $caption, $build)

if ($caption -match "2025" -or $build -ge 26100) { $ver = "2025" }
elseif ($caption -match "2022" -or ($build -ge 20348 -and $build -lt 26100)) { $ver = "2022" }
else { $ver = $null }

if ($caption -match "Datacenter") { $edition = "Datacenter" }
elseif ($caption -match "Standard") { $edition = "Standard" }
else { $edition = $null }

if (-not $ver -or -not $edition) {
    Write-Error ("Could not determine Windows Server version/edition (got ver={0}, edition={1}). Aborting." -f $ver, $edition)
    exit 1
}

$key = switch ("$ver|$edition") {
    "2022|Datacenter" { $Key2022Datacenter }
    "2022|Standard"   { $Key2022Standard }
    "2025|Datacenter" { $Key2025Datacenter }
    "2025|Standard"   { $Key2025Standard }
    default           { $null }
}

Write-Host ("Detected: Windows Server {0} {1}. Using GVLK: {2}" -f $ver, $edition, $key)

# --- helper: map common licensing HRESULTs -----------------------------------
function Describe-HResult($hr) {
    if ($null -eq $hr) { return "unknown error (no error code reported)" }
    $h = "0x{0:X8}" -f ([int]$hr -band 0xFFFFFFFF)
    $msg = switch ($h) {
        "0xC004F069" { "product key is not valid for this edition (edition/key mismatch)" }
        "0xC004F034" { "license not activated - no reachable KMS host (KMS activation requires a KMS server)" }
        "0xC004F074" { "no Key Management Service (KMS) could be contacted" }
        "0xC004F050" { "the product key is invalid" }
        "0xC004F012" { "the call has timed out" }
        default      { "licensing error" }
    }
    return ("{0} - {1}" -f $h, $msg)
}

# --- install key + activate via WMI ------------------------------------------
$sls = Get-WmiObject -Query "SELECT * FROM SoftwareLicensingService" -ErrorAction SilentlyContinue
if (-not $sls) { Write-Error "SoftwareLicensingService is not available."; exit 1 }

try { $null = $sls.InstallProductKey($key) | Out-Null; Write-Host "Product key installed." } catch {
    $hr = $null
    if ($_.Exception.Message -match "0x[0-9A-Fa-f]{8}") { $hr = [Convert]::ToInt32($Matches[0], 16) }
    Write-Error ("Failed to install product key: {0}" -f (Describe-HResult $hr))
    Write-Host ("Raw error: {0}" -f $_.Exception.Message)
    exit 1
}

try { $null = $sls.RefreshLicenseStatus() | Out-Null } catch { }

$appId = "55c92734-d682-4d71-983e-d6ec3f16059f"   # Windows OS application id
$product = Get-WmiObject -Query ("SELECT * FROM SoftwareLicensingProduct WHERE ApplicationID='{0}' AND PartialProductKey IS NOT NULL" -f $appId) -ErrorAction SilentlyContinue

if (-not $product) {
    Write-Error "Could not find the active licensing product after installing the key."
    exit 1
}

$slmgr = Join-Path $env:SystemRoot "System32\slmgr.vbs"

# If a KMS host is provided, point the KMS client at it (slmgr /skms) so the
# GVLK key can actually activate. Output captured (not printed) to avoid noise.
if ($KmsServer -and $KmsServer.Trim() -ne "") {
    Write-Host ("Setting KMS host: {0}" -f $KmsServer)
    $skmsOut = & cscript.exe //nologo $slmgr /skms $KmsServer 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "KMS host set."
    } else {
        Write-Host ("WARNING: slmgr /skms returned exit {0}." -f $LASTEXITCODE)
    }
} else {
    Write-Host "No KMS server provided - skipping /skms (GVLK will need a KMS host to activate)."
}

Write-Host "Activating Windows (slmgr /ato)..."
$atoOut = & cscript.exe //nologo $slmgr /ato 2>&1 | Out-String
$atoCode = $LASTEXITCODE
$hr = $null
if ($atoOut -match "0x[0-9A-Fa-f]{8}") { $hr = [Convert]::ToInt32($Matches[0], 16) }
if ($atoCode -eq 0) {
    Write-Host "Activation call succeeded."
} else {
    Write-Host ("Activation failed: {0}" -f (Describe-HResult $hr))
    Write-Host "NOTE: GVLK keys activate against a KMS host. If no KMS server is"
    Write-Host "      reachable this is expected - check KMS connectivity, then re-run."
}

# --- report final status (clean Unicode) -------------------------------------
try { $product.Refresh() } catch { }
$st = $null
try { $st = (Get-WmiObject -Query ("SELECT * FROM SoftwareLicensingProduct WHERE ApplicationID='{0}' AND PartialProductKey IS NOT NULL" -f $appId)).LicenseStatus } catch { }
$stText = switch ($st) {
    0 { "Unlicensed" }
    1 { "Licensed (activated)" }
    2 { "OOBGrace" }
    3 { "OOTGrace" }
    4 { "NonGenuineGrace" }
    5 { "Notification (not activated)" }
    6 { "ExtendedGrace" }
    default { ("Unknown ({0})" -f $st) }
}
Write-Host ""
Write-Host ("License status: {0}" -f $stText)
