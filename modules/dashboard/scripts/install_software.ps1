# install_software.ps1 - installs a minimal software set:
#   7-Zip, Google Chrome, PuTTY, WinSCP, Notepad++, Radmin VPN, VMware Tools.
# Strategy per app:
#   1) skip if already installed (registry / known paths);
#   2) winget install -e --id <id> (with a hard timeout) when winget exists;
#   3) otherwise a direct download + silent install (job-based download so a
#      stalled transfer can never hang the run; per-app download timeouts).
# At the end prints a per-app SOFTWARE SUMMARY and exits non-zero if any app
# FAILED, so the GUI per-item summary can show it.
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

$DownloadTimeoutSec = 300
$InstallTimeoutMs   = 300000   # 5 minutes per installer
$stamp = Get-Date -Format "yyyyMMddHHmmss"

$script:results = @()
function Add-Result([string]$name, [string]$status, [string]$detail = "") {
    $script:results += ,@{ name = $name; status = $status; detail = $detail }
}

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
    # Keep the real extension LAST (npp_<stamp>.exe) so Windows/Start-Process
    # recognises the file type; a name like "npp.exe_<stamp>" would pop the
    # "How do you want to open this file?" shell dialog and block the run.
    $ext  = [System.IO.Path]::GetExtension($name)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    return (Join-Path $env:TEMP ($base + "_" + $stamp + $ext))
}

# Download inside a background job so a stalled transfer can never hang the
# run. Tries every URL in $urls, up to 2 attempts per URL.
function Invoke-Download([string[]]$urls, [string]$dst, [string]$name, [int]$timeoutSec = $DownloadTimeoutSec) {
    foreach ($url in $urls) {
        for ($i = 1; $i -le 2; $i++) {
            Write-Host ("  Downloading {0} (attempt {1}, {2}s limit) ..." -f $name, $i, $timeoutSec)
            Write-Host ("    from $url")
            Remove-Item $dst -Force -ErrorAction SilentlyContinue
            $job = Start-Job -ScriptBlock {
                param($u, $f)
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
            } -ArgumentList $url, $dst
            if (Wait-Job $job -Timeout $timeoutSec) {
                $jerr = (Receive-Job $job 2>&1 | Out-String).Trim()
                Remove-Job $job -Force
                if ((Test-Path $dst) -and (Get-Item $dst).Length -gt 0) { return $true }
                Write-Host ("  {0} attempt {1} finished but no file was written." -f $name, $i)
                if ($jerr) { Write-Host ("    download error: " + $jerr) }
            } else {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -Force
                Write-Host ("  TIMEOUT: {0} download exceeded {1}s - killed." -f $name, $timeoutSec)
            }
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

function Invoke-Winget([string]$id, [string]$name) {
    $p = Start-Process -FilePath "winget" -ArgumentList "install","-e","--id",$id,"--silent","--accept-source-agreements","--accept-package-agreements" -PassThru -NoNewWindow
    if (-not $p.WaitForExit($InstallTimeoutMs)) {
        try { $p.Kill() } catch {}
        Write-Host ("  TIMEOUT: winget {0} exceeded {1} ms - killed." -f $name, $InstallTimeoutMs)
        return $false
    }
    if ($p.ExitCode -eq 0) { Write-Host ("  OK: {0} via winget." -f $name); return $true }
    Write-Host ("  winget {0} exit {1}." -f $name, $p.ExitCode)
    return $false
}

function Test-Winget {
    try { $null = Get-Command winget -ErrorAction Stop; return $true } catch { }
    try {
        $p = Start-Process -FilePath "winget" -ArgumentList "--version" -PassThru -NoNewWindow
        if ($p.WaitForExit(10000)) { return ($p.ExitCode -eq 0) }
        try { $p.Kill() } catch {}
    } catch { }
    return $false
}

function Install-Msi([string[]]$urls, [string]$baseName, [string]$name, [string[]]$paths, [string[]]$patterns, [int]$timeoutSec = $DownloadTimeoutSec) {
    if (Test-Installed $paths $patterns) { Add-Result $name "SKIP" "already installed"; return }
    $dst = Get-TempFile ($baseName + ".msi")
    if (-not (Invoke-Download $urls $dst $name $timeoutSec)) {
        Write-Host ("  {0}: download failed - skipped." -f $name)
        Add-Result $name "FAIL" "download failed"
        return
    }
    $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$dst`"", '/qn', '/norestart' -PassThru -NoNewWindow
    if (-not $p.WaitForExit($InstallTimeoutMs)) {
        try { $p.Kill() } catch {}
        Write-Host ("  TIMEOUT: {0} installer exceeded {1} ms - killed." -f $name, $InstallTimeoutMs)
        Add-Result $name "FAIL" "installer timeout"
    } elseif ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
        Write-Host ("  OK: {0} installed (exit {1})." -f $name, $p.ExitCode)
        Add-Result $name "OK" ("msi exit " + $p.ExitCode)
    } else {
        Write-Host ("  {0} installer exit {1}." -f $name, $p.ExitCode)
        Add-Result $name "FAIL" ("msi exit " + $p.ExitCode)
    }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

function Install-NotepadPlusPlus {
    $name = "Notepad++"
    if (Test-Installed @("$env:ProgramFiles\Notepad++\notepad++.exe") @("Notepad++*")) { Add-Result $name "SKIP" "already installed"; return }
    $urls = @()
    try {
        $xml = (Invoke-WebRequest "https://notepad-plus-plus.org/update/getDownloadUrl.php?version=8&param=x64" -UseBasicParsing -TimeoutSec 60).Content
        $loc = ([xml]$xml).GUP.Location
        if ($loc) { $urls += $loc }
    } catch { Write-Host ("  Notepad++ URL lookup failed: " + $_.Exception.Message) }
    $urls += "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.8.8/npp.8.8.8.Installer.x64.exe"
    $dst = Get-TempFile "npp.exe"
    if (Invoke-Download $urls $dst $name 300) {
        $p = Start-Process -FilePath $dst -ArgumentList '/S' -PassThru -NoNewWindow
        if (-not $p.WaitForExit($InstallTimeoutMs)) {
            try { $p.Kill() } catch {}
            Write-Host "  TIMEOUT: Notepad++ installer killed."
            Add-Result $name "FAIL" "installer timeout"
        } elseif ($p.ExitCode -eq 0) {
            Write-Host ("  OK: Notepad++ installed (exit 0).")
            Add-Result $name "OK" "silent exit 0"
        } else {
            Write-Host ("  Notepad++ installer exit {0}." -f $p.ExitCode)
            Add-Result $name "FAIL" ("installer exit " + $p.ExitCode)
        }
    } else {
        Write-Host "  Notepad++: download failed - skipped."
        Add-Result $name "FAIL" "download failed"
    }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

function Install-RadminVpn {
    $name = "Radmin VPN"
    if (Test-Installed @("${env:ProgramFiles(x86)}\Radmin VPN\RadminVPN.exe", "$env:ProgramFiles\Radmin VPN\RadminVPN.exe") @("Radmin VPN*")) { Add-Result $name "SKIP" "already installed"; return }
    $dst = Get-TempFile "radminvpn.exe"
    if (Invoke-Download @("https://download.radmin-vpn.com/download/files/Radmin_VPN_2.0.4899.9.exe") $dst $name 300) {
        $p = Start-Process -FilePath $dst -ArgumentList '/VERYSILENT', '/NORESTART' -PassThru -NoNewWindow
        if (-not $p.WaitForExit($InstallTimeoutMs)) {
            try { $p.Kill() } catch {}
            Write-Host "  TIMEOUT: Radmin VPN installer killed."
            Add-Result $name "FAIL" "installer timeout"
        } elseif ($p.ExitCode -eq 0) {
            Write-Host "  OK: Radmin VPN installed (exit 0)."
            Add-Result $name "OK" "silent exit 0"
        } else {
            Write-Host ("  Radmin VPN installer exit {0}." -f $p.ExitCode)
            Add-Result $name "FAIL" ("installer exit " + $p.ExitCode)
        }
    } else {
        Write-Host "  Radmin VPN: download failed - skipped."
        Add-Result $name "FAIL" "download failed"
    }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

function Install-VmwareTools {
    $name = "VMware Tools"
    if (Test-Installed @("$env:ProgramFiles\VMware\VMware Tools\vmtoolsd.exe") @("VMware Tools*")) { Add-Result $name "SKIP" "already installed"; return }
    $vmDir = "https://packages.vmware.com/tools/releases/latest/windows/x64/"
    $urls = @()
    try {
        $listing = (Invoke-WebRequest $vmDir -UseBasicParsing -TimeoutSec 60).Content
        if ($listing -match '(VMware-tools-[0-9\.]+-[0-9]+-x64\.exe)') { $urls += ($vmDir + $Matches[1]) }
    } catch { Write-Host ("  VMware Tools listing failed: " + $_.Exception.Message) }
    $urls += ($vmDir + "VMware-tools-13.1.5-25544008-x64.exe")
    # ~140 MB: give the download up to 15 minutes.
    $dst = Get-TempFile "vmware-tools.exe"
    if (Invoke-Download $urls $dst $name 900) {
        $p = Start-Process -FilePath $dst -ArgumentList '/S', '/v', '/qn' -PassThru -NoNewWindow
        if (-not $p.WaitForExit(600000)) {
            try { $p.Kill() } catch {}
            Write-Host "  TIMEOUT: VMware Tools installer killed."
            Add-Result $name "FAIL" "installer timeout"
        } elseif ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
            Write-Host ("  OK: VMware Tools installed (exit {0})." -f $p.ExitCode)
            Add-Result $name "OK" ("exit " + $p.ExitCode)
        } else {
            Write-Host ("  VMware Tools installer exit {0}." -f $p.ExitCode)
            Add-Result $name "FAIL" ("installer exit " + $p.ExitCode)
        }
    } else {
        Write-Host "  VMware Tools: download failed - skipped."
        Add-Result $name "FAIL" "download failed"
    }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

$haveWinget = Test-Winget
Write-Host ("winget available: {0}" -f $haveWinget)

$apps = @(
    @{ id = "7zip.7zip"; name = "7-Zip"; paths = @("$env:ProgramFiles\7-Zip\7z.exe"); pat = @("7-Zip*");
       direct = { Install-Msi @("https://www.7-zip.org/a/7z2409-x64.msi") "7z" "7-Zip" @("$env:ProgramFiles\7-Zip\7z.exe") @("7-Zip*") } },
    @{ id = "Google.Chrome"; name = "Google Chrome"; paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe"); pat = @("Google Chrome*");
       direct = { Install-Msi @("https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi") "chrome" "Google Chrome" @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe") @("Google Chrome*") } },
    @{ id = "PuTTY.PuTTY"; name = "PuTTY"; paths = @("$env:ProgramFiles\PuTTY\putty.exe"); pat = @("PuTTY*");
       direct = { Install-Msi @("https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.85-installer.msi") "putty" "PuTTY" @("$env:ProgramFiles\PuTTY\putty.exe") @("PuTTY*") } },
    @{ id = "WinSCP.WinSCP"; name = "WinSCP"; paths = @("${env:ProgramFiles(x86)}\WinSCP\WinSCP.exe", "$env:ProgramFiles\WinSCP\WinSCP.exe"); pat = @("WinSCP*");
       direct = { Install-Msi @("https://sourceforge.net/projects/winscp/files/WinSCP/6.5.7/WinSCP-6.5.7.msi/download") "winscp" "WinSCP" @("${env:ProgramFiles(x86)}\WinSCP\WinSCP.exe", "$env:ProgramFiles\WinSCP\WinSCP.exe") @("WinSCP*") } },
    @{ id = "Notepad++.Notepad++"; name = "Notepad++"; paths = @("$env:ProgramFiles\Notepad++\notepad++.exe"); pat = @("Notepad++*");
       direct = { Install-NotepadPlusPlus } },
    @{ id = "Famatech.RadminVPN"; name = "Radmin VPN"; paths = @("${env:ProgramFiles(x86)}\Radmin VPN\RadminVPN.exe", "$env:ProgramFiles\Radmin VPN\RadminVPN.exe"); pat = @("Radmin VPN*");
       direct = { Install-RadminVpn } },
    @{ id = "VMware.VMwareTools"; name = "VMware Tools"; paths = @("$env:ProgramFiles\VMware\VMware Tools\vmtoolsd.exe"); pat = @("VMware Tools*");
       direct = { Install-VmwareTools } }
)

foreach ($app in $apps) {
    if (Test-Installed $app.paths $app.pat) {
        Write-Host ("  SKIP: {0} already installed." -f $app.name)
        Add-Result $app.name "SKIP" "already installed"
        continue
    }
    $done = $false
    if ($haveWinget) {
        Write-Host ("  winget install -e --id {0} ..." -f $app.id)
        $done = Invoke-Winget $app.id $app.name
        if ($done) { Add-Result $app.name "OK" "winget" }
    }
    if (-not $done) {
        if ($haveWinget) { Write-Host ("  winget failed for {0} - direct install." -f $app.name) }
        & $app.direct
    }
}

Write-Host ""
Write-Host "===== SOFTWARE SUMMARY ====="
$failed = 0
foreach ($r in $script:results) {
    $line = ("  [{0}] {1}" -f $r.status, $r.name)
    if ($r.detail) { $line += " - " + $r.detail }
    Write-Host $line
    if ($r.status -eq "FAIL") { $failed++ }
}
Write-Host ("Total: {0}, failed: {1}" -f $script:results.Count, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
