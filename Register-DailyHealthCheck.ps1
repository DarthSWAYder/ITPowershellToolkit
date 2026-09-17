<#
.SYNOPSIS
    Registers (or removes) a Windows Scheduled Task that runs the system
    health report automatically on a daily basis.

.DESCRIPTION
    Sets up a Task Scheduler entry that runs Get-SystemHealthReport.ps1
    every day at a chosen time and appends the results to a CSV log, so you
    build a history of your machine's health over time without doing
    anything manually.

.PARAMETER Time
    Time of day to run, 24-hour format. Default "08:00".

.PARAMETER LogPath
    Where the CSV report is written/appended. Default C:\Reports\health-log.csv

.PARAMETER Unregister
    Removes the scheduled task instead of creating it.

.EXAMPLE
    .\Register-DailyHealthCheck.ps1 -Time "07:30" -LogPath C:\Reports\health-log.csv

.EXAMPLE
    .\Register-DailyHealthCheck.ps1 -Unregister

.NOTES
    Must be run as Administrator. The task runs whether or not you're
    logged in, using the SYSTEM account.
#>

[CmdletBinding()]
param(
    [string]$Time = "08:00",
    [string]$LogPath = "C:\Reports\health-log.csv",
    [switch]$Unregister
)

$taskName = "IT-Toolkit-DailyHealthCheck"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$healthScript = Join-Path $scriptDir "Get-SystemHealthReport.ps1"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "This script must be run as Administrator. Right-click PowerShell and 'Run as Administrator', then re-run."
    return
}

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Scheduled task '$taskName' removed." -ForegroundColor Green
    } else {
        Write-Host "No scheduled task named '$taskName' found." -ForegroundColor Yellow
    }
    return
}

if (-not (Test-Path $healthScript)) {
    throw "Could not find Get-SystemHealthReport.ps1 next to this script. Keep the toolkit files together."
}

$logDir = Split-Path -Parent $LogPath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Wraps the health check so results append to a running CSV log rather than overwrite it
$wrapperPath = Join-Path $scriptDir "_DailyHealthCheckWrapper.ps1"
$wrapperContent = @"
`$results = & '$healthScript'
`$results | Export-Csv -Path '$LogPath' -NoTypeInformation -Append -Force
"@
Set-Content -Path $wrapperPath -Value $wrapperContent -Encoding UTF8

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Runs the IT toolkit health check daily and logs results to $LogPath" | Out-Null

Write-Host "Scheduled task '$taskName' created - runs daily at $Time." -ForegroundColor Green
Write-Host "Results will append to: $LogPath" -ForegroundColor Green
Write-Host "To remove it later: .\Register-DailyHealthCheck.ps1 -Unregister" -ForegroundColor Cyan
