# 02 — ServiceTitan Multi-Tenant Automation

## Problem

A field services company operating across multiple regions uses separate ServiceTitan tenants per region. When onboarding a technician, a duplicate login, phone number, or email in **any** tenant — even an inactive record — causes the API to reject the new account. Manually checking 6+ tenants before every onboarding was time-consuming and error-prone.

## Solution

Before creating any account, the script scans **all tenants** in parallel using paginated API calls across both the `technicians` and `employees` endpoints (active and inactive). Conflicts are categorized:

- **Active conflicts** — surfaced to the operator for review (potential duplicate employee)
- **Inactive conflicts on phone/email** — auto-remediated via PATCH (stale data from terminated employees)

Only after the conflict scan passes does the script prompt for tenant, role, and position selection.

## Credential Storage Pattern

Each tenant's API credentials are stored as a password entry in Hudu:

```
Entry Name:  ServiceTitan - Region Name
Username:    cid.xxxxxxxxxxxxxxxxxxxxxxxx   (ClientId)
Password:    <ClientSecret>
Notes:
  TenantId: 12345678
  AppKey:   ak1.xxxxxxxxxxxxxxxxxxxxxxxx
```

The script loads all matching entries at runtime — adding a new tenant requires only a new Hudu entry, no code changes.

## Conflict Detection Logic

```
For each tenant:
  For each endpoint (technicians, employees):
    For each active state (true, false):
      Paginate 500/page until hasMore = false
      Check each record for: LOGIN | PHONE | NAME | EMAIL match
```

## Auto-Remediation

Inactive records blocking on phone or email are cleared automatically:

```powershell
PATCH /settings/v2/tenant/{id}/technicians/{recordId}
Body: { "phoneNumber": "" }   # or { "email": "" }
```

This is safe because the record is already inactive — it cannot log in and the phone/email are just stale data.

## Usage

```powershell
$user = [PSCustomObject]@{
    DisplayName = 'Jane Smith'
    FirstName   = 'Jane'
    LastName    = 'Smith'
    Email       = 'jsmith@contoso.com'
    Phone       = '4805551234'
    Password    = 'TempPass123!'
}
Add-STTechnician -UserInfo $user
```

## Files

| File | Description |
|------|-------------|
| `Add-STTechnician.ps1` | Multi-tenant conflict scan, auto-remediation, technician creation, payroll config |
