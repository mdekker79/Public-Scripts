#Requires -Version 7.0
<#
.SYNOPSIS
    GUI user finder with fuzzy fallback chain, parallel search, and confirmation grid.

.DESCRIPTION
    Searches Entra / on-prem AD for a list of names using a progressive fallback chain:
      1. Full name exact
      2. Last name
      3. First name
      4. First 4 chars of last name
      5. First 4 chars of first name

    Results appear in a grid — pre-checked on confident matches, unchecked on fuzzy/partial.
    Confirm the selection to export CSV or add directly to a distribution group.

.PARAMETER DistributionGroup
    If provided, "Confirm Selected" will call Add-DistributionGroupMember directly.

.PARAMETER SkipEntra
    Skip Entra / Microsoft Graph search.

.PARAMETER SkipAD
    Skip on-prem Active Directory search.

.EXAMPLE
    .\Find-UsersUI.ps1
    .\Find-UsersUI.ps1 -DistributionGroup "IDG-DFW"
#>
param(
    [string]$DistributionGroup = "",
    [string]$Organization = "",
    [ValidateSet("Name","Email","Both")]
    [string]$SearchBy = "Both",
    [switch]$SkipEntra,
    [switch]$SkipAD
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#region ── Shared sync state (thread-safe) ────────────────────────────────────
$script:sync = [hashtable]::Synchronized(@{
    Progress = 0
    Total    = 0
    Results  = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()
    Done     = $false
})
#endregion

#region ── Pre-connect (before form launches to avoid MSAL/WinForms conflict) ─
# Graph / Entra
if (-not $SkipEntra) {
    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        try {
            Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
        } catch {
            Write-Error "Could not connect to Microsoft Graph: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Graph: already connected as $((Get-MgContext).Account)" -ForegroundColor Green
    }
}

# Exchange Online (only needed if adding to a DL)
if ($DistributionGroup) {
    if (-not (Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
        Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
        $connectParams = @{ ShowBanner = $false; ErrorAction = "Stop"; Device = $true }
        if ($Organization) { $connectParams.Organization = $Organization }
        try {
            Connect-ExchangeOnline @connectParams
        } catch {
            Write-Error "Could not connect to Exchange Online: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Exchange Online: already connected as $((Get-ConnectionInformation).UserPrincipalName)" -ForegroundColor Green
    }
}
#endregion

#region ── Build UI ───────────────────────────────────────────────────────────
$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "User Finder"
$form.Size             = New-Object System.Drawing.Size(760, 660)
$form.StartPosition    = "CenterScreen"
$form.FormBorderStyle  = "Sizable"
$form.MinimumSize      = New-Object System.Drawing.Size(600, 580)

# ── Input area ──
$lblInput          = New-Object System.Windows.Forms.Label
$lblInput.Text     = "Paste names (one per line):"
$lblInput.Location = New-Object System.Drawing.Point(10, 10)
$lblInput.Size     = New-Object System.Drawing.Size(240, 20)
$form.Controls.Add($lblInput)

$txtInput             = New-Object System.Windows.Forms.TextBox
$txtInput.Multiline   = $true
$txtInput.ScrollBars  = "Vertical"
$txtInput.Location    = New-Object System.Drawing.Point(10, 32)
$txtInput.Size        = New-Object System.Drawing.Size(720, 150)
$txtInput.Font        = New-Object System.Drawing.Font("Consolas", 9)
$txtInput.Anchor      = "Top,Left,Right"
$form.Controls.Add($txtInput)

# ── File load ──
$btnFile          = New-Object System.Windows.Forms.Button
$btnFile.Text     = "Load from File..."
$btnFile.Location = New-Object System.Drawing.Point(10, 192)
$btnFile.Size     = New-Object System.Drawing.Size(130, 28)
$form.Controls.Add($btnFile)

$lblFile           = New-Object System.Windows.Forms.Label
$lblFile.Text      = ""
$lblFile.ForeColor = [System.Drawing.Color]::Gray
$lblFile.Location  = New-Object System.Drawing.Point(150, 198)
$lblFile.Size      = New-Object System.Drawing.Size(580, 20)
$form.Controls.Add($lblFile)

# ── Source toggles ──
$chkEntra          = New-Object System.Windows.Forms.CheckBox
$chkEntra.Text     = "Entra / M365"
$chkEntra.Checked  = (-not $SkipEntra)
$chkEntra.Location = New-Object System.Drawing.Point(10, 232)
$chkEntra.Size     = New-Object System.Drawing.Size(120, 22)
$form.Controls.Add($chkEntra)

$chkAD             = New-Object System.Windows.Forms.CheckBox
$chkAD.Text        = "On-prem AD"
$chkAD.Checked     = (-not $SkipAD)
$chkAD.Location    = New-Object System.Drawing.Point(140, 232)
$chkAD.Size        = New-Object System.Drawing.Size(120, 22)
$form.Controls.Add($chkAD)

# ── Search button + progress ──
$btnSearch            = New-Object System.Windows.Forms.Button
$btnSearch.Text       = "Search"
$btnSearch.Location   = New-Object System.Drawing.Point(10, 262)
$btnSearch.Size       = New-Object System.Drawing.Size(90, 30)
$btnSearch.BackColor  = [System.Drawing.Color]::SteelBlue
$btnSearch.ForeColor  = [System.Drawing.Color]::White
$btnSearch.FlatStyle  = "Flat"
$form.Controls.Add($btnSearch)

$progressBar          = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(110, 265)
$progressBar.Size     = New-Object System.Drawing.Size(500, 24)
$progressBar.Minimum  = 0
$progressBar.Value    = 0
$form.Controls.Add($progressBar)

$lblStatus            = New-Object System.Windows.Forms.Label
$lblStatus.Text       = ""
$lblStatus.Location   = New-Object System.Drawing.Point(620, 268)
$lblStatus.Size       = New-Object System.Drawing.Size(120, 20)
$lblStatus.ForeColor  = [System.Drawing.Color]::DarkBlue
$form.Controls.Add($lblStatus)

# ── Results grid ──
$grid                          = New-Object System.Windows.Forms.DataGridView
$grid.Location                 = New-Object System.Drawing.Point(10, 302)
$grid.Size                     = New-Object System.Drawing.Size(720, 270)
$grid.Anchor                   = "Top,Left,Right,Bottom"
$grid.ReadOnly                 = $false
$grid.AllowUserToAddRows       = $false
$grid.RowHeadersVisible        = $false
$grid.SelectionMode            = "FullRowSelect"
$grid.AutoSizeColumnsMode      = "Fill"
$grid.BackgroundColor          = [System.Drawing.Color]::White
$grid.DefaultCellStyle.Font    = New-Object System.Drawing.Font("Segoe UI", 9)

$colCheck              = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheck.HeaderText   = "Include"
$colCheck.Width        = 58
$colCheck.FillWeight   = 1
$colCheck.ReadOnly     = $false
$grid.Columns.Add($colCheck) | Out-Null

foreach ($h in @("Input Name","Matched Name","Email","Source","Confidence")) {
    $c              = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.HeaderText   = $h
    $c.ReadOnly     = $true
    $grid.Columns.Add($c) | Out-Null
}
$form.Controls.Add($grid)

# ── Bottom buttons ──
$btnConfirm           = New-Object System.Windows.Forms.Button
$btnConfirm.Text      = if ($DistributionGroup) { "Add to $DistributionGroup" } else { "Confirm Selected" }
$btnConfirm.Location  = New-Object System.Drawing.Point(10, 582)
$btnConfirm.Size      = New-Object System.Drawing.Size(160, 32)
$btnConfirm.Enabled   = $false
$btnConfirm.Anchor    = "Bottom,Left"
$form.Controls.Add($btnConfirm)

$btnExport            = New-Object System.Windows.Forms.Button
$btnExport.Text       = "Export CSV"
$btnExport.Location   = New-Object System.Drawing.Point(180, 582)
$btnExport.Size       = New-Object System.Drawing.Size(100, 32)
$btnExport.Enabled    = $false
$btnExport.Anchor     = "Bottom,Left"
$form.Controls.Add($btnExport)

$btnSelectAll         = New-Object System.Windows.Forms.Button
$btnSelectAll.Text    = "Select All"
$btnSelectAll.Location = New-Object System.Drawing.Point(290, 582)
$btnSelectAll.Size    = New-Object System.Drawing.Size(90, 32)
$btnSelectAll.Enabled = $false
$btnSelectAll.Anchor  = "Bottom,Left"
$form.Controls.Add($btnSelectAll)

$btnClearAll          = New-Object System.Windows.Forms.Button
$btnClearAll.Text     = "Clear All"
$btnClearAll.Location = New-Object System.Drawing.Point(390, 582)
$btnClearAll.Size     = New-Object System.Drawing.Size(90, 32)
$btnClearAll.Enabled  = $false
$btnClearAll.Anchor   = "Bottom,Left"
$form.Controls.Add($btnClearAll)

$lblResult            = New-Object System.Windows.Forms.Label
$lblResult.Text       = ""
$lblResult.Location   = New-Object System.Drawing.Point(490, 590)
$lblResult.Size       = New-Object System.Drawing.Size(260, 20)
$lblResult.ForeColor  = [System.Drawing.Color]::DarkGreen
$lblResult.Anchor     = "Bottom,Left"
$form.Controls.Add($lblResult)
#endregion

#region ── Helpers ────────────────────────────────────────────────────────────
function Get-RowColor([string]$confidence) {
    switch ($confidence) {
        "Exact"        { return [System.Drawing.Color]::FromArgb(220, 255, 220) }  # green
        "LastName"     { return [System.Drawing.Color]::FromArgb(255, 255, 210) }  # yellow
        "FirstName"    { return [System.Drawing.Color]::FromArgb(255, 255, 210) }  # yellow
        "PartialLast"  { return [System.Drawing.Color]::FromArgb(255, 230, 190) }  # orange
        "PartialFirst" { return [System.Drawing.Color]::FromArgb(255, 230, 190) }  # orange
        "NoMatch"      { return [System.Drawing.Color]::FromArgb(255, 210, 210) }  # red
        default        { return [System.Drawing.Color]::White }
    }
}

function Populate-Grid($results) {
    $grid.SuspendLayout()
    $grid.Rows.Clear()

    foreach ($r in ($results | Sort-Object InputName)) {
        if ($r.Matches.Count -eq 0) {
            $idx = $grid.Rows.Add($false, $r.InputName, "(no match found)", "", "", "NoMatch")
            $grid.Rows[$idx].DefaultCellStyle.BackColor = Get-RowColor "NoMatch"
            $grid.Rows[$idx].Cells[0].ReadOnly = $true
        }
        else {
            foreach ($m in $r.Matches) {
                # Pre-check only on high-confidence matches
                $include = $r.Confidence -in @("Exact", "LastName")
                $idx = $grid.Rows.Add($include, $r.InputName, $m.DisplayName, $m.Email, $m.Source, $r.Confidence)
                $grid.Rows[$idx].DefaultCellStyle.BackColor = Get-RowColor $r.Confidence
            }
        }
    }

    $grid.ResumeLayout()
    $btnConfirm.Enabled  = $true
    $btnExport.Enabled   = $true
    $btnSelectAll.Enabled = $true
    $btnClearAll.Enabled  = $true

    $matched  = ($results | Where-Object { $_.Matches.Count -gt 0 }).Count
    $total    = $results.Count
    $lblStatus.Text = "Done. $matched / $total matched."
}
#endregion

#region ── Event handlers ─────────────────────────────────────────────────────
$btnFile.Add_Click({
    $ofd        = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Text / CSV (*.txt;*.csv)|*.txt;*.csv|All files|*.*"
    if ($ofd.ShowDialog() -eq "OK") {
        $lines = Get-Content $ofd.FileName | Where-Object { $_.Trim() }
        $txtInput.Text     = $lines -join "`r`n"
        $lblFile.Text      = "$($lines.Count) names loaded from: $([System.IO.Path]::GetFileName($ofd.FileName))"
        $lblFile.ForeColor = [System.Drawing.Color]::DarkGreen
    }
})

$btnSelectAll.Add_Click({
    $grid.EndEdit()
    foreach ($row in $grid.Rows) {
        if (-not $row.Cells[0].ReadOnly) {
            $row.Cells[0].Value = $true
            $grid.UpdateCellValue($row.Cells[0].ColumnIndex, $row.Index)
        }
    }
    $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    $grid.Invalidate()
})

$btnClearAll.Add_Click({
    $grid.EndEdit()
    foreach ($row in $grid.Rows) {
        if (-not $row.Cells[0].ReadOnly) {
            $row.Cells[0].Value = $false
            $grid.UpdateCellValue($row.Cells[0].ColumnIndex, $row.Index)
        }
    }
    $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    $grid.Invalidate()
})

# ── Poll timer — updates progress bar from background thread ──
$searchTimer          = New-Object System.Windows.Forms.Timer
$searchTimer.Interval = 200
$searchTimer.Add_Tick({
    if ($script:sync.Total -gt 0) {
        $pct = [Math]::Min($script:sync.Progress, $progressBar.Maximum)
        $progressBar.Value = $pct
        $lblStatus.Text    = "$($script:sync.Progress) / $($script:sync.Total)"
    }
    if ($script:sync.Done) {
        $searchTimer.Stop()
        $btnSearch.Enabled = $true
        Populate-Grid $script:sync.Results
    }
})

# ── Search ──
$btnSearch.Add_Click({
    $script:terms = $txtInput.Text -split "`n" |
                    ForEach-Object { $_.Trim() } |
                    Where-Object   { $_ -ne "" }

    if (-not $script:terms) {
        [System.Windows.Forms.MessageBox]::Show("No names entered.", "User Finder") | Out-Null
        return
    }

    # Reset state
    $grid.Rows.Clear()
    $btnConfirm.Enabled   = $false
    $btnExport.Enabled    = $false
    $btnSelectAll.Enabled = $false
    $btnClearAll.Enabled  = $false
    $btnSearch.Enabled    = $false
    $lblResult.Text       = ""

    $script:sync.Progress = 0
    $script:sync.Total    = $script:terms.Count
    $script:sync.Done     = $false
    $script:sync.Results  = [System.Collections.Concurrent.ConcurrentBag[psobject]]::new()

    $progressBar.Maximum = $script:terms.Count
    $progressBar.Value   = 0
    $lblStatus.Text      = "Connecting..."

    $script:useEntra  = $chkEntra.Checked
    $script:useAD     = $chkAD.Checked
    $script:searchBy  = $SearchBy

    # Connect before spawning threads
    if ($script:useEntra) {
        try {
            if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
                Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Graph connection failed: $($_.Exception.Message)") | Out-Null
            $btnSearch.Enabled = $true
            return
        }
    }

    $lblStatus.Text = "Searching..."

    # ── Parallel search in background thread ──────────────────────────────────
    # ThreadJob shares process memory — the $script:sync hashtable reference is
    # passed by reference (not serialized), so progress updates are live.
    # Graph module in PS7 re-uses the process-level MSAL token cache across
    # runspaces, so no re-auth is needed inside the parallel blocks.
    $null = Start-ThreadJob -Name "UserFinderSearch" -ScriptBlock {
        $s        = $using:sync
        $names    = $using:terms
        $useEntra = $using:useEntra
        $useAD    = $using:useAD
        $searchBy = $using:searchBy

        $names | ForEach-Object -Parallel {
            $name     = $_
            $s        = $using:s
            $entra    = $using:useEntra
            $ad       = $using:useAD
            $by       = $using:searchBy

            if ($entra) { Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue }
            if ($ad)    { Import-Module ActiveDirectory       -ErrorAction SilentlyContinue }

            # Parse name into parts
            $parts = $name.Trim() -split '\s+', 2
            $first = $parts[0]
            $last  = if ($parts.Count -gt 1) { $parts[-1] } else { "" }

            # Build fallback tiers in order — Email mode uses the term as-is (no name parsing)
            $tiers = [ordered]@{}
            if ($by -eq "Email") {
                $tiers["Exact"] = $name.Trim()
            } else {
                $tiers["Exact"]        = $name.Trim()
                if ($last)                  { $tiers["LastName"]     = $last }
                if ($first)                 { $tiers["FirstName"]    = $first }
                if ($last.Length  -ge 3)    { $tiers["PartialLast"]  = $last.Substring(0,  [Math]::Min(4, $last.Length)) }
                if ($first.Length -ge 3)    { $tiers["PartialFirst"] = $first.Substring(0, [Math]::Min(4, $first.Length)) }
            }

            $resultObj = [pscustomobject]@{
                InputName  = $name
                Confidence = "NoMatch"
                Matches    = @()
            }

            foreach ($tier in $tiers.GetEnumerator()) {
                $term    = $tier.Value
                $confKey = $tier.Key
                $found   = [System.Collections.Generic.List[psobject]]::new()

                # ── Entra search ──
                if ($entra) {
                    try {
                        $filter = if ($by -eq "Email") {
                            "mail eq '$term' or userPrincipalName eq '$term'"
                        } else {
                            switch ($confKey) {
                                "Exact"        { "displayName eq '$term'" }
                                "LastName"     { "startsWith(surname,'$term')" }
                                "FirstName"    { "startsWith(givenName,'$term')" }
                                default        { "startsWith(displayName,'$term')" }
                            }
                        }
                        $users = Get-MgUser -Filter $filter `
                                            -Property DisplayName,UserPrincipalName,Mail,AccountEnabled `
                                            -All -ErrorAction Stop
                        foreach ($u in $users) {
                            $found.Add([pscustomobject]@{
                                Source      = "Entra"
                                DisplayName = $u.DisplayName
                                Email       = if ($u.Mail) { $u.Mail } else { $u.UserPrincipalName }
                                Enabled     = $u.AccountEnabled
                            })
                        }
                    } catch { }
                }

                # ── AD search (only if Entra found nothing) ──
                if ($ad -and $found.Count -eq 0) {
                    try {
                        $adFilter = if ($by -eq "Email") {
                            "EmailAddress -eq '$term'"
                        } else {
                            switch ($confKey) {
                                "Exact"        { "DisplayName -eq '$term'" }
                                "LastName"     { "Surname -like '$term*'" }
                                "FirstName"    { "GivenName -like '$term*'" }
                                default        { "DisplayName -like '$term*'" }
                            }
                        }
                        $adUsers = Get-ADUser -Filter $adFilter `
                                              -Properties DisplayName,EmailAddress,Enabled `
                                              -ErrorAction Stop
                        foreach ($u in $adUsers) {
                            $found.Add([pscustomobject]@{
                                Source      = "AD"
                                DisplayName = $u.DisplayName
                                Email       = $u.EmailAddress
                                Enabled     = $u.Enabled
                            })
                        }
                    } catch { }
                }

                if ($found.Count -gt 0) {
                    $resultObj.Confidence = $confKey
                    $resultObj.Matches    = $found.ToArray()
                    break  # Stop at first tier that returns results
                }
            }

            $s.Results.Add($resultObj)
            $s.Progress = $s.Progress + 1  # synchronized hashtable handles thread safety

        } -ThrottleLimit 10

        $s.Done = $true

    } -StreamingHost $Host

    $searchTimer.Start()
})

# ── Confirm / Add to DL ──
$btnConfirm.Add_Click({
    $confirmed = @()
    foreach ($row in $grid.Rows) {
        if ($row.Cells[0].Value -eq $true -and $row.Cells[2].Value -ne "(no match found)") {
            $confirmed += [pscustomobject]@{
                InputName   = $row.Cells[1].Value
                DisplayName = $row.Cells[2].Value
                Email       = $row.Cells[3].Value
                Source      = $row.Cells[4].Value
                Confidence  = $row.Cells[5].Value
            }
        }
    }

    if (-not $confirmed) {
        [System.Windows.Forms.MessageBox]::Show("No rows checked.", "User Finder") | Out-Null
        return
    }

    if ($DistributionGroup) {
        $msg = "Add $($confirmed.Count) user(s) to '$DistributionGroup'?"
        if ([System.Windows.Forms.MessageBox]::Show($msg, "Confirm", "YesNo", "Question") -eq "Yes") {

            $added = 0; $skipped = 0; $failed = 0
            foreach ($u in $confirmed) {
                if (-not $u.Email) { $skipped++; continue }
                try {
                    Add-DistributionGroupMember -Identity $DistributionGroup -Member $u.Email -ErrorAction Stop
                    $added++
                } catch {
                    if ($_.Exception.Message -like "*already a member*") { $skipped++ }
                    else {
                        $failed++
                        Write-Warning "Failed to add $($u.Email): $($_.Exception.Message)"
                    }
                }
            }
            $lblResult.ForeColor = if ($failed -gt 0) { [System.Drawing.Color]::Red } else { [System.Drawing.Color]::DarkGreen }
            $lblResult.Text = "Added: $added  |  Skipped: $skipped  |  Failed: $failed"
        }
    }
    else {
        # No DL specified — offer CSV save
        $sfd            = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter     = "CSV (*.csv)|*.csv"
        $sfd.FileName   = "ConfirmedUsers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        if ($sfd.ShowDialog() -eq "OK") {
            $confirmed | Export-Csv $sfd.FileName -NoTypeInformation
            $lblResult.ForeColor = [System.Drawing.Color]::DarkGreen
            $lblResult.Text = "Saved $($confirmed.Count) users to $([System.IO.Path]::GetFileName($sfd.FileName))"
        }
    }
})

# ── Export all rows ──
$btnExport.Add_Click({
    $all = @()
    foreach ($row in $grid.Rows) {
        $all += [pscustomobject]@{
            Include     = $row.Cells[0].Value
            InputName   = $row.Cells[1].Value
            DisplayName = $row.Cells[2].Value
            Email       = $row.Cells[3].Value
            Source      = $row.Cells[4].Value
            Confidence  = $row.Cells[5].Value
        }
    }
    $sfd          = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter   = "CSV (*.csv)|*.csv"
    $sfd.FileName = "UserSearch_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    if ($sfd.ShowDialog() -eq "OK") {
        $all | Export-Csv $sfd.FileName -NoTypeInformation
        $lblResult.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblResult.Text = "Exported $($all.Count) rows."
    }
})
#endregion

$form.ShowDialog() | Out-Null
