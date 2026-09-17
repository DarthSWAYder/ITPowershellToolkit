<#
.SYNOPSIS
    Inventories installed software on local or remote machines.

.DESCRIPTION
    Reads both the 32-bit and 64-bit uninstall registry keys (more reliable
    and much faster than Win32_Product, which triggers a repair scan on
    every MSI install and can hang a machine). Useful for auditing store
    machines for outdated or unauthorized software.

.PARAMETER ComputerName
    One or more computer names. Defaults to local machine.

.PARAMETER NameFilter
    Optional wildcard filter on software name, e.g. "*Java*".

.PARAMETER ExportPath
    Optional CSV export path.

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -NameFilter "*Java*" -ExportPath C:\Reports\java_audit.csv

.EXAMPLE
    "STORE01-POS01","STORE01-POS02" | .\Get-SoftwareInventory.ps1
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [string]$NameFilter = '*',

    [string]$ExportPath
)

begin {
    $regPaths = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $results = [System.Collections.Generic.List[object]]::new()
}

process {
    foreach ($computer in $ComputerName) {
        Write-Verbose "Scanning $computer..."
        try {
            $scriptBlock = {
                param($paths, $filter)
                foreach ($p in $paths) {
                    Get-ItemProperty -Path "HKLM:\$p" -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -like $filter } |
                        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
                }
            }

            if ($computer -eq $env:COMPUTERNAME) {
                $software = & $scriptBlock $regPaths $NameFilter
            } else {
                $software = Invoke-Command -ComputerName $computer -ScriptBlock $scriptBlock -ArgumentList $regPaths, $NameFilter -ErrorAction Stop
            }

            foreach ($app in $software) {
                if ([string]::IsNullOrWhiteSpace($app.DisplayName)) { continue }
                $results.Add([PSCustomObject]@{
                    ComputerName = $computer
                    Name         = $app.DisplayName
                    Version      = $app.DisplayVersion
                    Publisher    = $app.Publisher
                    InstallDate  = $app.InstallDate
                })
            }
        }
        catch {
            Write-Warning "Failed to query $computer : $($_.Exception.Message)"
        }
    }
}

end {
    $sorted = $results | Sort-Object ComputerName, Name
    if ($ExportPath) {
        $sorted | Export-Csv -Path $ExportPath -NoTypeInformation
        Write-Host "Inventory exported to $ExportPath ($($sorted.Count) entries)" -ForegroundColor Green
    }
    $sorted | Format-Table -AutoSize
}
