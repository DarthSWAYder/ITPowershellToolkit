<#
.SYNOPSIS
    GUI launcher for the PowerShell IT Automation Toolkit.

.DESCRIPTION
    A simple Windows Forms front-end so you can run any toolkit script,
    fill in parameters, and see output without touching the console.
    Scripts run in a background runspace so the window doesn't freeze
    while a check is in progress.

.EXAMPLE
    .\Toolkit-GUI.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- Form setup ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "IT Automation Toolkit"
$form.Size = New-Object System.Drawing.Size(760, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font("Segoe UI", 9)
$monoFont = New-Object System.Drawing.Font("Consolas", 9)

# ---------- Script selector ----------
$lblScript = New-Object System.Windows.Forms.Label
$lblScript.Text = "Script:"
$lblScript.Location = New-Object System.Drawing.Point(15, 15)
$lblScript.Size = New-Object System.Drawing.Size(80, 20)
$lblScript.Font = $font

$cmbScript = New-Object System.Windows.Forms.ComboBox
$cmbScript.Location = New-Object System.Drawing.Point(100, 12)
$cmbScript.Size = New-Object System.Drawing.Size(320, 24)
$cmbScript.DropDownStyle = "DropDownList"
$cmbScript.Font = $font
$cmbScript.Items.AddRange(@(
    "System Health Report",
    "Software Inventory",
    "Disk Cleanup (preview - WhatIf)",
    "Disk Cleanup (run for real)",
    "Connectivity Test",
    "Critical Events",
    "Full Triage Report (HTML)"
))
$cmbScript.SelectedIndex = 0

# ---------- Computer name input ----------
$lblComputer = New-Object System.Windows.Forms.Label
$lblComputer.Text = "Computer(s):"
$lblComputer.Location = New-Object System.Drawing.Point(15, 50)
$lblComputer.Size = New-Object System.Drawing.Size(80, 20)
$lblComputer.Font = $font

$txtComputer = New-Object System.Windows.Forms.TextBox
$txtComputer.Location = New-Object System.Drawing.Point(100, 47)
$txtComputer.Size = New-Object System.Drawing.Size(320, 24)
$txtComputer.Font = $font
$txtComputer.Text = $env:COMPUTERNAME

# ---------- Hours input (for events) ----------
$lblHours = New-Object System.Windows.Forms.Label
$lblHours.Text = "Hours back:"
$lblHours.Location = New-Object System.Drawing.Point(440, 50)
$lblHours.Size = New-Object System.Drawing.Size(75, 20)
$lblHours.Font = $font

$numHours = New-Object System.Windows.Forms.NumericUpDown
$numHours.Location = New-Object System.Drawing.Point(520, 47)
$numHours.Size = New-Object System.Drawing.Size(80, 24)
$numHours.Minimum = 1
$numHours.Maximum = 8760
$numHours.Value = 48
$numHours.Font = $font

# ---------- Run / Export buttons ----------
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run"
$btnRun.Location = New-Object System.Drawing.Point(440, 12)
$btnRun.Size = New-Object System.Drawing.Size(90, 26)
$btnRun.Font = $font
$btnRun.BackColor = [System.Drawing.Color]::FromArgb(42, 92, 138)
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = "Flat"

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export Output..."
$btnExport.Location = New-Object System.Drawing.Point(620, 12)
$btnExport.Size = New-Object System.Drawing.Size(110, 26)
$btnExport.Font = $font

# ---------- Status label ----------
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready."
$lblStatus.Location = New-Object System.Drawing.Point(15, 82)
$lblStatus.Size = New-Object System.Drawing.Size(715, 20)
$lblStatus.Font = $font
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(42, 92, 138)

# ---------- Output box ----------
$txtOutput = New-Object System.Windows.Forms.RichTextBox
$txtOutput.Location = New-Object System.Drawing.Point(15, 108)
$txtOutput.Size = New-Object System.Drawing.Size(715, 460)
$txtOutput.Font = $monoFont
$txtOutput.ReadOnly = $true
$txtOutput.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$txtOutput.WordWrap = $false
$txtOutput.ScrollBars = "Both"

$form.Controls.AddRange(@($lblScript, $cmbScript, $lblComputer, $txtComputer, $lblHours, $numHours, $btnRun, $btnExport, $lblStatus, $txtOutput))

# ---------- Runspace-based execution so the UI doesn't freeze ----------
$script:ps = $null
$script:handle = $null
$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 300

$timerTick = {
    if ($script:handle -and $script:handle.IsCompleted) {
        $script:timer.Stop()
        try {
            $output = $script:ps.EndInvoke($script:handle)
            $errors = $script:ps.Streams.Error

            $txtOutput.Clear()
            if ($output) {
                $txtOutput.AppendText(($output | Out-String))
            }
            if ($errors.Count -gt 0) {
                $txtOutput.AppendText("`r`n--- Errors ---`r`n")
                foreach ($e in $errors) { $txtOutput.AppendText("$e`r`n") }
            }
            if (-not $output -and $errors.Count -eq 0) {
                $txtOutput.AppendText("(No output.)")
            }
        } catch {
            $txtOutput.AppendText("Execution failed: $($_.Exception.Message)")
        } finally {
            $script:ps.Dispose()
            $btnRun.Enabled = $true
            $lblStatus.Text = "Done."
        }
    }
}
$script:timer.Add_Tick($timerTick)

$btnRun.Add_Click({
    $btnRun.Enabled = $false
    $txtOutput.Clear()
    $lblStatus.Text = "Running..."
    [System.Windows.Forms.Application]::DoEvents()

    $computers = $txtComputer.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if (-not $computers) { $computers = @($env:COMPUTERNAME) }
    $hours = [int]$numHours.Value

    $scriptPath = switch ($cmbScript.SelectedItem) {
        "System Health Report"              { Join-Path $scriptDir "Get-SystemHealthReport.ps1" }
        "Software Inventory"                { Join-Path $scriptDir "Get-SoftwareInventory.ps1" }
        "Disk Cleanup (preview - WhatIf)"   { Join-Path $scriptDir "Clear-DiskSpace.ps1" }
        "Disk Cleanup (run for real)"       { Join-Path $scriptDir "Clear-DiskSpace.ps1" }
        "Connectivity Test"                 { Join-Path $scriptDir "Test-StoreConnectivity.ps1" }
        "Critical Events"                   { Join-Path $scriptDir "Get-CriticalEvents.ps1" }
        "Full Triage Report (HTML)"         { Join-Path $scriptDir "Invoke-RemoteTriage.ps1" }
    }

    $script:ps = [PowerShell]::Create()

    switch ($cmbScript.SelectedItem) {
        "System Health Report" {
            [void]$script:ps.AddScript('param($p,$c) & $p -ComputerName $c').AddArgument($scriptPath).AddArgument($computers)
        }
        "Software Inventory" {
            [void]$script:ps.AddScript('param($p,$c) & $p -ComputerName $c').AddArgument($scriptPath).AddArgument($computers)
        }
        "Disk Cleanup (preview - WhatIf)" {
            [void]$script:ps.AddScript('param($p) & $p -WhatIf').AddArgument($scriptPath)
        }
        "Disk Cleanup (run for real)" {
            [void]$script:ps.AddScript('param($p) & $p').AddArgument($scriptPath)
        }
        "Connectivity Test" {
            [void]$script:ps.AddScript('param($p,$c) & $p -TargetList $c -Ports 445,3389').AddArgument($scriptPath).AddArgument($computers)
        }
        "Critical Events" {
            [void]$script:ps.AddScript('param($p,$c,$h) & $p -ComputerName $c[0] -Hours $h').AddArgument($scriptPath).AddArgument($computers).AddArgument($hours)
        }
        "Full Triage Report (HTML)" {
            $outFile = Join-Path $env:TEMP "triage-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
            [void]$script:ps.AddScript('param($p,$c,$o) & $p -ComputerName $c -OutputPath $o; Start-Process $o').AddArgument($scriptPath).AddArgument($computers).AddArgument($outFile)
        }
    }

    $script:handle = $script:ps.BeginInvoke()
    $script:timer.Start()
})

$btnExport.Add_Click({
    if (-not $txtOutput.Text) {
        [System.Windows.Forms.MessageBox]::Show("Nothing to export yet - run a script first.", "Export Output")
        return
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "Text file (*.txt)|*.txt|All files (*.*)|*.*"
    $dlg.FileName = "toolkit-output-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutput.Text | Out-File -FilePath $dlg.FileName -Encoding utf8
        [System.Windows.Forms.MessageBox]::Show("Saved to $($dlg.FileName)", "Export Output")
    }
})

[void]$form.ShowDialog()


