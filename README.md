# Public Scripts — Matt Dekker

Sanitized examples of production automation built while managing IT for MSP clients in the field services industry.

## Background

I'm an IT admin and MSP engineer specializing in PowerShell automation, Microsoft 365, and field service platform integrations. The scripts here are representative of real work — simplified and sanitized for public sharing, but based on production systems handling daily onboarding/offboarding across multiple tenants and platforms.

**Core stack:** PowerShell · Microsoft Graph SDK · Exchange Online · ServiceTitan API · NinjaOne RMM · Rewst · Hudu (secrets management) · Pester

---

## MSP Automation

Production-grade onboarding/offboarding automation for a multi-tenant field services environment.

### [01 — M365 Provisioning](MSP-Automation/01-M365-Provisioning/)

Full Microsoft 365 user provisioning via Graph SDK. Handles email collision avoidance, directory propagation retries, license pool selection, and multi-type group membership (M365 Groups, Security Groups, Distribution Lists).

**Highlights:** Progressive suffix email algorithm · Propagation wait-and-retry · Distribution group retry loop (Exchange Online mailbox lag)

---

### [02 — ServiceTitan Multi-Tenant](MSP-Automation/02-ServiceTitan-MultiTenant/)

Technician onboarding across 6+ ServiceTitan tenants. Scans all tenants before creation for login/phone/email/name conflicts. Inactive conflicts are auto-remediated via PATCH; active conflicts surface to the operator.

**Highlights:** Cross-tenant conflict detection · Auto-remediation of stale inactive records · Paginated API scan (500/page) · Credentials loaded dynamically from secrets manager

---

### [03 — Headless RMM Automation](MSP-Automation/03-Headless-RMM-Automation/)

The same onboarding logic re-written for headless execution via NinjaOne + Rewst. No interactive prompts — all selections arrive as parameters from a Rewst form. Output is structured JSON captured by the orchestration platform.

**Highlights:** Parameter-driven (no Read-Host/Out-GridView) · JSON stdout output · Rewst form options populated dynamically · NinjaOne-compatible error signaling

---

### [04 — TOTP / MFA Automation](MSP-Automation/04-TOTP-MFA/)

Pure PowerShell RFC 6238 TOTP implementation — no external modules. Used to generate MFA codes during automated onboarding when interactive authentication isn't possible.

**Highlights:** Base32 decode · HMAC-SHA1 · Dynamic truncation · Matches Google/Microsoft Authenticator output exactly

---

## PowerShell Portfolio Kit

General-purpose AD, DNS/DHCP, Group Policy, and security scripts.

See [PowerShell-Portfolio-Kit/](PowerShell-Portfolio-Kit/) for the full listing.

---

## Contact

- GitHub: [mdekker79](https://github.com/mdekker79)
- Email: mat@itninjas.com
