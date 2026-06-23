# 01 — M365 Provisioning

## Problem

Manually creating M365 accounts for a growing field services company is error-prone and slow — especially when email collisions, license availability, and group membership across multiple group types all need to be handled correctly.

## Solution

A full provisioning workflow via Microsoft Graph SDK that handles every edge case:

- **Unique email generation** — progressive last-name suffix algorithm (`jsmith` → `jsmi` → `js` → `jsmith2`) to guarantee no collisions without user intervention
- **Propagation retry loop** — M365 account creation is async; the script waits up to 90 seconds with retries before proceeding to license/group steps
- **License pool selection** — queries available licenses and shows only those with remaining seats
- **Multi-type group handling** — M365 Groups and Security Groups use Graph API; Distribution Groups require Exchange Online with a separate retry loop (mailbox provisioning is slower than account provisioning)

## Prerequisites

```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Directory.ReadWrite.All"
Connect-ExchangeOnline   # only needed if adding to Distribution Groups
```

## Usage

```powershell
$user = [PSCustomObject]@{
    FirstName   = 'Jane'
    LastName    = 'Smith'
    DisplayName = 'Jane Smith'
    JobTitle    = 'Field Technician'
    Department  = 'Operations'
    Password    = 'TempPass123!'
    Domain      = 'contoso.com'
}

$created = New-M365User -UserInfo $user
# Returns enriched object with Email and License properties added
```

## Key Patterns

| Pattern | Why |
|---------|-----|
| Progressive suffix algorithm | Avoids manual collision resolution at scale |
| Propagation wait-and-retry | Graph replication is eventually consistent — skipping this causes license/group failures |
| Group type detection | M365/Security vs Distribution require different APIs |
| Distribution group retry loop | Exchange mailbox provisioning lags behind Graph account creation by minutes |

## Files

| File | Description |
|------|-------------|
| `New-M365User.ps1` | Full provisioning workflow — email generation, account creation, license assignment, group membership |
