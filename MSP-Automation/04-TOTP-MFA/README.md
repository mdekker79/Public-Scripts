# 04 — TOTP / MFA Automation

## Problem

In MSP environments, service accounts for multi-tenant platforms (e.g. field service software) require MFA. When onboarding automation runs headlessly via an RMM platform, there's no human available to read an authenticator app — the script needs to generate the code itself.

## Solution

A pure PowerShell implementation of RFC 6238 TOTP — no external modules, no dependencies. The secret is retrieved from a secrets manager (Hudu) at runtime and the 6-digit code is generated on the fly.

## How It Works

1. Base32-decode the secret from the authenticator setup
2. Compute the current 30-second time step as a big-endian 8-byte integer
3. Run HMAC-SHA1 over the time step using the decoded key
4. Apply dynamic truncation to extract a 4-byte slice
5. Mod 1,000,000 → zero-pad to 6 digits

This matches exactly what Google Authenticator, Microsoft Authenticator, and Authy produce.

## Usage

```powershell
# Secret stored in secrets manager, retrieved at runtime
$secret = Get-SecretFromVault -Name "ServiceAccount-MFA"
$code   = Get-TOTP -Secret $secret

# Use the code in automation
Submit-MfaCode -Code $code
```

## Real-World Context

Used in a multi-tenant field service onboarding workflow. After creating a new technician account via API, the script automatically:
1. Retrieves the admin TOTP secret from Hudu
2. Generates the current MFA code
3. Opens a browser session pre-filled with credentials + OTP
4. Prompts the operator to complete MFA enrollment for the new user

This eliminates manual authentication during automated onboarding runs.

## Files

| File | Description |
|------|-------------|
| `Get-TOTP.ps1` | RFC 6238 TOTP implementation — Base32 decode, HMAC-SHA1, dynamic truncation |
