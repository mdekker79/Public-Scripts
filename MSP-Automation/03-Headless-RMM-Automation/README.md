# 03 — Headless RMM Automation (NinjaOne / Rewst)

## Problem

Interactive onboarding scripts with `Read-Host` and `Out-GridView` can't run in an RMM platform. NinjaOne executes scripts on a headless automation host — there's no console, no UI, no operator present. All selections need to come in as parameters, and the output needs to be structured JSON that downstream workflow steps can parse.

## Architecture

```
Rewst Form (browser)
    │  operator fills in: name, phone, tenant, role, positions, license, groups
    │
    ▼
NinjaOne Script Run  ──►  Invoke-Onboarding.ps1 (this script)
    │                          │
    │                          ├── M365: New-MgUser, Set-MgUserLicense, group membership
    │                          └── ServiceTitan: POST /technicians, PATCH payroll
    │
    ▼
JSON output  ──►  Rewst captures and routes to next step
    {
      "success": true,
      "email": "jsmith@contoso.com",
      "password": "Xk7mnpqr3",
      "stId": 12345678,
      "stUrl": "https://go.servicetitan.com/#/Settings/Technician/12345678"
    }
```

## Companion Script

`Get-OnboardingFormOptions.ps1` (not shown) powers the Rewst form dropdowns — it queries the live environment and returns all valid options:

```json
{
  "tenants":    [{ "name": "Region A", "tenantId": "12345678" }],
  "roles":      [{ "name": "Technician", "id": 42 }],
  "positions":  ["HVAC", "Plumbing", "Electrical"],
  "licenses":   [{ "name": "Microsoft 365 Business Standard", "skuId": "...", "available": 3 }],
  "groups":     [{ "name": "All Staff", "id": "...", "type": "Security" }]
}
```

This means the form always reflects the current state — no hardcoded lists to maintain.

## Error Handling

The script wraps everything in a try/catch and always outputs valid JSON:

```powershell
# Success
{ "success": true, "email": "...", "stId": 12345678 }

# Failure — Rewst routes to error handling branch
{ "success": false, "error": "Account did not propagate after 90 seconds." }
```

Exit code 1 on failure signals NinjaOne to mark the run as failed.

## Key Design Decisions

| Decision | Reason |
|----------|--------|
| No `Read-Host` or `Out-GridView` | Headless execution — no stdin, no display |
| JSON output via `Write-Output` | Rewst captures stdout, not return values |
| `$ErrorActionPreference = 'Stop'` | Any unhandled error falls to the catch block |
| Propagation retry loop | M365 replication is async — skipping causes license failures |
| Token refresh before group ops | Long propagation waits can expire the initial Graph token |

## Files

| File | Description |
|------|-------------|
| `Invoke-Onboarding.ps1` | Headless M365 + ServiceTitan onboarding — parameter-driven, JSON output |
