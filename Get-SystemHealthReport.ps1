<#
.SYNOPSIS
    Generates a system health report for a local or remote Windows machine.

.DESCRIPTION
    Pulls CPU load, memory usage, disk space, uptime, pending reboot status,
    and recent critical/error events into a single object. Useful for quick
    triage before an in-person or remote troubleshooting call.

.PARAMETER ComputerName
    One or more computer names to check. Defaults to the local machine.

.PARAMETER EventHours
    How far back to look in the event log for errors/critical events. Default 24.

.PARAMETER ExportPath
    Optional path to export results as CSV. If omitted, results print to console.

.EXAMPLE
    .\Get-SystemHealthReport.ps1

.EXAMPLE
    .\Get-SystemHealthReport.ps1 -ComputerName STORE12-POS01, STORE12-BOSTER -ExportPath C:\Reports\health.csv

.EXAMPLE
    Get-Content .\stores.txt | .\Get-SystemHealthReport.ps1 -ExportPath C:\Reports\daily.csv
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [int]$EventHours = 24,

    [string]$ExportPath
)

begin {
    $results = [System.Collections.Generic.List[object]]::new()

    function Test-PendingReboot {
        param($CimSession)
        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
        )
        foreach ($p in $paths) {
            if (Test-Path $p) { return $true }
        }
        return $false
    }
}

process {
    foreach ($computer in $ComputerName) {
        Write-Verbose "Checking $computer..."
        try {
            $cimParams = @{ ComputerName = $computer; ErrorAction = 'Stop' }

            $os      = Get-CimInstance -ClassName Win32_OperatingSystem @cimParams
            $cpu     = Get-CimInstance -ClassName Win32_Processor @cimParams |
                       Measure-Object -Property LoadPercentage -Average |
                       Select-Object -ExpandProperty Average
            $disks   = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" @cimParams

            $uptime      = (Get-Date) - $os.LastBootUpTime
            $memFreePct  = [math]::Round(($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)

            $diskSummary = ($disks | ForEach-Object {
                $freePct = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
                "$($_.DeviceID) $freePct% free ($([math]::Round($_.FreeSpace/1GB,1))GB / $([math]::Round($_.Size/1GB,1))GB)"
            }) -join '; '

            $lowDisk = $disks | Where-Object { ($_.FreeSpace / $_.Size) -lt 0.10 }

            $recentErrors = $null
            try {
                $recentErrors = Get-WinEvent -ComputerName $computer -FilterHashtable @{
                    LogName   = 'System', 'Application'
                    Level     = 1, 2  # Critical, Error
                    StartTime = (Get-Date).AddHours(-$EventHours)
                } -ErrorAction Stop
            } catch {
                # No matching events is not a failure condition
            }

            $pendingReboot = $false
            if ($computer -eq $env:COMPUTERNAME) {
                $pendingReboot = Test-PendingReboot
            }

            $results.Add([PSCustomObject]@{
                ComputerName    = $computer
                Status          = 'Online'
                UptimeDays      = [math]::Round($uptime.TotalDays, 1)
                CPULoadPercent  = $cpu
                MemFreePercent  = $memFreePct
                DiskSummary     = $diskSummary
                LowDiskWarning  = if ($lowDisk) { ($lowDisk.DeviceID -join ', ') + ' below 10% free' } else { 'OK' }
                ErrorEventCount = if ($recentErrors) { $recentErrors.Count } else { 0 }
                PendingReboot   = $pendingReboot
                CheckedAt       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            })
        }
        catch {
            $results.Add([PSCustomObject]@{
                ComputerName    = $computer
                Status          = "Unreachable: $($_.Exception.Message)"
                UptimeDays      = $null
                CPULoadPercent  = $null
                MemFreePercent  = $null
                DiskSummary     = $null
                LowDiskWarning  = $null
                ErrorEventCount = $null
                PendingReboot   = $null
                CheckedAt       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            })
        }
    }
}

end {
    if ($ExportPath) {
        $results | Export-Csv -Path $ExportPath -NoTypeInformation
        Write-Host "Report exported to $ExportPath" -ForegroundColor Green
    }
    $results | Format-Table -AutoSize
}
