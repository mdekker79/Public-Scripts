# PowerShell Portfolio Starter Kit

A curated subset of your own scripts, pulled together as raw material for a clean, public-ready
PowerShell module. The thesis is **Active Directory security engineering** — the pieces here map
directly onto senior AD/GPO/security job requirements (ACL/ACE modeling, least-privilege analysis,
GPO, authentication hardening, DNS, PAM/secrets, and REST automation for breadth).

These are reference copies for you to rework — not finished, not yet generic.

## Before anything goes into a repo

- **Secrets:** I stripped the obvious ones (a NetBox API token, internal IPs, a file-server name,
  the Secret Server domain/host, the ServiceTitan app key, Hudu instance). Still, **re-read every
  file** before committing. Search for: real hostnames, domains, IPs, UNC paths (`\\server\share`),
  email addresses, employee/sam names, and any `password`/`token`/`secret =` assignment.
- **Provenance:** these are your own authored functions (your name/date are in the headers), but
  they were written inside former-employer environments. The clean move is to rebuild each as a
  *generic* implementation of the technique — swap company/domain names for placeholders or
  parameters, and don't carry over anything org-specific. That also removes any IP question.

## Target structure to build toward

```
PSAdminToolkit/
  PSAdminToolkit.psd1          # manifest (version, exported functions, metadata)
  PSAdminToolkit.psm1          # loader: dot-sources Public/Private at import
  Public/                      # one exported function per file
  Private/                     # internal helpers
  Tests/                       # Pester tests (one *.Tests.ps1 per function)
  .github/workflows/ci.yml     # PSScriptAnalyzer lint + Pester on push
  README.md
```

You already have a working version of this pattern in **09-Module-Template** — reuse it.

## What's in the kit (and why each earns its place)

### 01-AD-Security-ACL  — the flagship category
Maps to the "granular ACE permissions models" / least-privilege requirements.
- `Get-ACLAudit.ps1` — audits AD/OU access and exports a report. Your strongest single piece;
  make this the showcase function with full comment-based help + Pester tests.
- `Get-AclOu.ps1`, `Get-DirectoryACL.ps1` — read OU / directory ACLs.
- `Set-OwnershipAndACL.ps1`, `Set-NTFS.ps1` — set ownership and NTFS permissions.
- `Get-FolderAudit.ps1` — NTFS folder permission audit.
- *Genericize:* parameterize domain/server/credential; remove any hardcoded OU paths and shares.

### 02-AD-GroupMembership  — least-privilege analysis
- `Get-NestedGroups.ps1` — recursive nested group membership. Clean, self-contained logic —
  a great second function for demonstrating Pester (easy to mock `Get-ADGroup`).
- `Get-UserAccess.ps1`, `Get-UserAudit.ps1` — user access/audit reporting.
- `Add-NewSecurityGroup.ps1`, `Add-UsersToGroups.ps1` — group provisioning.
- *Genericize:* strip group-naming conventions tied to the old org (e.g. `RG-` prefixes).

### 03-GroupPolicy  — GPO requirement
- `Get-GpoMatchSettings.ps1` — find GPOs by setting/string. Good "GPO engineering" signal.
- `Get-GpoString.ps1` — search GPO contents.

### 04-Auth-Hardening  — threats / mitigation / authentication
- `Get-NTLMv1Audit.ps1`, `Get-SMBv1.ps1` — detect legacy protocols (textbook hardening story).
- `Get-AdUserFailedLogonInfo.ps1`, `Get-LastLogonEvent.ps1` — logon/auth failure analysis.
- `Get-LockoutPolicy.ps1` — account lockout policy.
- `Get-CertInfo.ps1` — certificate inventory.

### 05-DNS-DHCP  — DNS requirement
- `Search-DNS.ps1`, `Get-DuplicateARecords.ps1` — DNS record queries/cleanup.
- `Get-DhcpScopeOptions.ps1`, `Set-DnsScavenging.ps1` — DHCP scope / DNS scavenging.

### 06-AD-Lifecycle  — hygiene / object management
- `Invoke-AdComputerCleanup.ps1`, `Move-DisabledComputers.ps1`, `Remove-DisabledUsers.ps1`.

### 07-Secrets-PAM  — privileged access / secrets management
- `Connect-SecretServer.ps1` — Thycotic/Delinea Secret Server REST auth. Strong security signal.
- `New-ThycoticADSecret.ps1` — store an AD credential in the vault.
- *Genericize:* parameterize server/realm; never hardcode the domain prefix or a sample password;
  remove the auto-run line at the bottom of the connect function.

### 08-API-Automation  — breadth (REST API skill)
- `New-TableauProject.ps1` — Tableau Server REST (sign-in + create). Doubles as identity/permissions.
- `Get-NetBoxApi.ps1` — NetBox IPAM REST client.
- *Genericize:* token via parameter/SecretManagement, base URL as a parameter.

### 09-Module-Template  — your existing scaffold, reuse it
- `PowerShellModuleProject.psd1/.psm1/.Tests.ps1` + `build_scripts/build.ps1` — a manifest +
  loader + Pester test + build script. This is your CI/test starting point.
- `Example-AD-Module/` — a real `.psd1`/`.psm1` module with a `Functions/Public` layout to copy.

## Sanitization checklist (run on every file before commit)

- [ ] No real domains, hostnames, FQDNs, or IPs
- [ ] No UNC paths to real shares
- [ ] No credentials, tokens, API keys, or sample passwords (even commented out)
- [ ] No org-specific naming conventions or employee/sam names
- [ ] No client/employer names in comments or headers
- [ ] Inputs (server, domain, credential, base URL, token) are **parameters**, not literals
- [ ] Secrets retrieved via `Get-Secret` (SecretManagement), never inline

## Suggested order of attack

1. Stand up the module skeleton from **09-Module-Template** (rename to something like `PSAdminToolkit`).
2. Rebuild `Get-ACLAudit` as the flagship: comment-based help, `[CmdletBinding()]`, parameter
   validation, pipeline support, and a Pester test. This one function sets the quality bar.
3. Add `Get-NestedGroups` second (best for showing clean tests).
4. Fold in the rest a category at a time, writing help + a test for each as you go.
5. Add `.github/workflows/ci.yml` (PSScriptAnalyzer + Pester). Flip the repo public when it's ready.
