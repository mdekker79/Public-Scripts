# Invoke-Onboarding.ps1
#
# Headless onboarding script — no interactive prompts, no Out-GridView.
# Designed to run via NinjaOne/Rewst on a dedicated automation host.
# All selections arrive as parameters from the Rewst workflow form.
# Output is a single JSON object captured by Rewst for downstream steps.
#
# Companion script Get-OnboardingFormOptions.ps1 populates the Rewst form
# dropdowns dynamically (tenants, roles, positions, licenses, groups).

param(
    [Parameter(Mandatory)] [string]$FirstName,
    [Parameter(Mandatory)] [string]$LastName,
    [Parameter(Mandatory)] [string]$Phone,
    [string]$JobTitle,
    [string]$Department,
    [Parameter(Mandatory)] [string]$TenantId,      # ST TenantId from form
    [Parameter(Mandatory)] [string]$RoleId,        # ST role id from form
    [Parameter(Mandatory)] [string]$Positions,     # Comma-separated positions
    [Parameter(Mandatory)] [string]$LicenseSkuId,  # M365 license SkuId
    [Parameter(Mandatory)] [string]$GroupIds       # Comma-separated M365 group Ids
)

$ErrorActionPreference = 'Stop'

try {
    # Adjust module path to match your automation host layout
    Import-Module "C:\Automation\Modules\YourModule.psd1" -Force

    $displayName  = "$FirstName $LastName"
    $positionList = $Positions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $groupIdList  = $GroupIds  -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

    # ── Generate temp password ───────────────────────────────────────────────────
    # Avoids ambiguous characters (0/O, 1/l/I) for readability when handed to user
    $lower   = 'abcdefghijkmnpqrstuvwxyz'
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $digits  = '23456789'
    $special = '!@#$'
    $password = $upper[(Get-Random -Maximum $upper.Length)] +
                $special[(Get-Random -Maximum $special.Length)] +
                (-join ((1..6) | ForEach-Object { $lower[(Get-Random -Maximum $lower.Length)] })) +
                $digits[(Get-Random -Maximum $digits.Length)]

    $userInfo = [PSCustomObject]@{
        FirstName   = $FirstName
        LastName    = $LastName
        DisplayName = $displayName
        Phone       = $Phone
        JobTitle    = $JobTitle
        Department  = $Department
        Password    = $password
    }

    # ── M365 account creation ────────────────────────────────────────────────────
    Get-GraphToken   # connects to Graph using app credentials from secrets manager

    Write-Output 'Checking email availability...'
    $email = Get-UniqueEmail -FirstName $FirstName -LastName $LastName -Domain 'contoso.com'
    Write-Output "Email: $email"

    $params = @{
        DisplayName       = $displayName
        GivenName         = $FirstName
        Surname           = $LastName
        UserPrincipalName = $email
        MailNickname      = $email.Split('@')[0]
        AccountEnabled    = $true
        PasswordProfile   = @{ Password = $password; ForceChangePasswordNextSignIn = $true }
    }
    if ($JobTitle)   { $params['JobTitle']   = $JobTitle }
    if ($Department) { $params['Department'] = $Department }

    $newUser = New-MgUser @params
    if (-not $newUser.Id) { throw 'M365 user creation failed — no ID returned.' }
    Write-Output 'M365 account created.'

    # Wait for directory propagation before license/group operations
    Write-Output 'Waiting for propagation...'
    Start-Sleep -Seconds 30
    $verified = $null; $retries = 0
    do {
        $verified = Get-MgUser -UserId $newUser.Id -ErrorAction SilentlyContinue
        if (-not $verified) { $retries++; Start-Sleep -Seconds 10 }
    } while (-not $verified -and $retries -lt 6)
    if (-not $verified) { throw 'Account did not propagate after 90 seconds.' }

    Update-MgUser -UserId $newUser.Id -UsageLocation 'US' | Out-Null
    Start-Sleep -Seconds 15

    Set-MgUserLicense -UserId $newUser.Id `
        -AddLicenses @{ SkuId = $LicenseSkuId } -RemoveLicenses @() | Out-Null
    Write-Output 'License assigned.'

    # Add to groups — handles M365, Security, and Distribution group types
    Get-GraphToken | Out-Null  # refresh in case token expired during propagation waits
    foreach ($gid in $groupIdList) {
        try {
            $g        = Get-MgGroup -GroupId $gid -Property 'Id,DisplayName,GroupTypes,SecurityEnabled,MailEnabled'
            $unified  = $g.GroupTypes -contains 'Unified'
            $security = $g.SecurityEnabled -and -not $g.MailEnabled
            $distro   = $g.MailEnabled -and -not $g.SecurityEnabled -and -not $unified

            if ($unified -or $security) {
                New-MgGroupMember -GroupId $gid -DirectoryObjectId $newUser.Id | Out-Null
                Write-Output "Added to group: $($g.DisplayName)"
            } elseif ($distro) {
                $attempts = 0; $added = $false
                do {
                    try {
                        Add-DistributionGroupMember -Identity $g.DisplayName -Member $email -ErrorAction Stop
                        Write-Output "Added to group: $($g.DisplayName)"
                        $added = $true
                    } catch {
                        $attempts++
                        if ($attempts -lt 10) { Start-Sleep -Seconds 30 }
                    }
                } while (-not $added -and $attempts -lt 10)
            }
        } catch {
            Write-Output "WARNING: Could not add to group $gid — $($_.Exception.Message)"
        }
    }

    # ── ServiceTitan technician creation ─────────────────────────────────────────
    $tenantCreds = Get-STTenantCredentials -TenantId $TenantId  # loads from secrets manager

    $tok = Invoke-RestMethod -Method Post -Uri 'https://auth.servicetitan.io/connect/token' `
        -Body @{ grant_type = 'client_credentials'; client_id = $tenantCreds.ClientId; client_secret = $tenantCreds.ClientSecret }

    $headers = @{ Authorization = "Bearer $($tok.access_token)"; 'ST-App-Key' = $tenantCreds.AppKey }
    $baseUri = "https://api.servicetitan.io/settings/v2/tenant/$TenantId"

    $body = @{
        name                  = $displayName
        email                 = $email
        phoneNumber           = ($Phone -replace '\D', '')
        login                 = $email.ToLower()
        password              = $password
        roleId                = [int]$RoleId
        positions             = $positionList
        licenseType           = 'ManagedTech'
        accountCreationMethod = 'AssignLoginAndPassword'
    } | ConvertTo-Json -Depth 10

    $stUser = Invoke-RestMethod -Uri "$baseUri/technicians" -Method Post `
        -Headers $headers -Body $body -ContentType 'application/json'
    Write-Output "ST Technician created: ID $($stUser.id)"

    # Configure payroll
    Invoke-RestMethod -Uri "$baseUri/technicians/$($stUser.id)" -Method Patch `
        -Headers $headers -ContentType 'application/json' `
        -Body (@{ includeInPayroll = $true; payType = 'Both' } | ConvertTo-Json) | Out-Null
    Write-Output 'Payroll configured.'

    # ── JSON output captured by Rewst ────────────────────────────────────────────
    @{
        success     = $true
        displayName = $displayName
        email       = $email
        password    = $password
        stId        = $stUser.id
        tenant      = $tenantCreds.Name
        stUrl       = "https://go.servicetitan.com/#/Settings/Technician/$($stUser.id)"
    } | ConvertTo-Json -Compress | Write-Output

} catch {
    @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress | Write-Output
    exit 1
}
