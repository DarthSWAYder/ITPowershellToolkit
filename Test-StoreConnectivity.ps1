<#
.SYNOPSIS
    Runs a connectivity sweep against a list of hosts (stores, servers, POS terminals).

.DESCRIPTION
    Checks ping, DNS resolution, and optional TCP port reachability for each
    target. Built for quickly narrowing down "is it the network or the machine"
    before an emergency site visit.

.PARAMETER TargetsPath
    Path to a text file with one hostname or IP per line.

.PARAMETER TargetList
    Alternative to -TargetsPath: pass hostnames/IPs directly.

.PARAMETER Ports
    TCP ports to test on each target (e.g. 445 for SMB, 3389 for RDP, 443 for HTTPS).

.PARAMETER ExportPath
    Optional CSV export path.

.EXAMPLE
    .\Test-StoreConnectivity.ps1 -TargetsPath .\stores.txt -Ports 445,3389 -ExportPath C:\Reports\connectivity.csv

.EXAMPLE
    .\Test-StoreConnectivity.ps1 -TargetList STORE01-SRV, STORE02-SRV -Ports 443
#>

[CmdletBinding(DefaultParameterSetName = 'FromFile')]
param(
    [Parameter(ParameterSetName = 'FromFile')]
    [string]$TargetsPath,

    [Parameter(ParameterSetName = 'FromList')]
    [string[]]$TargetList,

    [int[]]$Ports,

    [string]$ExportPath
)

if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
    if (-not (Test-Path $TargetsPath)) {
        throw "Targets file not found: $TargetsPath"
    }
    $targets = Get-Content -Path $TargetsPath | Where-Object { $_.Trim() -ne '' }
} else {
    $targets = $TargetList
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($target in $targets) {
    Write-Verbose "Testing $target..."
    $target = $target.Trim()

    $pingOk = Test-Connection -ComputerName $target -Count 2 -Quiet -ErrorAction SilentlyContinue

    $dnsOk = $true
    $resolvedIp = $null
    try {
        $resolvedIp = ([System.Net.Dns]::GetHostAddresses($target) | Select-Object -First 1).IPAddressToString
    } catch {
        $dnsOk = $false
    }

    $portResults = @{}
    if ($Ports) {
        foreach ($port in $Ports) {
            $portOk = $false
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connectTask = $tcp.ConnectAsync($target, $port)
                $portOk = $connectTask.Wait(2000) -and $tcp.Connected
                $tcp.Close()
            } catch {
                $portOk = $false
            }
            $portResults[$port] = $portOk
        }
    }

    $row = [ordered]@{
        Target      = $target
        PingOK      = $pingOk
        DNSResolved = $dnsOk
        ResolvedIP  = $resolvedIp
    }
    foreach ($port in $portResults.Keys) {
        $row["Port_$port"] = $portResults[$port]
    }

    $results.Add([PSCustomObject]$row)
}

if ($ExportPath) {
    $results | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "Results exported to $ExportPath" -ForegroundColor Green
}

$results | Format-Table -AutoSize

$down = $results | Where-Object { -not $_.PingOK }
if ($down) {
    Write-Host ""
    Write-Host "Unreachable targets:" -ForegroundColor Yellow
    $down | ForEach-Object { Write-Host "  - $($_.Target)" -ForegroundColor Yellow }
}
