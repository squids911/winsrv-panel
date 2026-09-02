# get_nics.ps1 — lists network adapters with IPv4 / gateway / DNS.
# NOTE: keep ASCII-only.

Get-NetIPConfiguration -All | Where-Object { $_.IPv4Address } | ForEach-Object {
    [PSCustomObject]@{
        Adapter = $_.InterfaceAlias
        IP      = ($_.IPv4Address.IPAddress -join ', ')
        Gateway = ($_.IPv4DefaultGateway.NextHop -join ', ')
        DNS     = ($_.DNSServer.ServerAddresses -join ', ')
    }
} | Format-Table -AutoSize
