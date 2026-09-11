# install_software.ps1 - installs a minimal software set:
#   7-Zip, Google Chrome, PuTTY, WinSCP.
# Strategy:
#   - skip an app if it is already installed (registry / known paths);
#   - winget when available, otherwise direct download + silent install;
#   - unique temp file names + retry, so a leftover/locked file cannot break it;
#   - every download and installer call has a TIMEOUT so a stuck step cannot
#     hang the whole run.
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

$DownloadTimeoutSec = 90
$InstallTimeoutMs   = 180000   # 3 minutes per installer
$stamp = Get-Date -Format "yyyyMMddHHmmss"

function Test-Installed([string[]]$paths, [string[]]$namePatterns) {
    foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $true } }
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($r in $roots) {
        $items = Get-ItemProperty $r -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
        foreach ($it in $items) {
            foreach ($pat in $namePatterns) { if ($it.DisplayName -like $pat) { return $true } }
        }
    }
    return $false
}

function Get-TempFile([string]$name) {
    # Unique per-run name so a locked/leftover file from a previous run cannot
    # cause "file is being used by another process".
    return (Join-Path $env:TEMP ($name + "_" + $stamp))
}

function Invoke-Download([string]$url, [string]$dst, [string]$name) {
    for ($i = 1; $i -le 2; $i++) {
        try {
            Write-Host ("  Downloading {0} (attempt {1}) ..." -f $name, $i)
            Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing -TimeoutSec $DownloadTimeoutSec
            return $true
        } catch {
            Write-Host ("  {0} download attempt {1} failed: {2}" -f $name, $i, $_.Exception.Message)
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

function Install-Msi([string]$url, [string]$baseName, [string]$name, [string[]]$paths, [string[]]$patterns) {
    if (Test-Installed $paths $patterns) { Write-Host ("  SKIP: {0} already installed." -f $name); return }
    $dst = Get-TempFile ($baseName + ".msi")
    if (-not (Invoke-Download $url $dst $name)) { Write-Host ("  {0}: download failed - skipped." -f $name); return }
    $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$dst`"", '/qn', '/norestart' -PassThru
    if (-not $p.WaitForExit($InstallTimeoutMs)) {
        try { $p.Kill() } catch {}
        Write-Host ("  TIMEOUT: {0} installer exceeded {1} ms - killed." -f $name, $InstallTimeoutMs)
    } elseif ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
        Write-Host ("  OK: {0} installed (exit {1})." -f $name, $p.ExitCode)
    } else {
        Write-Host ("  {0} installer exit {1}." -f $name, $p.ExitCode)
    }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

$haveWinget = $false
try { $null = Get-Command winget -ErrorAction Stop; $haveWinget = $true } catch { $haveWinget = $false }

if ($haveWinget) {
    Write-Host "winget found - installing via winget (skipping already installed)."
    $map = @(
        @{ id = "7zip.7zip";     name = "7-Zip";         paths = @("$env:ProgramFiles\7-Zip\7z.exe"); pat = @("7-Zip*") },
        @{ id = "Google.Chrome"; name = "Google Chrome"; paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe"); pat = @("Google Chrome*") },
        @{ id = "PuTTY.PuTTY";   name = "PuTTY";         paths = @("$env:ProgramFiles\PuTTY\putty.exe"); pat = @("PuTTY*") },
        @{ id = "WinSCP.WinSCP"; name = "WinSCP";        paths = @("${env:ProgramFiles(x86)}\WinSCP\WinSCP.exe"); pat = @("WinSCP*") }
    )
    foreach ($m in $map) {
        if (Test-Installed $m.paths $m.pat) { Write-Host ("  SKIP: {0} already installed." -f $m.name); continue }
        Write-Host ("  winget install {0} ..." -f $m.id)
        & winget install --id $m.id -e --silent --accept-source-agreements --accept-package-agreements
    }
} else {
    Write-Host "winget not found - direct download (skip if installed, unique temp files, timeouts)."
    Install-Msi "https://www.7-zip.org/a/7z2409-x64.msi" "7z" "7-Zip" `
        @("$env:ProgramFiles\7-Zip\7z.exe") @("7-Zip*")
    Install-Msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" "chrome" "Google Chrome" `
        @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe") @("Google Chrome*")
    Install-Msi "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.85-installer.msi" "putty" "PuTTY" `
        @("$env:ProgramFiles\PuTTY\putty.exe") @("PuTTY*")
    # WinSCP is an EXE installer; use the version-agnostic "latest" URL.
    if (Test-Installed @("${env:ProgramFiles(x86)}\WinSCP\WinSCP.exe") @("WinSCP*")) {
        Write-Host "  SKIP: WinSCP already installed."
    } else {
        $dst = Get-TempFile "winscp.exe"
        if (Invoke-Download "https://winscp.net/download/latest/WinSCP-Setup.exe" $dst "WinSCP") {
            $p = Start-Process $dst -ArgumentList '/VERYSILENT', '/NORESTART' -PassThru
            if (-not $p.WaitForExit($InstallTimeoutMs)) { try { $p.Kill() } catch {}; Write-Host "  TIMEOUT: WinSCP installer killed." }
            else { Write-Host ("  OK: WinSCP installed (exit {0})." -f $p.ExitCode) }
        } else {
            Write-Host "  WinSCP: download failed - skipped."
        }
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Minimal software installation finished."
