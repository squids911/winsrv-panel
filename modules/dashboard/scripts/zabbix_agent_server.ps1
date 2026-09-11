# ==============================================================================
# zabbix_agent_server.ps1
#   Windows: install Zabbix Agent 2 (MSI 7.4.14) monitored DIRECTLY by the server.
#   + create/update host via API (deploy token, Bearer header)
#   + template "Windows by Zabbix agent active", group "Windows servers"
#   + PSK (generated; reused from API if the host already exists)
# NOTE: keep ASCII-only.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$HostName  = $env:COMPUTERNAME,
    [string]$ZbxServer = "37.17.55.196",
    [string]$ApiUrl    = "https://z.csl.by/api_jsonrpc.php",
    [string]$ApiToken  = "a79f44635ae19ff21848e7c66c30ead84a621ac89c54eb6f679b275703c3d714",
    [string]$TplName   = "Windows by Zabbix agent active",
    [string]$GroupName = "Windows servers",
    [string]$MsiUrl    = "https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.14/zabbix_agent2-7.4.14-windows-amd64-openssl.msi"
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

$ErrorActionPreference = "Stop"
function Say($c, $m) { Write-Host "[$c] $m" }
function Fail($m)    { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Fail "Run PowerShell as Administrator." }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAll : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int pr) { return true; }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll

function ZApi([string]$method, [string]$params) {
    $body = '{"jsonrpc":"2.0","method":"' + $method + '","params":' + $params + ',"id":1}'
    $hdr  = @{ 'Content-Type' = 'application/json-rpc'; 'Authorization' = ('Bearer ' + $ApiToken) }
    try { $r = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $hdr -Body $body -TimeoutSec 30 }
    catch { Fail ("API request fail: " + $_.Exception.Message) }
    if ($r.PSObject.Properties.Name -contains 'error') { Fail ("API ERROR: " + ($r.error | ConvertTo-Json -Compress)) }
    return $r.result
}
$e = $HostName -replace '\\', '\\\\' -replace '"', '\"'

Say "OK" "host=$HostName  server=$ZbxServer"

# --- local IP ---
$ip = "127.0.0.1"
try {
    $nic = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
    if ($nic) { $ip = $nic.IPv4Address.IPAddress }
} catch {}
Say "OK" "local IP: $ip"

# ===================== 1/5 PSK: from server or new ==========================
$exist = ZApi "host.get" ('{"filter":{"host":["' + $e + '"]},"output":["hostid","tls_psk","tls_psk_identity"]}')
$hostId = $null; $psk = $null
if ($exist.Count -gt 0) { $hostId = $exist[0].hostid; if ($exist[0].tls_psk) { $psk = $exist[0].tls_psk } }
if ($psk) { Say "OK" "host exists (hostid=$hostId), PSK taken from API" }
else {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $b = New-Object byte[] 32; $rng.GetBytes($b)
    $psk = (($b | ForEach-Object { $_.ToString('x2') }) -join '')
    Say "OK" "new PSK generated"
}

# ===================== 2/5 PSK file BEFORE msiexec! =========================
$agentDir = Join-Path $env:ProgramFiles "Zabbix Agent 2"
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
$pskFile = Join-Path $agentDir "agent2.psk"
[System.IO.File]::WriteAllText($pskFile, $psk)
Say "OK" "PSK file created: $pskFile"

# ===================== 3/5 MSI download + install ===========================
$msi = Join-Path $env:TEMP "zabbix_agent2.msi"
if (-not (Test-Path $msi)) {
    Say "..." "Downloading MSI (7.4.14)..."
    Invoke-WebRequest -Uri $MsiUrl -OutFile $msi -UseBasicParsing
}
Say "OK" ("MSI: " + [math]::Round((Get-Item $msi).Length/1MB, 1) + " MB")

$svc = Get-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue
if ($svc) {
    Say "..." "Cleaning old service..."
    Stop-Service "Zabbix Agent 2" -Force -ErrorAction SilentlyContinue
    sc.exe delete "Zabbix Agent 2" | Out-Null
    Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Zabbix Agent 2" -Recurse -ErrorAction SilentlyContinue
    Start-Sleep 2
}

$serverVal = $ZbxServer
$msiArgs = '/i', "`"$msi`"", '/qn',
        "SERVER=$serverVal", "SERVERACTIVE=$serverVal", "HOSTNAME=$HostName",
        "TLSCONNECT=psk", "TLSACCEPT=psk", "TLSPSKIDENTITY=$HostName", "TLSPSKFILE=`"$pskFile`"",
        "ENABLEREMOTECOMMANDS=1"
$p = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
if ($p.ExitCode -ne 0) { Fail ("msiexec exit " + $p.ExitCode) }
Say "OK" "Zabbix Agent 2 installed (MSI)"

Set-Service "Zabbix Agent 2" -StartupType Automatic
Start-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue
Start-Sleep 2
if ((Get-Service "Zabbix Agent 2").Status -ne "Running") { Fail "Service did not start - see C:\Program Files\Zabbix Agent 2\zabbix_agent2.log" }
Say "OK" "Service Running"

try {
    New-NetFirewallRule -DisplayName "Zabbix Agent 2 (10050)" -Direction Inbound -Protocol TCP -LocalPort 10050 -Action Allow -ErrorAction SilentlyContinue | Out-Null
} catch {}

# ===================== 4/5 group + template via API =========================
$g = ZApi "hostgroup.get" ('{"filter":{"name":["' + $GroupName + '"]},"output":["groupid"]}')
if ($g.Count -gt 0) { $gid = $g[0].groupid } else { $gid = (ZApi "hostgroup.create" ('{"name":"' + $GroupName + '"}')).groupids[0]; Say "OK" "group created" }
$t = ZApi "template.get" ('{"filter":{"host":["' + $TplName + '"]},"output":["templateid"]}')
if ($t.Count -eq 0) {
    $TplName = "Windows by Zabbix agent"
    $t = ZApi "template.get" ('{"filter":{"host":["' + $TplName + '"]},"output":["templateid"]}')
}
if ($t.Count -eq 0) { Fail "Template 'Windows by Zabbix agent [active]' not found on the server" }
$tid = $t[0].templateid
Say "OK" "group=$gid  template=$TplName ($tid)"

# ===================== 5/5 host via API (create/update) =====================
$iface = '{"type":1,"main":1,"useip":1,"ip":"' + $ip + '","dns":"","port":"10050"}'
$tlsv  = '"tls_connect":2,"tls_accept":2,"tls_psk_identity":"' + $e + '","tls_psk":"' + $psk + '"'
$base  = '"groups":[{"groupid":"' + $gid + '"}],"templates":[{"templateid":"' + $tid + '"}],"interfaces":[' + $iface + '],' + $tlsv
if ($hostId) {
    ZApi "host.update" ('{"hostid":"' + $hostId + '",' + $base + '}') | Out-Null
    Say "OK" "host updated (hostid=$hostId)"
} else {
    $hostId = (ZApi "host.create" ('{"host":"' + $e + '",' + $base + '}')).hostids[0]
    Say "OK" "host created (hostid=$hostId)"
}

Write-Host ""
Say "OK" "DONE: $HostName -> server directly ($ZbxServer), PSK, '$TplName'"
Write-Host "[!] ZBX turns green in ~2 min (Data collection -> Hosts)." -ForegroundColor Yellow
