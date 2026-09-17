<#
.SYNOPSIS
    Runs a full triage pass (health, software snapshot, connectivity, event log)
    against one or more remote machines and writes a single HTML report.

.DESCRIPTION
    Ties together Get-SystemHealthReport, Get-CriticalEvents, and
    Test-StoreConnectivity into one call so a first pass on a "store computer
    is broken" ticket takes one command instead of five. Requires PS Remoting
    (WinRM) enabled on target machines, or run against localhost.

.PARAMETER ComputerName
    One or more target machines.

.PARAMETER OutputPath
    Path to write the HTML report. Defaults to .\triage-report-<timestamp>.html

.EXAMPLE
    .\Invoke-RemoteTriage.ps1 -ComputerName STORE14-POS02 -OutputPath C:\Reports\store14.html
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ComputerName,

    [string]$OutputPath = ".\triage-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Running system health checks..." -ForegroundColor Cyan
$health = & "$scriptDir\Get-SystemHealthReport.ps1" -ComputerName $ComputerName

Write-Host "Running connectivity checks..." -ForegroundColor Cyan
$connectivity = & "$scriptDir\Test-StoreConnectivity.ps1" -TargetList $ComputerName -Ports 445, 3389

$eventSections = foreach ($computer in $ComputerName) {
    Write-Host "Pulling recent errors for $computer..." -ForegroundColor Cyan
    try {
        $events = Get-WinEvent -ComputerName $computer -FilterHashtable @{
            LogName   = 'System', 'Application'
            Level     = 1, 2
            StartTime = (Get-Date).AddHours(-48)
        } -ErrorAction Stop | Select-Object -First 20 TimeCreated, Id, LevelDisplayName, ProviderName

        $rows = $events | ConvertTo-Html -Fragment -PreContent "<h3>$computer - Recent Critical/Error Events</h3>"
        $rows
    } catch {
        "<h3>$computer - Recent Critical/Error Events</h3><p><em>None found or log unavailable.</em></p>"
    }
}

$style = @"
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1a1a1a; }
  h1 { border-bottom: 2px solid #333; padding-bottom: 8px; }
  h2 { margin-top: 32px; color: #2a5c8a; }
  h3 { margin-top: 24px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
  th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; font-size: 13px; }
  th { background-color: #2a5c8a; color: white; }
  tr:nth-child(even) { background-color: #f4f6f8; }
</style>
"@

$healthHtml = $health | ConvertTo-Html -Fragment -PreContent "<h2>System Health</h2>"
$connHtml   = $connectivity | ConvertTo-Html -Fragment -PreContent "<h2>Connectivity</h2>"

$report = ConvertTo-Html -Head $style `
    -Title "Triage Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" `
    -Body "<h1>Remote Triage Report</h1><p>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') for: $($ComputerName -join ', ')</p>$healthHtml$connHtml$($eventSections -join '')"

$report | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host ""
Write-Host "Triage report written to $OutputPath" -ForegroundColor Green
