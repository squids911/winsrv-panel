# install_software.ps1 - installs a minimal software set:
#   7-Zip, Google Chrome, PuTTY, WinSCP.
# Strategy:
#   - skip an app if it is already installed (registry / known paths);
#   - winget when available, otherwise direct download + silent install;
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

function Test-Installed([string[]]$paths, [string[]]$namePatterns) {
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($r in $roots) {
        $items = Get-ItemProperty $r -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName }
        foreach ($it in $items) {
            foreach ($pat in $namePatterns) {
                if ($it.DisplayName -like $pat) { return $true }
            }
        }
    }
    return $false
}

function Invoke-WithTimeout([scriptblock]$block, [int]$ms, [string]$what) {
    $job = Start-Job -ScriptBlock $block
    if (Wait-Job $job -Timeout ($ms / 1000)) {
        $res = Receive-Job $job
        Remove-Job $job -Force
        return $res
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force
        Write-Host ("  TIMEOUT: {0} exceeded {1} ms - skipped." -f $what, $ms)
        return $null
    }
}

function Install-Msi([string]$url, [string]$file, [string]$name, [string[]]$paths, [string[]]$patterns, [string]$installerArgs) {
    if (Test-Installed $paths $patterns) {
        Write-Host ("  SKIP: {0} already installed." -f $name)
        return
    }
    $dst = Join-Path $env:TEMP $file
    try {
        Write-Host ("  Downloading {0} ..." -f $name)
        Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing -TimeoutSec $DownloadTimeoutSec
    } catch {
        Write-Host ("  {0} download failed: {1}" -f $name, $_.Exception.Message)
        return
    }
    $argList = $installerArgs -f "`"$dst`""
    $p = Start-Process msiexec.exe -ArgumentList $argList -PassThru
    if (-not $p.WaitForExit($InstallTimeoutMs)) {
        try { $p.Kill() } catch {}
        Write-Host ("  TIMEOUT: {0} installer exceeded {1} ms - killed." -f $name, $InstallTimeoutMs)
        return
    }
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
        Write-Host ("  OK: {0} installed (exit {1})." -f $name, $p.ExitCode)
    } else {
        Write-Host ("  {0} installer exit {1}." -f $name, $p.ExitCode)
    }
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
        $blk = [scriptblock]::Create("winget install --id $($m.id) -e --silent --accept-source-agreements --accept-package-agreements")
        $null = Invoke-WithTimeout $blk $InstallTimeoutMs ("winget " + $m.name)
    }
} else {
    Write-Host "winget not found - direct download (skip if installed, with timeouts)."
    # NOTE: versioned URLs may need updating over time.
    Install-Msi "https://www.7-zip.org/a/7z2409-x64.msi" "7z.msi" "7-Zip" `
        @("$env:ProgramFiles\7-Zip\7z.exe") @("7-Zip*") '/i {0} /qn /norestart'
    Install-Msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" "chrome.msi" "Google Chrome" `
        @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe") @("Google Chrome*") '/i {0} /qn /norestart'
    Install-Msi "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.81-installer.msi" "putty.msi" "PuTTY" `
        @("$env:ProgramFiles\PuTTY\putty.exe") @("PuTTY*") '/i {0} /qn /norestart'
    # WinSCP is an EXE installer.
    if (Test-Installed @("${env:ProgramFiles(x86)}\WinSCP\WinSCP.exe") @("WinSCP*")) {
        Write-Host "  SKIP: WinSCP already installed."
    } else {
        try {
            $u = "https://winscp.net/download/WinSCP-6.3.5-Setup.exe"
            $dst = Join-Path $env:TEMP "winscp.exe"
            Write-Host "  Downloading WinSCP ..."
            Invoke-WebRequest -Uri $u -OutFile $dst -UseBasicParsing -TimeoutSec $DownloadTimeoutSec
            $p = Start-Process $dst -ArgumentList '/VERYSILENT', '/NORESTART' -PassThru
            if (-not $p.WaitForExit($InstallTimeoutMs)) { try { $p.Kill() } catch {}; Write-Host "  TIMEOUT: WinSCP installer killed." }
            else { Write-Host ("  OK: WinSCP installed (exit {0})." -f $p.ExitCode) }
        } catch {
            Write-Host ("  WinSCP failed: " + $_.Exception.Message)
        }
    }
}

Write-Host "Minimal software installation finished."
