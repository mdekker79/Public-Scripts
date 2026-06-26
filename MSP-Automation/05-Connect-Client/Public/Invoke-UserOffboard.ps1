function Invoke-UserOffboard {
    <#
    .SYNOPSIS
        Offboards a user from a client M365 tenant.
    .DESCRIPTION
        Requires Connect-Client to have been run first (Exchange + Graph connected).
        Steps performed:
          1. Revoke all sign-in sessions
          2. Block sign-in
          3. Reset password to random value
          4. Convert mailbox to Shared
          5. Remove all licenses
          6. Remove from all groups
          7. Grant delegated access (FullAccess + SendAs) to shared mailbox
    .EXAMPLE
        Connect-Client          # connect to the tenant first
        Invoke-UserOffboard     # then run offboarding
    #>
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # -------------------------------------------------------
    # HELPER — small WinForms search picker
    # -------------------------------------------------------
    function Show-UserPicker {
        param(
            [string]$Title,
            [string]$Prompt = "Search by name or UPN:"
        )

        $f = New-Object System.Windows.Forms.Form
        $f.Text            = $Title
        $f.Size            = New-Object System.Drawing.Size(480, 420)
        $f.StartPosition   = "CenterScreen"
        $f.FormBorderStyle = "FixedDialog"
        $f.MaximizeBox     = $false
        $f.TopMost         = $true

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text     = $Prompt
        $lbl.Location = New-Object System.Drawing.Point(12, 12)
        $lbl.Size     = New-Object System.Drawing.Size(440, 20)
        $f.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point(12, 36)
        $txt.Size     = New-Object System.Drawing.Size(340, 22)
        $f.Controls.Add($txt)

        $btnSearch = New-Object System.Windows.Forms.Button
        $btnSearch.Text     = "Search"
        $btnSearch.Location = New-Object System.Drawing.Point(360, 34)
        $btnSearch.Size     = New-Object System.Drawing.Size(90, 26)
        $f.Controls.Add($btnSearch)

        $list = New-Object System.Windows.Forms.ListBox
        $list.Location      = New-Object System.Drawing.Point(12, 70)
        $list.Size          = New-Object System.Drawing.Size(438, 270)
        $list.Font          = New-Object System.Drawing.Font("Segoe UI", 10)
        $list.DisplayMember = "DisplayLabel"
        $f.Controls.Add($list)

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text      = "Select"
        $btnOK.Location  = New-Object System.Drawing.Point(12, 350)
        $btnOK.Size      = New-Object System.Drawing.Size(200, 32)
        $btnOK.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
        $btnOK.ForeColor = [System.Drawing.Color]::White
        $btnOK.FlatStyle = "Flat"
        $btnOK.Enabled   = $false
        $f.Controls.Add($btnOK)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text     = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(250, 350)
        $btnCancel.Size     = New-Object System.Drawing.Size(200, 32)
        $f.Controls.Add($btnCancel)

        $userResults = @()

        $doSearch = {
            $query = $txt.Text.Trim()
            if (-not $query) { return }
            $list.Items.Clear()
            $btnOK.Enabled = $false
            try {
                $uri = "https://graph.microsoft.com/v1.0/users?`$filter=startswith(displayName,'$query') or startswith(userPrincipalName,'$query')&`$select=id,displayName,userPrincipalName,accountEnabled&`$top=20"
                $response = Invoke-MgGraphRequest -Method GET -Uri $uri
                $script:userResults = $response.value
                foreach ($u in $script:userResults) {
                    $status = if ($u.accountEnabled) { "" } else { " [BLOCKED]" }
                    $item = [PSCustomObject]@{
                        DisplayLabel = "$($u.displayName)$status — $($u.userPrincipalName)"
                        User         = $u
                    }
                    $list.Items.Add($item) | Out-Null
                }
                if ($list.Items.Count -eq 0) {
                    $list.Items.Add([PSCustomObject]@{ DisplayLabel = "(no results)"; User = $null }) | Out-Null
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Search failed: $_", "Error") | Out-Null
            }
        }

        $btnSearch.Add_Click($doSearch)
        $txt.Add_KeyDown({
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { & $doSearch }
        })

        $list.Add_SelectedIndexChanged({
            $btnOK.Enabled = ($list.SelectedItem -ne $null -and $list.SelectedItem.User -ne $null)
        })
        $list.Add_DoubleClick({
            if ($list.SelectedItem -and $list.SelectedItem.User) {
                $f.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $f.Close()
            }
        })

        $btnOK.Add_Click({ $f.DialogResult = [System.Windows.Forms.DialogResult]::OK; $f.Close() })
        $btnCancel.Add_Click({ $f.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $f.Close() })
        $f.AcceptButton = $btnSearch

        $r = $f.ShowDialog()
        if ($r -ne [System.Windows.Forms.DialogResult]::OK -or -not $list.SelectedItem -or -not $list.SelectedItem.User) {
            return $null
        }
        return $list.SelectedItem.User
    }

    # -------------------------------------------------------
    # STEP 1 — Select user to offboard
    # -------------------------------------------------------
    $target = Show-UserPicker -Title "Invoke-UserOffboard — Select User to Offboard"
    if (-not $target) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    $userId = $target.id
    $upn    = $target.userPrincipalName
    $name   = $target.displayName

    Write-Host ""
    Write-Host "Offboarding: $name ($upn)" -ForegroundColor Cyan
    Write-Host ("-" * 50)

    # -------------------------------------------------------
    # STEP 2 — Confirm
    # -------------------------------------------------------
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Offboard the following user?`n`n$name`n$upn`n`nThis will revoke sessions, block sign-in, convert mailbox to Shared, and remove licenses.",
        "Confirm Offboard",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    # -------------------------------------------------------
    # STEP 3 — Revoke all sessions
    # -------------------------------------------------------
    Write-Host "[1/6] Revoking sign-in sessions..." -ForegroundColor Cyan
    try {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$userId/revokeSignInSessions" | Out-Null
        Write-Host "      Done." -ForegroundColor Green
    } catch {
        Write-Host "      Failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------
    # STEP 4 — Block sign-in
    # -------------------------------------------------------
    Write-Host "[2/6] Blocking sign-in..." -ForegroundColor Cyan
    try {
        Update-MgUser -UserId $userId -AccountEnabled:$false
        Write-Host "      Done." -ForegroundColor Green
    } catch {
        Write-Host "      Failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------
    # STEP 5 — Reset password to random value
    # -------------------------------------------------------
    Write-Host "[3/6] Resetting password..." -ForegroundColor Cyan
    try {
        $chars   = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%'
        $newPwd  = -join ((1..20) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
        $pwdProfile = @{
            Password                      = $newPwd
            ForceChangePasswordNextSignIn = $false
        }
        Update-MgUser -UserId $userId -PasswordProfile $pwdProfile
        Write-Host "      Done. (password not displayed)" -ForegroundColor Green
    } catch {
        Write-Host "      Failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------
    # STEP 6 — Convert mailbox to Shared
    # -------------------------------------------------------
    Write-Host "[4/6] Converting mailbox to Shared..." -ForegroundColor Cyan
    try {
        Set-Mailbox -Identity $upn -Type Shared
        Write-Host "      Done." -ForegroundColor Green
    } catch {
        Write-Host "      Failed (mailbox may not exist or Exchange not connected): $_" -ForegroundColor Red
    }

    # -------------------------------------------------------
    # STEP 7 — Remove all licenses
    # -------------------------------------------------------
    Write-Host "[5/6] Removing licenses..." -ForegroundColor Cyan
    try {
        $licenses = Get-MgUserLicenseDetail -UserId $userId
        if ($licenses) {
            $skuIds = $licenses | ForEach-Object { $_.SkuId }
            Set-MgUserLicense -UserId $userId -AddLicenses @() -RemoveLicenses $skuIds
            Write-Host "      Removed $($skuIds.Count) license(s)." -ForegroundColor Green
        } else {
            Write-Host "      No licenses assigned." -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "      Failed: $_" -ForegroundColor Red
    }

    # -------------------------------------------------------
    # STEP 8 — Remove from all groups
    # -------------------------------------------------------
    Write-Host "[6/6] Removing from groups..." -ForegroundColor Cyan
    try {
        $memberships = Get-MgUserMemberOf -UserId $userId -All
        $groups = $memberships | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
        $removed = 0
        foreach ($g in $groups) {
            try {
                Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $userId -ErrorAction Stop
                $removed++
            } catch {
                # Some groups (dynamic, role-assigned) can't be manually removed — skip silently
            }
        }
        Write-Host "      Removed from $removed of $($groups.Count) group(s)." -ForegroundColor Green
    } catch {
        Write-Host "      Failed: $_" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Offboard complete for $name." -ForegroundColor Green
    Write-Host ("-" * 50)

    # -------------------------------------------------------
    # STEP 9 — Delegate access to shared mailbox (loop)
    # -------------------------------------------------------
    $addDelegate = [System.Windows.Forms.MessageBox]::Show(
        "Grant delegated access to $name's shared mailbox?`n`n(FullAccess + SendAs)",
        "Delegated Access",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($addDelegate -eq [System.Windows.Forms.DialogResult]::Yes) {
        $delegatesAdded = @()

        while ($true) {
            $delegate = Show-UserPicker -Title "Select User — Grant Access to $name's Mailbox" -Prompt "Search for who should access the shared mailbox:"
            if (-not $delegate) { break }

            $delegateUpn = $delegate.userPrincipalName
            Write-Host "Granting access to $delegateUpn..." -ForegroundColor Cyan
            try {
                Add-MailboxPermission -Identity $upn -User $delegateUpn -AccessRights FullAccess -InheritanceType All -AutoMapping $true -ErrorAction Stop
                Write-Host "  FullAccess granted." -ForegroundColor Green
            } catch {
                Write-Host "  FullAccess failed: $_" -ForegroundColor Red
            }
            try {
                Add-RecipientPermission -Identity $upn -Trustee $delegateUpn -AccessRights SendAs -Confirm:$false -ErrorAction Stop
                Write-Host "  SendAs granted." -ForegroundColor Green
            } catch {
                Write-Host "  SendAs failed: $_" -ForegroundColor Red
            }
            $delegatesAdded += $delegateUpn

            $another = [System.Windows.Forms.MessageBox]::Show(
                "Access granted to $delegateUpn.`n`nAdd another person?",
                "Add Another?",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($another -ne [System.Windows.Forms.DialogResult]::Yes) { break }
        }

        if ($delegatesAdded.Count -eq 0) {
            Write-Host "Skipped delegate access." -ForegroundColor Yellow
        } else {
            Write-Host "Shared mailbox access granted to $($delegatesAdded.Count) user(s):" -ForegroundColor Green
            $delegatesAdded | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
        }
    }

    Write-Host ""
    Write-Host "Done. $name has been fully offboarded." -ForegroundColor Green
}
