function Get-UniqueEmail {
    <#
    .SYNOPSIS
        Generates a unique UPN/email for a new M365 user.
    .DESCRIPTION
        Tries progressively longer suffixes of the last name until a unique
        address is found. Falls back to a numeric suffix if the full name
        is already taken.

        Collision sequence for "John Smith":
          jsmith@contoso.com → jsmi → jsm → js → j →
          jsmith2@contoso.com → jsmith3@contoso.com ...
    #>
    param(
        [Parameter(Mandatory)] [string]$FirstName,
        [Parameter(Mandatory)] [string]$LastName,
        [Parameter(Mandatory)] [string]$Domain
    )

    $first = $FirstName.ToLower().Trim()
    $last  = $LastName.ToLower().Trim()

    for ($i = 1; $i -le $last.Length; $i++) {
        $candidate = "$first$($last.Substring(0, $i))@$Domain"
        $existing  = Get-MgUser -Filter "userPrincipalName eq '$candidate'" -ErrorAction SilentlyContinue
        if (-not $existing) { return $candidate }
        Write-Host "  '$candidate' taken, trying more letters..." -ForegroundColor Yellow
    }

    $n = 2
    do {
        $candidate = "$first$last$n@$Domain"
        $existing  = Get-MgUser -Filter "userPrincipalName eq '$candidate'" -ErrorAction SilentlyContinue
        $n++
    } while ($existing)

    return $candidate
}


function New-M365User {
    <#
    .SYNOPSIS
        Creates a new Microsoft 365 user, assigns a license, and adds them to groups.
    .DESCRIPTION
        Full M365 provisioning workflow via Microsoft Graph SDK:
          1. Generates a unique UPN using progressive last-name suffix algorithm
          2. Creates the account and waits for directory propagation (with retry)
          3. Assigns a license selected from the available pool
          4. Adds the user to selected groups — handles M365, Security,
             and Distribution group types differently
        Requires: Connect-MgGraph with User.ReadWrite.All, Group.ReadWrite.All,
                  Exchange Online connection for distribution groups.
    .PARAMETER UserInfo
        PSCustomObject with: FirstName, LastName, DisplayName, Phone, JobTitle,
        Department, Password, Domain.
    .OUTPUTS
        PSCustomObject — enriched UserInfo with Email and assigned license added.
    .EXAMPLE
        $user = [PSCustomObject]@{
            FirstName   = 'Jane'
            LastName    = 'Smith'
            DisplayName = 'Jane Smith'
            JobTitle    = 'Field Technician'
            Department  = 'Operations'
            Password    = 'TempPass123!'
            Domain      = 'contoso.com'
        }
        New-M365User -UserInfo $user
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$UserInfo
    )

    # ── Generate unique email ────────────────────────────────────────────────────
    Write-Host "`nChecking email availability..." -ForegroundColor Cyan
    $email = Get-UniqueEmail -FirstName $UserInfo.FirstName -LastName $UserInfo.LastName -Domain $UserInfo.Domain
    Write-Host "  Email: $email" -ForegroundColor Green
    Write-Host "  Temp password: $($UserInfo.Password)" -ForegroundColor Yellow

    # ── Group selection ──────────────────────────────────────────────────────────
    Write-Host "`nLoading groups..." -ForegroundColor Cyan
    $selectedGroups = Get-MgGroup -All -Property "Id,DisplayName,GroupTypes,SecurityEnabled,MailEnabled,Description" |
        Select-Object DisplayName,
            @{N='Type'; E={
                if ($_.GroupTypes -contains 'Unified')                       { 'M365 Group' }
                elseif ($_.MailEnabled -and $_.SecurityEnabled)              { 'Mail-Enabled Security' }
                elseif ($_.MailEnabled -and -not $_.SecurityEnabled)         { 'Distribution' }
                elseif ($_.SecurityEnabled -and -not $_.MailEnabled)         { 'Security' }
                else                                                         { 'Other' }
            }},
            Description, Id |
        Sort-Object DisplayName |
        Out-GridView -Title "Select groups for $($UserInfo.DisplayName) (Ctrl for multiple)" -PassThru

    $confirm = Read-Host "`nProceed with account creation? (Y/N)"
    if ($confirm -ne 'Y') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return $null }

    try {
        # ── Create user ──────────────────────────────────────────────────────────
        $params = @{
            DisplayName       = $UserInfo.DisplayName
            GivenName         = $UserInfo.FirstName
            Surname           = $UserInfo.LastName
            UserPrincipalName = $email
            MailNickname      = $email.Split('@')[0]
            AccountEnabled    = $true
            PasswordProfile   = @{
                Password                      = $UserInfo.Password
                ForceChangePasswordNextSignIn = $true
            }
        }
        if ($UserInfo.JobTitle)   { $params['JobTitle']   = $UserInfo.JobTitle }
        if ($UserInfo.Department) { $params['Department'] = $UserInfo.Department }

        $newUser = New-MgUser @params
        if (-not $newUser.Id) { throw 'User creation returned no ID.' }
        Write-Host 'M365 account created.' -ForegroundColor Green

        # ── Wait for propagation ─────────────────────────────────────────────────
        # Graph replication can take 30-90 seconds before the account is usable
        Write-Host 'Waiting for directory propagation...' -ForegroundColor Cyan
        Start-Sleep -Seconds 30
        $verified = $null; $retries = 0
        do {
            $verified = Get-MgUser -UserId $newUser.Id -ErrorAction SilentlyContinue
            if (-not $verified) { $retries++; Write-Host "  Not ready, retrying... ($retries/6)"; Start-Sleep -Seconds 10 }
        } while (-not $verified -and $retries -lt 6)
        if (-not $verified) { throw 'Account did not propagate after 90 seconds.' }
        Write-Host 'Account verified in directory.' -ForegroundColor Green

        # ── Set usage location (required before license assignment) ──────────────
        Update-MgUser -UserId $newUser.Id -UsageLocation 'US' | Out-Null
        Start-Sleep -Seconds 15

        # ── License selection from available pool ────────────────────────────────
        Write-Host 'Querying available licenses...' -ForegroundColor Cyan
        $selectedLicense = Get-MgSubscribedSku |
            Where-Object { $_.ConsumedUnits -lt $_.PrepaidUnits.Enabled } |
            Select-Object @{N='License'; E={$_.SkuPartNumber}},
                          @{N='Available'; E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}},
                          @{N='SkuId'; E={$_.SkuId}} |
            Out-GridView -Title "Select a license for $($UserInfo.DisplayName)" -PassThru |
            Select-Object -First 1

        if ($selectedLicense) {
            Set-MgUserLicense -UserId $newUser.Id `
                -AddLicenses @{ SkuId = $selectedLicense.SkuId } `
                -RemoveLicenses @() | Out-Null
            Write-Host "License assigned: $($selectedLicense.License)" -ForegroundColor Green
        } else {
            Write-Host 'No license selected.' -ForegroundColor Yellow
        }

        # ── Group membership ─────────────────────────────────────────────────────
        foreach ($group in $selectedGroups) {
            try {
                $g         = Get-MgGroup -GroupId $group.Id -Property 'Id,DisplayName,GroupTypes,SecurityEnabled,MailEnabled'
                $isUnified = $g.GroupTypes -contains 'Unified'
                $isDistro  = $g.MailEnabled -and -not $g.SecurityEnabled -and -not $isUnified

                if ($isUnified -or ($g.SecurityEnabled -and -not $g.MailEnabled)) {
                    New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $newUser.Id | Out-Null
                    Write-Host "Added to: $($group.DisplayName)" -ForegroundColor Green
                } elseif ($isDistro) {
                    # Distribution groups require Exchange Online — mailbox must finish provisioning first
                    $maxRetries = 10; $attempt = 0; $added = $false
                    do {
                        try {
                            Add-DistributionGroupMember -Identity $group.DisplayName -Member $email -ErrorAction Stop
                            Write-Host "Added to: $($group.DisplayName)" -ForegroundColor Green
                            $added = $true
                        } catch {
                            $attempt++
                            if ($attempt -lt $maxRetries) {
                                Write-Host "  Mailbox not ready for '$($group.DisplayName)', retry $attempt/$maxRetries in 30s..." -ForegroundColor Yellow
                                Start-Sleep -Seconds 30
                            }
                        }
                    } while (-not $added -and $attempt -lt $maxRetries)
                }
            } catch {
                Write-Host "Failed to add to $($group.DisplayName): $_" -ForegroundColor Red
            }
        }

        Write-Host "`n--- Summary ---" -ForegroundColor Cyan
        Write-Host "  Name:     $($UserInfo.DisplayName)"
        Write-Host "  Email:    $email"
        Write-Host "  Password: $($UserInfo.Password)"
        Write-Host "  License:  $($selectedLicense.License)"
        Write-Host "  Groups:   $(($selectedGroups.DisplayName) -join ', ')"

        return $UserInfo | Select-Object *, @{N='Email';E={$email}}, @{N='License';E={$selectedLicense.License}}

    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        return $null
    }
}
