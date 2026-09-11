# install_software.ps1 - installs a minimal software set:
#   7-Zip, Google Chrome, PuTTY, WinSCP.
# Strategy: use winget when available; otherwise fall back to direct download
# and silent install (best effort - a failure of one item does not stop others).
# NOTE: keep ASCII-only.

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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Install-ByWinget([string]$id, [string]$name) {
    Write-Host ("winget install {0} ({1}) ..." -f $id, $name)
    & winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -eq 0) { Write-Host ("  OK: {0}" -f $name) }
    else { Write-Host ("  winget exit {0} for {1}" -f $LASTEXITCODE, $name) }
}

function Install-Msi([string]$url, [string]$file, [string]$name) {
    try {
        $dst = Join-Path $env:TEMP $file
        Write-Host ("Downloading {0} ..." -f $name)
        Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList '/i', "`"$dst`"", '/qn', '/norestart' -Wait
        Write-Host ("  OK: {0} (direct MSI)" -f $name)
    } catch {
        Write-Host ("  {0} failed: {1}" -f $name, $_.Exception.Message)
    }
}

$haveWinget = $false
try { $null = Get-Command winget -ErrorAction Stop; $haveWinget = $true } catch { $haveWinget = $false }

if ($haveWinget) {
    Write-Host "winget found - installing via winget."
    Install-ByWinget "7zip.7zip"      "7-Zip"
    Install-ByWinget "Google.Chrome"  "Google Chrome"
    Install-ByWinget "PuTTY.PuTTY"    "PuTTY"
    Install-ByWinget "WinSCP.WinSCP"  "WinSCP"
} else {
    Write-Host "winget not found - falling back to direct download (best effort)."
    # NOTE: versioned URLs may need updating over time.
    Install-Msi "https://www.7-zip.org/a/7z2409-x64.msi" "7z.msi" "7-Zip"
    Install-Msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" "chrome.msi" "Google Chrome"
    Install-Msi "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.81-installer.msi" "putty.msi" "PuTTY"
    try {
        $u = "https://winscp.net/download/WinSCP-6.3.5-Setup.exe"
        $dst = Join-Path $env:TEMP "winscp.exe"
        Write-Host "Downloading WinSCP ..."
        Invoke-WebRequest -Uri $u -OutFile $dst -UseBasicParsing
        Start-Process $dst -ArgumentList '/VERYSILENT', '/NORESTART' -Wait
        Write-Host "  OK: WinSCP (direct EXE)"
    } catch {
        Write-Host ("  WinSCP failed: " + $_.Exception.Message)
    }
}

Write-Host "Minimal software installation finished."
