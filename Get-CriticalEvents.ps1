<#
.SYNOPSIS
    Pulls recent critical/error events from a machine and summarizes patterns.

.DESCRIPTION
    Useful when a store calls in about "the computer's been acting weird" and
    you need a fast read on what's actually been failing, without opening
    Event Viewer and scrolling manually.

.PARAMETER ComputerName
    Target machine. Defaults to local.

.PARAMETER Hours
    How far back to search. Default 48.

.PARAMETER LogNames
    Event logs to search. Default System, Application.

.PARAMETER Top
    How many top recurring Event IDs to summarize. Default 10.

.EXAMPLE
    .\Get-CriticalEvents.ps1 -ComputerName STORE07-POS03 -Hours 72
#>

[CmdletBinding()]
param(
    [string]$ComputerName = $env:COMPUTERNAME,
    [int]$Hours = 48,
    [string[]]$LogNames = @('System', 'Application'),
    [int]$Top = 10
)

try {
    $events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
        LogName   = $LogNames
        Level     = 1, 2  # Critical, Error
        StartTime = (Get-Date).AddHours(-$Hours)
    } -ErrorAction Stop
} catch [Exception] {
    if ($_.Exception.Message -like '*No events*') {
        Write-Host "No critical/error events found on $ComputerName in the last $Hours hours." -ForegroundColor Green
        return
    }
    throw
}

Write-Host "Found $($events.Count) critical/error events on $ComputerName (last $Hours hours)" -ForegroundColor Cyan
Write-Host ""

Write-Host "--- Top recurring Event IDs ---" -ForegroundColor Yellow
$events |
    Group-Object -Property Id, ProviderName |
    Sort-Object Count -Descending |
    Select-Object -First $Top |
    ForEach-Object {
        $sample = $_.Group[0]
        [PSCustomObject]@{
            Count      = $_.Count
            EventId    = $sample.Id
            Provider   = $sample.ProviderName
            LastSeen   = ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
            SampleText = ($sample.Message -split "`n")[0]
        }
    } | Format-Table -AutoSize -Wrap

Write-Host ""
Write-Host "--- Most recent 15 events ---" -ForegroundColor Yellow
$events |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 15 TimeCreated, Id, LevelDisplayName, ProviderName |
    Format-Table -AutoSize
