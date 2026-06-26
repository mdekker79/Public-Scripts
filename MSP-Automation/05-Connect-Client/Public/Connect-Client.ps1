function Connect-Client {
    <#
    .SYNOPSIS
        One-click M365/Exchange/Graph connection to any client tenant.
    .DESCRIPTION
        Opens a searchable WinForms window listing all Hudu companies. Select a client
        to connect Exchange Online and Microsoft Graph using the app registration stored
        in Hudu. Requires a Hudu password entry named "M365 App Registration" with:
          - Username    : Client ID (application ID)
          - Password    : Client Secret
          - Description : Must contain "Thumbprint: <value>" and "TenantId: <value>"
    .EXAMPLE
        Connect-Client
    .NOTES
        Prerequisites:
          - HuduAPI, ExchangeOnlineManagement, Microsoft.Graph modules installed
          - 'Hudu' secret stored in LocalSecrets vault (Microsoft.PowerShell.SecretManagement)
          - HUDU_BASE_URL environment variable set to your Hudu instance URL
          - Run Initialize-ClientSecrets once per machine if not already set up
    #>
    [CmdletBinding()]
    param()

    # -------------------------------------------------------
    # HUDU CONNECTION
    # -------------------------------------------------------
    try {
        Connect-CCHudu
    } catch {
        Write-Host "Failed to connect to Hudu. Is your vault unlocked?" -ForegroundColor Red
        Write-Host "Run: Unlock-SecretStore" -ForegroundColor Yellow
        return
    }

    # -------------------------------------------------------
    # LOAD COMPANY LIST
    # -------------------------------------------------------
    Write-Host "Loading client list from Hudu..." -ForegroundColor Cyan
    $companies = Get-HuduCompanies | Sort-Object -Property name

    if (-not $companies) {
        Write-Host "No companies found in Hudu." -ForegroundColor Red
        return
    }

    # -------------------------------------------------------
    # WINFORMS PICKER
    # -------------------------------------------------------
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Connect-Client — Select Tenant"
    $form.Size            = New-Object System.Drawing.Size(420, 500)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text     = "Search:"
    $lblSearch.Location = New-Object System.Drawing.Point(12, 12)
    $lblSearch.Size     = New-Object System.Drawing.Size(50, 20)
    $form.Controls.Add($lblSearch)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(65, 9)
    $txtSearch.Size     = New-Object System.Drawing.Size(325, 22)
    $form.Controls.Add($txtSearch)

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location      = New-Object System.Drawing.Point(12, 40)
    $listBox.Size          = New-Object System.Drawing.Size(378, 380)
    $listBox.Font          = New-Object System.Drawing.Font("Segoe UI", 10)
    $listBox.SelectionMode = "One"
    $form.Controls.Add($listBox)

    $btnConnect = New-Object System.Windows.Forms.Button
    $btnConnect.Text      = "Connect"
    $btnConnect.Location  = New-Object System.Drawing.Point(12, 428)
    $btnConnect.Size      = New-Object System.Drawing.Size(180, 32)
    $btnConnect.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $btnConnect.ForeColor = [System.Drawing.Color]::White
    $btnConnect.FlatStyle = "Flat"
    $btnConnect.Enabled   = $false
    $form.Controls.Add($btnConnect)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text     = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(210, 428)
    $btnCancel.Size     = New-Object System.Drawing.Size(180, 32)
    $form.Controls.Add($btnCancel)

    $allNames = $companies | ForEach-Object { $_.name }
    $listBox.Items.AddRange($allNames)

    $txtSearch.Add_TextChanged({
        $filter = $txtSearch.Text.Trim()
        $listBox.BeginUpdate()
        $listBox.Items.Clear()
        $filtered = if ($filter) {
            $allNames | Where-Object { $_ -like "*$filter*" }
        } else {
            $allNames
        }
        if ($filtered) { $listBox.Items.AddRange($filtered) }
        $listBox.EndUpdate()
        $btnConnect.Enabled = $false
    })

    $listBox.Add_SelectedIndexChanged({
        $btnConnect.Enabled = ($listBox.SelectedIndex -ge 0)
    })

    $listBox.Add_DoubleClick({ $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() })
    $btnConnect.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() })
    $btnCancel.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $form.Close() })
    $form.AcceptButton = $btnConnect

    $result = $form.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK -or $listBox.SelectedItem -eq $null) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    $selectedName    = $listBox.SelectedItem
    $selectedCompany = $companies | Where-Object { $_.name -eq $selectedName } | Select-Object -First 1

    # -------------------------------------------------------
    # LOOK UP APP REGISTRATION IN HUDU
    # -------------------------------------------------------
    Write-Host "Looking up credentials for '$selectedName'..." -ForegroundColor Cyan

    $passwords = Get-HuduPasswords -CompanyId $selectedCompany.id
    $appReg = $passwords | Where-Object { $_.name -like "*M365 App Registration*" } | Select-Object -First 1

    if (-not $appReg) {
        Write-Host ""
        Write-Host "No M365 App Registration found for '$selectedName'." -ForegroundColor Red
        Write-Host "This client has not been set up yet. Run Setup-ClientAppReg to configure." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Expected Hudu entry:" -ForegroundColor DarkGray
        Write-Host "  Name     : M365 App Registration" -ForegroundColor DarkGray
        Write-Host "  Username : <Client ID>" -ForegroundColor DarkGray
        Write-Host "  Password : <Client Secret>" -ForegroundColor DarkGray
        Write-Host "  Notes    : Thumbprint: <cert thumbprint>" -ForegroundColor DarkGray
        Write-Host "             TenantId: <tenant GUID>" -ForegroundColor DarkGray
        return
    }

    $clientId     = $appReg.username
    $clientSecret = $appReg.password
    $notes        = $appReg.description

    $thumbprint = if ($notes -match 'Thumbprint:\s*(\S+)') { $matches[1] } else { $null }
    $tenantId   = if ($notes -match 'TenantId:\s*(\S+)')   { $matches[1] } else { $null }

    if (-not $clientId) {
        Write-Host "Client ID (username) is missing from the Hudu entry for '$selectedName'." -ForegroundColor Red
        return
    }

    # -------------------------------------------------------
    # CONNECT EXCHANGE ONLINE (cert-based, requires thumbprint)
    # -------------------------------------------------------
    if ($thumbprint -and $tenantId) {
        $orgDomain = if ($notes -match 'Domain:\s*(\S+)') { $matches[1] } else { $null }
        if (-not $orgDomain) { $orgDomain = $selectedCompany.website }

        if ($orgDomain) {
            $orgDomain = $orgDomain -replace '^https?://', '' -replace '/$', ''
            try {
                Write-Host "Connecting Exchange Online ($orgDomain)..." -ForegroundColor Cyan
                Connect-ExchangeOnline -AppId $clientId -CertificateThumbprint $thumbprint -Organization $orgDomain -ShowBanner:$false
                Write-Host "Exchange Online connected." -ForegroundColor Green
            } catch {
                Write-Host "Exchange Online connection failed: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "Skipping Exchange Online — no domain found." -ForegroundColor Yellow
            Write-Host "Add 'Domain: contoso.com' to the Hudu notes, or set the company Website field." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Skipping Exchange Online — Thumbprint or TenantId missing from Hudu notes." -ForegroundColor Yellow
    }

    # -------------------------------------------------------
    # CONNECT MICROSOFT GRAPH (client credentials)
    # -------------------------------------------------------
    if ($clientSecret -and $tenantId) {
        try {
            Write-Host "Connecting Microsoft Graph..." -ForegroundColor Cyan
            $body = @{
                Grant_Type    = "client_credentials"
                Scope         = "https://graph.microsoft.com/.default"
                Client_Id     = $clientId
                Client_Secret = $clientSecret
            }
            $token = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method POST -Body $body -ErrorAction Stop
            Connect-MgGraph -AccessToken ($token.access_token | ConvertTo-SecureString -AsPlainText -Force) -NoWelcome
            Write-Host "Microsoft Graph connected." -ForegroundColor Green
        } catch {
            Write-Host "Microsoft Graph connection failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Skipping Microsoft Graph — Client Secret or TenantId missing from Hudu notes." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Connected to: $selectedName" -ForegroundColor Green
}
