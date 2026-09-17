# PowerShell IT Automation Toolkit

A set of practical scripts for day-to-day desktop/field support and remote
site troubleshooting — health checks, software inventory, disk cleanup,
connectivity testing, event log triage, and a one-shot report generator that
ties them together.

## Requirements
- Windows PowerShell 5.1+ or PowerShell 7+
- For remote targets: WinRM/PS Remoting enabled (`Enable-PSRemoting`), or
  local admin rights + firewall access for CIM/WMI calls
- Run as Administrator for full results (disk cleanup, some event log queries)

## Scripts

### `Get-SystemHealthReport.ps1`
CPU load, memory, disk free space, uptime, pending reboot flag, and recent
error/critical event counts for one or more machines. Accepts pipeline input
and exports to CSV — good for a daily or weekly fleet-wide health pass.

```powershell
.\Get-SystemHealthReport.ps1 -ComputerName STORE12-POS01, STORE12-BOSTER -ExportPath C:\Reports\health.csv
Get-Content .\stores.txt | .\Get-SystemHealthReport.ps1 -ExportPath C:\Reports\daily.csv
```

### `Get-SoftwareInventory.ps1`
Reads installed software from the registry uninstall keys (fast — avoids the
`Win32_Product` MSI repair-scan trap). Filter by name, useful for license or
version audits across stores.

```powershell
.\Get-SoftwareInventory.ps1 -NameFilter "*Java*" -ExportPath C:\Reports\java_audit.csv
```

### `Clear-DiskSpace.ps1`
Clears temp folders, browser caches, and optionally the Windows Update
download cache, then empties the Recycle Bin. Supports `-WhatIf` to preview
before deleting anything.

```powershell
.\Clear-DiskSpace.ps1 -WhatIf
.\Clear-DiskSpace.ps1 -IncludeWindowsUpdateCache
```

### `Test-StoreConnectivity.ps1`
Ping + DNS + optional TCP port sweep across a list of hosts. Built for the
"is it the network or the machine" triage step before deciding a site visit
is needed.

```powershell
.\Test-StoreConnectivity.ps1 -TargetsPath .\stores.txt -Ports 445,3389 -ExportPath C:\Reports\connectivity.csv
```

### `Get-CriticalEvents.ps1`
Pulls recent Critical/Error events from System and Application logs and
groups them by recurring Event ID, so you can see patterns instead of
scrolling Event Viewer.

```powershell
.\Get-CriticalEvents.ps1 -ComputerName STORE07-POS03 -Hours 72
```

### `Invoke-RemoteTriage.ps1`
Runs health check + connectivity test + recent event log pull against one or
more machines and compiles everything into a single HTML report. This is the
"ticket just came in" one-liner.

```powershell
.\Invoke-RemoteTriage.ps1 -ComputerName STORE14-POS02 -OutputPath C:\Reports\store14.html
```

## Notes
- All scripts default sensibly to the local machine when no `-ComputerName`
  is given, so they double as quick local diagnostics.
- Scripts that write/delete (`Clear-DiskSpace.ps1`) support `-WhatIf` and
  `-Verbose` via `CmdletBinding(SupportsShouldProcess)`.
- Nothing here requires the Active Directory module — everything works
  against workgroup or domain machines via CIM/WinRM.
- Adjust `$Ports`, `$Hours`, and log names as needed for your environment.
