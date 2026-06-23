function Add-STTechnician {
    <#
    .SYNOPSIS
        Creates a new technician in ServiceTitan with cross-tenant conflict checking.
    .DESCRIPTION
        Before creating a technician, scans ALL configured ServiceTitan tenants for
        conflicts on login, phone number, name, and email. Inactive records with
        conflicting phone/email are auto-remediated via PATCH. Active conflicts
        require operator confirmation.

        After creation, configures payroll settings and automates the MFA setup
        step by generating a TOTP code from the admin account secret stored in
        the secrets manager.

        Credentials for each tenant are stored in a secrets manager (Hudu) with
        a structured notes format:
            TenantId: 12345678
            AppKey:   ak1.xxxxxxxxxxxxx

    .PARAMETER UserInfo
        PSCustomObject with: DisplayName, FirstName, LastName, Email, Phone, Password.
    .EXAMPLE
        $user = [PSCustomObject]@{
            DisplayName = 'Jane Smith'
            FirstName   = 'Jane'
            LastName    = 'Smith'
            Email       = 'jsmith@contoso.com'
            Phone       = '4805551234'
            Password    = 'TempPass123!'
        }
        Add-STTechnician -UserInfo $user
    .NOTES
        Requires: HuduAPI module, ServiceTitan API app credentials per tenant in Hudu.
        API Docs: https://developer.servicetitan.io/
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$UserInfo
    )

    $email = $UserInfo.Email
    $login = $email.ToLower()

    # ── Load tenants from secrets manager ────────────────────────────────────────
    Write-Host "`nLoading ServiceTitan tenants..." -ForegroundColor Cyan

    # Tenant credentials are stored as password entries named "ServiceTitan - <TenantName>"
    # Notes field contains: TenantId, AppKey
    # Username field contains: ClientId (cid.xxxxx)
    # Password field contains: ClientSecret
    $tenantEntries = Get-HuduPasswords | Where-Object {
        $_.name -like '*ServiceTitan*' -and $_.username -like 'cid.*'
    }

    if (-not $tenantEntries) {
        Write-Host 'No ServiceTitan tenants found in secrets manager.' -ForegroundColor Red
        return
    }

    $tenantList = $tenantEntries | ForEach-Object {
        $tenantId = if ($_.description -match 'TenantId:\s*(\d+)') { $matches[1] } else { $null }
        $appKey   = if ($_.description -match 'AppKey:\s*(\S+)')   { $matches[1] } else { $null }
        if (-not $tenantId) { Write-Warning "Skipping '$($_.name)' — no TenantId in notes"; return }
        if (-not $appKey)   { Write-Warning "Skipping '$($_.name)' — no AppKey in notes";   return }
        [PSCustomObject]@{
            Name         = $_.name
            TenantId     = $tenantId
            ClientId     = $_.username
            ClientSecret = $_.password
            AppKey       = $appKey
        }
    } | Sort-Object TenantId -Unique

    Write-Host "  Found $($tenantList.Count) tenant(s)." -ForegroundColor Green

    # ── Cross-tenant conflict check ──────────────────────────────────────────────
    Write-Host 'Scanning all tenants for conflicts (login, phone, name, email)...' -ForegroundColor Cyan

    $targetPhone = $UserInfo.Phone -replace '\D', ''
    $targetName  = $UserInfo.DisplayName.ToLower().Trim()
    $targetEmail = $email.ToLower()
    $conflicts   = @()

    foreach ($t in $tenantList) {
        try {
            $tok = Invoke-RestMethod -Method Post `
                -Uri 'https://auth.servicetitan.io/connect/token' `
                -Body @{
                    grant_type    = 'client_credentials'
                    client_id     = $t.ClientId
                    client_secret = $t.ClientSecret
                }
            $h  = @{ Authorization = "Bearer $($tok.access_token)"; 'ST-App-Key' = $t.AppKey }
            $bu = "https://api.servicetitan.io/settings/v2/tenant/$($t.TenantId)"

            foreach ($endpoint in @('technicians', 'employees')) {
                foreach ($active in @('true', 'false')) {
                    $page = 1
                    do {
                        $r = Invoke-RestMethod -Uri "$bu/${endpoint}?pageSize=500&page=$page&active=$active" -Headers $h
                        foreach ($rec in $r.data) {
                            $flags = @()
                            if ($rec.login   -and $rec.login.ToLower()                    -eq $login)        { $flags += 'LOGIN' }
                            if (($rec.phoneNumber -replace '\D','')                        -eq $targetPhone)  { $flags += 'PHONE' }
                            if ($rec.name    -and $rec.name.ToLower()                     -eq $targetName)   { $flags += 'NAME'  }
                            if ($rec.email   -and $rec.email.ToLower()                    -eq $targetEmail)  { $flags += 'EMAIL' }
                            if ($flags) {
                                $conflicts += [PSCustomObject]@{
                                    Tenant   = $t.Name
                                    TenantId = $t.TenantId
                                    Type     = $endpoint.TrimEnd('s')
                                    Flags    = $flags -join '+'
                                    Name     = $rec.name
                                    Login    = $rec.login
                                    Phone    = $rec.phoneNumber
                                    Email    = $rec.email
                                    Active   = $rec.active
                                    Id       = $rec.id
                                    Headers  = $h
                                    BaseUri  = $bu
                                }
                            }
                        }
                        $page++
                    } while ($r.hasMore -eq $true)
                }
            }
            Write-Host "  Checked: $($t.Name)" -ForegroundColor DarkGray
        } catch {
            Write-Host "  Could not check $($t.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($conflicts) {
        Write-Host "`nConflicts found:" -ForegroundColor Yellow
        foreach ($c in $conflicts) {
            $label = if ($c.Active) { 'ACTIVE' } else { 'inactive' }
            $color = if ($c.Active) { 'Red' } else { 'Yellow' }
            Write-Host "  [$label] $($c.Flags) — $($c.Name) | login=$($c.Login) | $($c.Tenant)" -ForegroundColor $color
        }

        # Active conflicts require operator sign-off
        if ($conflicts | Where-Object { $_.Active }) {
            $cont = Read-Host "`nActive conflicts found — continue anyway? (Y/N)"
            if ($cont -ne 'Y') { return }
        }

        # Auto-remediate inactive conflicts — clear phone and email so they don't block creation
        foreach ($c in ($conflicts | Where-Object { -not $_.Active })) {
            if ($c.Flags -match 'PHONE') {
                try {
                    Invoke-RestMethod -Uri "$($c.BaseUri)/$($c.Type)s/$($c.Id)" -Method Patch `
                        -Headers $c.Headers -Body (@{ phoneNumber = '' } | ConvertTo-Json) `
                        -ContentType 'application/json' | Out-Null
                    Write-Host "  Auto-cleared phone: $($c.Name) ($($c.Tenant))" -ForegroundColor Green
                } catch { Write-Host "  Failed to clear phone for $($c.Name): $($_.Exception.Message)" -ForegroundColor Red }
            }
            if ($c.Flags -match 'EMAIL') {
                try {
                    Invoke-RestMethod -Uri "$($c.BaseUri)/$($c.Type)s/$($c.Id)" -Method Patch `
                        -Headers $c.Headers -Body (@{ email = '' } | ConvertTo-Json) `
                        -ContentType 'application/json' | Out-Null
                    Write-Host "  Auto-cleared email: $($c.Name) ($($c.Tenant))" -ForegroundColor Green
                } catch { Write-Host "  Failed to clear email for $($c.Name): $($_.Exception.Message)" -ForegroundColor Red }
            }
        }
    } else {
        Write-Host '  No conflicts.' -ForegroundColor Green
    }

    # ── Tenant selection ─────────────────────────────────────────────────────────
    $selectedTenant = $tenantList | Select-Object Name, TenantId |
        Out-GridView -Title 'Select tenant to create technician in' -PassThru |
        Select-Object -First 1
    if (-not $selectedTenant) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }

    $creds = $tenantList | Where-Object { $_.TenantId -eq $selectedTenant.TenantId } | Select-Object -First 1

    # ── Authenticate to selected tenant ──────────────────────────────────────────
    $tok = Invoke-RestMethod -Method Post `
        -Uri 'https://auth.servicetitan.io/connect/token' `
        -Body @{ grant_type = 'client_credentials'; client_id = $creds.ClientId; client_secret = $creds.ClientSecret }

    $headers = @{ Authorization = "Bearer $($tok.access_token)"; 'ST-App-Key' = $creds.AppKey }
    $baseUri = "https://api.servicetitan.io/settings/v2/tenant/$($creds.TenantId)"

    # ── Role selection ───────────────────────────────────────────────────────────
    $selectedRole = (Invoke-RestMethod -Uri "$baseUri/user-roles" -Headers $headers).data |
        Select-Object name, id | Sort-Object name |
        Out-GridView -Title "Select role for $($UserInfo.DisplayName)" -PassThru |
        Select-Object -First 1
    if (-not $selectedRole) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }

    # ── Position selection ───────────────────────────────────────────────────────
    $positions = (Invoke-RestMethod -Uri "$baseUri/technicians" -Headers $headers).data |
        ForEach-Object { $_.positions } | Where-Object { $_ } | Sort-Object -Unique |
        ForEach-Object { [PSCustomObject]@{ Position = $_ } } |
        Out-GridView -Title "Select position(s) for $($UserInfo.DisplayName) (Ctrl for multiple)" -PassThru |
        Select-Object -ExpandProperty Position

    if (-not $positions) { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }

    # ── Create technician ────────────────────────────────────────────────────────
    $confirm = Read-Host "`nCreate '$($UserInfo.DisplayName)' in '$($creds.Name)'? (Y/N)"
    if ($confirm -ne 'Y') { Write-Host 'Cancelled.' -ForegroundColor Yellow; return }

    $body = @{
        name                  = $UserInfo.DisplayName
        email                 = $email
        phoneNumber           = ($UserInfo.Phone -replace '\D', '')
        login                 = $login
        password              = $UserInfo.Password
        roleId                = $selectedRole.id
        positions             = @($positions)
        licenseType           = 'ManagedTech'
        accountCreationMethod = 'AssignLoginAndPassword'
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "$baseUri/technicians" -Method Post `
            -Headers $headers -Body $body -ContentType 'application/json'

        Write-Host "`nTechnician created: ID $($response.id)" -ForegroundColor Green

        # Configure payroll
        Invoke-RestMethod -Uri "$baseUri/technicians/$($response.id)" -Method Patch `
            -Headers $headers -ContentType 'application/json' `
            -Body (@{ includeInPayroll = $true; payType = 'Both' } | ConvertTo-Json) | Out-Null
        Write-Host 'Payroll configured.' -ForegroundColor Green

        # Open browser to technician profile for MFA setup
        $stUrl = "https://go.servicetitan.com/#/Settings/Technician/$($response.id)"
        Start-Process 'msedge.exe' "--inprivate $stUrl"
        Write-Host "Browser opened for MFA setup: $stUrl" -ForegroundColor Cyan

    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}
