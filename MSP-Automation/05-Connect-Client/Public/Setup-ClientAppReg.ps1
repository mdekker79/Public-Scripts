function Setup-ClientAppReg {
    <#
    .SYNOPSIS
        Creates an M365 app registration in a client tenant and saves credentials to Hudu.
    .DESCRIPTION
        Interactive setup wizard for a new client tenant. Connects using your Global Admin
        credentials (browser popup), creates an Entra app registration with a self-signed
        certificate and client secret, grants admin consent, assigns the Exchange Administrator
        role, then saves everything to Hudu under the selected company.

        After this runs, Connect-Client will work for this tenant.

    .EXAMPLE
        Setup-ClientAppReg
    .NOTES
        Prerequisites:
          - HuduAPI, Microsoft.Graph, ExchangeOnlineManagement modules installed
          - 'Hudu' secret stored in LocalSecrets vault (Microsoft.PowerShell.SecretManagement)
          - HUDU_BASE_URL environment variable set to your Hudu instance URL
          - Run as a user who can write to Cert:\CurrentUser\My
    #>
    [CmdletBinding()]
    param(
        [string]$MspName = "MSP"
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # -------------------------------------------------------
    # GRAPH PERMISSIONS TO REQUEST
    # appId 00000003-0000-0000-c000-000000000000 = Microsoft Graph
    # appId 00000002-0000-0ff1-ce00-000000000000 = Exchange Online
    # -------------------------------------------------------
    $graphAppId    = "00000003-0000-0000-c000-000000000000"
    $exchangeAppId = "00000002-0000-0ff1-ce00-000000000000"

    $graphPermissions = @(
        "User.ReadWrite.All",
        "User.RevokeSessions.All",
        "Directory.ReadWrite.All",
        "Group.ReadWrite.All",
        "MailboxSettings.ReadWrite",
        "RoleManagement.Read.All"
    )

    $exchangePermissions = @("Exchange.ManageAsApp")

    # -------------------------------------------------------
    # HELPER — WinForms company picker (Hudu)
    # -------------------------------------------------------
    function Show-CompanyPicker {
        param([array]$Companies)

        $f = New-Object System.Windows.Forms.Form
        $f.Text            = "Setup-ClientAppReg — Select Client"
        $f.Size            = New-Object System.Drawing.Size(420, 500)
        $f.StartPosition   = "CenterScreen"
        $f.FormBorderStyle = "FixedDialog"
        $f.MaximizeBox     = $false
        $f.TopMost         = $true

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text     = "Search:"
        $lbl.Location = New-Object System.Drawing.Point(12, 12)
        $lbl.Size     = New-Object System.Drawing.Size(50, 20)
        $f.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point(65, 9)
        $txt.Size     = New-Object System.Drawing.Size(325, 22)
        $f.Controls.Add($txt)

        $list = New-Object System.Windows.Forms.ListBox
        $list.Location      = New-Object System.Drawing.Point(12, 40)
        $list.Size          = New-Object System.Drawing.Size(378, 380)
        $list.Font          = New-Object System.Drawing.Font("Segoe UI", 10)
        $list.SelectionMode = "One"
        $f.Controls.Add($list)

        $btnOK = New-Object System.Windows.Forms.Button
        $btnOK.Text      = "Select"
        $btnOK.Location  = New-Object System.Drawing.Point(12, 428)
        $btnOK.Size      = New-Object System.Drawing.Size(180, 32)
        $btnOK.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
        $btnOK.ForeColor = [System.Drawing.Color]::White
        $btnOK.FlatStyle = "Flat"
        $btnOK.Enabled   = $false
        $f.Controls.Add($btnOK)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text     = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(210, 428)
        $btnCancel.Size     = New-Object System.Drawing.Size(180, 32)
        $f.Controls.Add($btnCancel)

        $allNames = $Companies | ForEach-Object { $_.name }
        $list.Items.AddRange($allNames)

        $txt.Add_TextChanged({
            $filter = $txt.Text.Trim()
            $list.BeginUpdate()
            $list.Items.Clear()
            $filtered = if ($filter) { $allNames | Where-Object { $_ -like "*$filter*" } } else { $allNames }
            if ($filtered) { $list.Items.AddRange($filtered) }
            $list.EndUpdate()
            $btnOK.Enabled = $false
        })

        $list.Add_SelectedIndexChanged({ $btnOK.Enabled = ($list.SelectedIndex -ge 0) })
        $list.Add_DoubleClick({ $f.DialogResult = [System.Windows.Forms.DialogResult]::OK; $f.Close() })
        $btnOK.Add_Click({ $f.DialogResult = [System.Windows.Forms.DialogResult]::OK; $f.Close() })
        $btnCancel.Add_Click({ $f.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $f.Close() })

        $r = $f.ShowDialog()
        if ($r -ne [System.Windows.Forms.DialogResult]::OK -or $list.SelectedIndex -lt 0) { return $null }
        return $Companies | Where-Object { $_.name -eq $list.SelectedItem } | Select-Object -First 1
    }

    # -------------------------------------------------------
    # STEP 1 — Connect to Hudu, pick company
    # -------------------------------------------------------
    Write-Host "Connecting to Hudu..." -ForegroundColor Cyan
    try {
        Connect-CCHudu
    } catch {
        Write-Host "Failed to connect to Hudu. Is your vault unlocked?" -ForegroundColor Red
        Write-Host "Run: Unlock-SecretStore" -ForegroundColor Yellow
        return
    }

    $companies = Get-HuduCompanies | Sort-Object -Property name
    if (-not $companies) { Write-Host "No companies found in Hudu." -ForegroundColor Red; return }

    $company = Show-CompanyPicker -Companies $companies
    if (-not $company) { Write-Host "Cancelled." -ForegroundColor Yellow; return }

    $companyName = $company.name
    $companyId   = $company.id

    $existing = Get-HuduPasswords -CompanyId $companyId | Where-Object { $_.name -like "*M365 App Registration*" } | Select-Object -First 1
    if ($existing) {
        $overwrite = [System.Windows.Forms.MessageBox]::Show(
            "An M365 App Registration already exists in Hudu for '$companyName'.`n`nOverwrite it with a new app registration?",
            "Already Configured",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($overwrite -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    Write-Host ""
    Write-Host "Setting up app registration for: $companyName" -ForegroundColor Cyan
    Write-Host ("-" * 55)

    # -------------------------------------------------------
    # STEP 2 — Interactive sign-in to client tenant
    # -------------------------------------------------------
    Write-Host ""
    Write-Host "A browser window will open. Sign in with a Global Admin account" -ForegroundColor Yellow
    Write-Host "for the '$companyName' tenant." -ForegroundColor Yellow
    Write-Host ""

    try {
        Connect-MgGraph -Scopes @(
            "Application.ReadWrite.All",
            "AppRoleAssignment.ReadWrite.All",
            "RoleManagement.ReadWrite.Directory",
            "Directory.ReadWrite.All"
        ) -NoWelcome -ErrorAction Stop
    } catch {
        Write-Host "Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
        return
    }

    $org      = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization" | Select-Object -ExpandProperty value | Select-Object -First 1
    $tenantId = $org.id
    $domain   = ($org.verifiedDomains | Where-Object { $_.isDefault -eq $true }).name

    Write-Host "Tenant:  $tenantId" -ForegroundColor DarkGray
    Write-Host "Domain:  $domain" -ForegroundColor DarkGray
    Write-Host ""

    # -------------------------------------------------------
    # STEP 3 — Self-signed certificate
    # -------------------------------------------------------
    Write-Host "[1/6] Creating self-signed certificate..." -ForegroundColor Cyan
    $certSubject = "CN=$MspName-$($companyName -replace '[^a-zA-Z0-9]','')-M365"
    try {
        $cert = New-SelfSignedCertificate `
            -Subject $certSubject `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -KeyExportPolicy Exportable `
            -KeySpec Signature `
            -KeyLength 2048 `
            -HashAlgorithm SHA256 `
            -NotAfter (Get-Date).AddYears(2) `
            -ErrorAction Stop
        $thumbprint  = $cert.Thumbprint
        $certBase64  = [Convert]::ToBase64String($cert.RawData)
        Write-Host "      Thumbprint: $thumbprint" -ForegroundColor Green
    } catch {
        Write-Host "      Failed to create certificate: $_" -ForegroundColor Red
        return
    }

    # -------------------------------------------------------
    # STEP 4 — Create app registration
    # -------------------------------------------------------
    Write-Host "[2/6] Creating app registration..." -ForegroundColor Cyan

    $graphSp    = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
    $exchangeSp = Get-MgServicePrincipal -Filter "appId eq '$exchangeAppId'"

    $graphRoles = $graphSp.AppRoles | Where-Object { $_.Value -in $graphPermissions -and $_.AllowedMemberTypes -contains "Application" }
    $exchRoles  = $exchangeSp.AppRoles | Where-Object { $_.Value -in $exchangePermissions -and $_.AllowedMemberTypes -contains "Application" }

    $requiredAccess = @(
        @{
            resourceAppId  = $graphAppId
            resourceAccess = @($graphRoles | ForEach-Object { @{ id = $_.Id; type = "Role" } })
        },
        @{
            resourceAppId  = $exchangeAppId
            resourceAccess = @($exchRoles | ForEach-Object { @{ id = $_.Id; type = "Role" } })
        }
    )

    try {
        $appParams = @{
            DisplayName            = "$MspName — $companyName"
            SignInAudience         = "AzureADMyOrg"
            RequiredResourceAccess = $requiredAccess
            KeyCredentials         = @(@{
                Type        = "AsymmetricX509Cert"
                Usage       = "Verify"
                Key         = [System.Convert]::FromBase64String($certBase64)
                DisplayName = $certSubject
            })
        }
        $app      = New-MgApplication @appParams -ErrorAction Stop
        $clientId = $app.AppId
        Write-Host "      App ID: $clientId" -ForegroundColor Green
    } catch {
        Write-Host "      Failed to create app registration: $_" -ForegroundColor Red
        return
    }

    Start-Sleep -Seconds 3
    $sp = New-MgServicePrincipal -AppId $clientId -ErrorAction Stop

    # -------------------------------------------------------
    # STEP 5 — Client secret
    # -------------------------------------------------------
    Write-Host "[3/6] Creating client secret..." -ForegroundColor Cyan
    try {
        $secretParams = @{
            PasswordCredential = @{
                DisplayName = "$MspName MSP Secret"
                EndDateTime = (Get-Date).AddYears(2)
            }
        }
        $secretResult = Add-MgApplicationPassword -ApplicationId $app.Id @secretParams -ErrorAction Stop
        $clientSecret = $secretResult.SecretText
        Write-Host "      Done. (secret stored in Hudu — not displayed)" -ForegroundColor Green
    } catch {
        Write-Host "      Failed to create client secret: $_" -ForegroundColor Red
        return
    }

    # -------------------------------------------------------
    # STEP 6 — Grant admin consent
    # -------------------------------------------------------
    Write-Host "[4/6] Granting admin consent..." -ForegroundColor Cyan
    $consentErrors = 0

    foreach ($role in $graphRoles) {
        try {
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $graphSp.Id -AppRoleId $role.Id -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "      Warning — Graph '$($role.Value)': $_" -ForegroundColor Yellow
            $consentErrors++
        }
    }

    foreach ($role in $exchRoles) {
        try {
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $exchangeSp.Id -AppRoleId $role.Id -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "      Warning — Exchange '$($role.Value)': $_" -ForegroundColor Yellow
            $consentErrors++
        }
    }

    if ($consentErrors -eq 0) {
        Write-Host "      All permissions consented." -ForegroundColor Green
    } else {
        Write-Host "      Completed with $consentErrors warning(s) — check manually in Entra." -ForegroundColor Yellow
    }

    # -------------------------------------------------------
    # STEP 7 — Assign Exchange Administrator role
    # -------------------------------------------------------
    Write-Host "[5/6] Assigning Exchange Administrator role..." -ForegroundColor Cyan
    try {
        $exchangeAdminRoleId = "29232cdf-9323-42fd-ade2-1d097af3e4de"
        $roledef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $exchangeAdminRoleId -ErrorAction Stop
        New-MgRoleManagementDirectoryRoleAssignment `
            -PrincipalId $sp.Id `
            -RoleDefinitionId $roledef.Id `
            -DirectoryScopeId "/" `
            -ErrorAction Stop | Out-Null
        Write-Host "      Done." -ForegroundColor Green
    } catch {
        Write-Host "      Failed (may need to assign manually in Entra > Roles): $_" -ForegroundColor Red
    }

    # -------------------------------------------------------
    # STEP 8 — Save to Hudu
    # -------------------------------------------------------
    Write-Host "[6/6] Saving credentials to Hudu..." -ForegroundColor Cyan

    $notes = @"
TenantId: $tenantId
Thumbprint: $thumbprint
Domain: $domain
CertSubject: $certSubject
CertExpiry: $((Get-Date).AddYears(2).ToString('yyyy-MM-dd'))
AppName: $MspName — $companyName
AppObjectId: $($app.Id)
"@

    try {
        if ($existing) {
            Set-HuduPassword -Id $existing.id `
                -Name "M365 App Registration" `
                -Username $clientId `
                -Password $clientSecret `
                -Description $notes `
                -CompanyId $companyId `
                -ErrorAction Stop | Out-Null
            Write-Host "      Updated existing Hudu entry." -ForegroundColor Green
        } else {
            New-HuduPassword `
                -Name "M365 App Registration" `
                -Username $clientId `
                -Password $clientSecret `
                -Description $notes `
                -CompanyId $companyId `
                -ErrorAction Stop | Out-Null
            Write-Host "      New Hudu entry created." -ForegroundColor Green
        }
    } catch {
        Write-Host "      Failed to save to Hudu: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "SAVE THESE MANUALLY — they cannot be recovered:" -ForegroundColor Red
        Write-Host "  Client ID     : $clientId" -ForegroundColor Yellow
        Write-Host "  Client Secret : $clientSecret" -ForegroundColor Yellow
        Write-Host "  Thumbprint    : $thumbprint" -ForegroundColor Yellow
        Write-Host "  Tenant ID     : $tenantId" -ForegroundColor Yellow
    }

    # -------------------------------------------------------
    # DONE
    # -------------------------------------------------------
    Write-Host ""
    Write-Host ("=" * 55) -ForegroundColor Green
    Write-Host " Setup complete: $companyName" -ForegroundColor Green
    Write-Host ("=" * 55) -ForegroundColor Green
    Write-Host "  Tenant ID  : $tenantId"
    Write-Host "  Domain     : $domain"
    Write-Host "  Client ID  : $clientId"
    Write-Host "  Thumbprint : $thumbprint"
    Write-Host "  Cert store : Cert:\CurrentUser\My\$thumbprint"
    Write-Host "  Cert expiry: $((Get-Date).AddYears(2).ToString('yyyy-MM-dd'))"
    Write-Host ""
    Write-Host "Run 'Connect-Client' and select '$companyName' to connect." -ForegroundColor Cyan

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
