# install_software.ps1 - installs a minimal software set:
#   7-Zip, Google Chrome, PuTTY, WinSCP, Notepad++, Radmin VPN, VMware Tools.
# Strategy per app:
#   1) skip if already installed (registry / known paths);
#   2) winget install -e --id <id> (with a hard timeout) when winget exists;
#   3) otherwise a direct download + silent install (job-based download so a
#      stalled transfer can never hang the whole run).
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

$DownloadTimeoutSec = 120
$InstallTimeoutMs   = 300000   # 5 minutes per installer
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
    return (Join-Path $env:TEMP ($name + "_" + $stamp))
}

# Download inside a background job so a stalled transfer can never hang the run.
function Invoke-Download([string]$url, [string]$dst, [string]$name) {
    for ($i = 1; $i -le 2; $i++) {
        Write-Host ("  Downloading {0} (attempt {1}) ..." -f $name, $i)
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
        $job = Start-Job -ScriptBlock {
            param($u, $f)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $u -OutFile $f -UseBasicParsing
        } -ArgumentList $url, $dst
        if (Wait-Job $job -Timeout $DownloadTimeoutSec) {
            Remove-Job $job -Force
            if (Test-Path $dst) { return $true }
            Write-Host ("  {0} attempt {1} finished but no file was written." -f $name, $i)
        } else {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force
            Write-Host ("  TIMEOUT: {0} download exceeded {1}s - killed." -f $name, $DownloadTimeoutSec)
        }
        Start-Sleep -Seconds 2
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
        try { $p.Kill() } catch { }
    } catch { }
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

function Install-NotepadPlusPlus {
    if (Test-Installed @("$env:ProgramFiles\Notepad++\notepad++.exe") @("Notepad++*")) { Write-Host "  SKIP: Notepad++ already installed."; return }
    $nppUrl = $null
    try {
        $xml = (Invoke-WebRequest "https://notepad-plus-plus.org/update/getDownloadUrl.php?version=8&param=x64" -UseBasicParsing -TimeoutSec 60).Content
        $nppUrl = ([xml]$xml).GUP.Location
    } catch { Write-Host ("  Notepad++ URL lookup failed: " + $_.Exception.Message) }
    if (-not $nppUrl) { $nppUrl = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.8.8/npp.8.8.8.Installer.x64.exe" }
    $dst = Get-TempFile "npp.exe"
    if (Invoke-Download $nppUrl $dst "Notepad++") {
        $p = Start-Process $dst -ArgumentList '/S' -PassThru
        if (-not $p.WaitForExit($InstallTimeoutMs)) { try { $p.Kill() } catch {}; Write-Host "  TIMEOUT: Notepad++ installer killed." }
        else { Write-Host ("  OK: Notepad++ installed (exit {0})." -f $p.ExitCode) }
    } else { Write-Host "  Notepad++: download failed - skipped." }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

function Install-RadminVpn {
    if (Test-Installed @("${env:ProgramFiles(x86)}\Radmin VPN\RadminVPN.exe", "$env:ProgramFiles\Radmin VPN\RadminVPN.exe") @("Radmin VPN*")) { Write-Host "  SKIP: Radmin VPN already installed."; return }
    $dst = Get-TempFile "radminvpn.exe"
    if (Invoke-Download "https://download.radmin-vpn.com/download/files/Radmin_VPN_2.0.4899.9.exe" $dst "Radmin VPN") {
        $p = Start-Process $dst -ArgumentList '/VERYSILENT', '/NORESTART' -PassThru
        if (-not $p.WaitForExit($InstallTimeoutMs)) { try { $p.Kill() } catch {}; Write-Host "  TIMEOUT: Radmin VPN installer killed." }
        else { Write-Host ("  OK: Radmin VPN installed (exit {0})." -f $p.ExitCode) }
    } else { Write-Host "  Radmin VPN: download failed - skipped." }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

function Install-VmwareTools {
    if (Test-Installed @("$env:ProgramFiles\VMware\VMware Tools\vmtoolsd.exe") @("VMware Tools*")) { Write-Host "  SKIP: VMware Tools already installed."; return }
    $vmDir = "https://packages.vmware.com/tools/releases/latest/windows/x64/"
    $vmExe = $null
    try {
        $listing = (Invoke-WebRequest $vmDir -UseBasicParsing -TimeoutSec 60).Content
        if ($listing -match '(VMware-tools-[0-9\.]+-[0-9]+-x64\.exe)') { $vmExe = $Matches[1] }
    } catch { Write-Host ("  VMware Tools listing failed: " + $_.Exception.Message) }
    if (-not $vmExe) { $vmExe = "VMware-tools-13.1.5-25544008-x64.exe" }
    $dst = Get-TempFile "vmware-tools.exe"
    if (Invoke-Download ($vmDir + $vmExe) $dst "VMware Tools") {
        $p = Start-Process $dst -ArgumentList '/S', '/v', '/qn' -PassThru
        if (-not $p.WaitForExit(600000)) { try { $p.Kill() } catch {}; Write-Host "  TIMEOUT: VMware Tools installer killed." }
        else { Write-Host ("  OK: VMware Tools installed (exit {0})." -f $p.ExitCode) }
    } else { Write-Host "  VMware Tools: download failed - skipped." }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}

$haveWinget = Test-Winget
Write-Host ("winget available: {0}" -f $haveWinget)

$apps = @(
    @{ id = "7zip.7zip"; name = "7-Zip"; paths = @("$env:ProgramFiles\7-Zip\7z.exe"); pat = @("7-Zip*");
       direct = { Install-Msi "https://www.7-zip.org/a/7z2409-x64.msi" "7z" "7-Zip" @("$env:ProgramFiles\7-Zip\7z.exe") @("7-Zip*") } },
    @{ id = "Google.Chrome"; name = "Google Chrome"; paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe"); pat = @("Google Chrome*");
       direct = { Install-Msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" "chrome" "Google Chrome" @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe") @("Google Chrome*") } },
    @{ id = "PuTTY.PuTTY"; name = "PuTTY"; paths = @("$env:ProgramFiles\PuTTY\putty.exe"); pat = @("PuTTY*");
       direct = { Install-Msi "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.85-installer.msi" "putty" "PuTTY" @("$env:ProgramFiles\PuTTY\putty.exe") @("PuTTY*") } },
    @{ id = "WinSCP.WinSCP"; name = "WinSCP"; paths = @("${env:ProgramFiles(x86)}\WinSCP\WinSCP.exe", "$env:ProgramFiles\WinSCP\WinSCP.exe"); pat = @("WinSCP*");
       direct = { Install-Msi "https://sourceforge.net/projects/winscp/files/WinSCP/6.5.7/WinSCP-6.5.7.msi/download" "winscp" "WinSCP" @("${env:ProgramFiles(x86)}\WinSCP\WinSCP.exe", "$env:ProgramFiles\WinSCP\WinSCP.exe") @("WinSCP*") } },
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
        continue
    }
    $done = $false
    if ($haveWinget) {
        Write-Host ("  winget install -e --id {0} ..." -f $app.id)
        $done = Invoke-Winget $app.id $app.name
    }
    if (-not $done) {
        if ($haveWinget) { Write-Host ("  winget failed for {0} - direct install." -f $app.name) }
        & $app.direct
    }
}

Write-Host "Minimal software installation finished."
