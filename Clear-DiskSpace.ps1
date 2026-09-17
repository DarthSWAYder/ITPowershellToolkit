<#
.SYNOPSIS
    Clears common temp/cache locations to free disk space.

.DESCRIPTION
    Targets Windows Temp, user Temp folders, Windows Update cache,
    browser caches, and the Recycle Bin. Reports space freed. Safe by
    default (skips files in use); use -WhatIf to preview without deleting.

.PARAMETER IncludeWindowsUpdateCache
    Also clears SoftwareDistribution\Download (safe; Windows Update rebuilds it).

.PARAMETER WhatIf
    Preview what would be deleted without deleting anything.

.EXAMPLE
    .\Clear-DiskSpace.ps1 -WhatIf

.EXAMPLE
    .\Clear-DiskSpace.ps1 -IncludeWindowsUpdateCache
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludeWindowsUpdateCache
)

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
}

$targets = @(
    "$env:WINDIR\Temp",
    "$env:TEMP",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
)

if ($IncludeWindowsUpdateCache) {
    $targets += "$env:WINDIR\SoftwareDistribution\Download"
}

$totalFreedBytes = 0

foreach ($path in $targets) {
    if (-not (Test-Path $path)) {
        Write-Verbose "Skipping (not found): $path"
        continue
    }

    $before = Get-FolderSize -Path $path
    Write-Host "Cleaning: $path" -ForegroundColor Cyan

    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete')) {
                Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

    $after = Get-FolderSize -Path $path
    $freed = $before - $after
    $totalFreedBytes += $freed
    Write-Host ("  Freed: {0:N1} MB" -f ($freed / 1MB))
}

# Empty Recycle Bin
if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Empty')) {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "Recycle Bin emptied." -ForegroundColor Cyan
    } catch {
        Write-Verbose "Recycle Bin already empty or inaccessible."
    }
}

Write-Host ""
Write-Host ("Total space freed: {0:N2} GB" -f ($totalFreedBytes / 1GB)) -ForegroundColor Green
