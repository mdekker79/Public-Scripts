function Get-TOTP {
    <#
    .SYNOPSIS
        Generates a RFC 6238 Time-Based One-Time Password (TOTP) from a Base32 secret.
    .DESCRIPTION
        Pure PowerShell implementation of the TOTP algorithm (RFC 6238).
        Decodes a Base32 secret, computes HMAC-SHA1 over the current 30-second
        time step, and applies dynamic truncation to produce a 6-digit code.

        Used in MSP automation to programmatically obtain MFA codes for service
        accounts where interactive login is not possible (e.g. RMM-driven scripts,
        headless onboarding workflows).
    .PARAMETER Secret
        Base32-encoded TOTP secret from the authenticator app setup.
    .OUTPUTS
        String — 6-digit TOTP code, zero-padded.
    .EXAMPLE
        Get-TOTP -Secret "JBSWY3DPEHPK3PXP"
        # Returns current 6-digit code for that secret
    .NOTES
        Algorithm: RFC 6238 (TOTP) / RFC 4226 (HOTP)
        Hash:      HMAC-SHA1
        Step:      30 seconds
        Digits:    6
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Secret
    )

    # ── Base32 decode ────────────────────────────────────────────────────────────
    $base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $clean = $Secret.ToUpper() -replace '[^A-Z2-7]', ''
    $bits  = -join ($clean.ToCharArray() | ForEach-Object {
        [Convert]::ToString($base32Chars.IndexOf($_), 2).PadLeft(5, '0')
    })
    $keyBytes = [byte[]]@(
        for ($i = 0; $i -lt ($bits.Length - 7); $i += 8) {
            [Convert]::ToByte($bits.Substring($i, 8), 2)
        }
    )

    # ── Current 30-second time step as big-endian 8-byte array ──────────────────
    $timeStep  = [Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30)
    $stepBytes = [BitConverter]::GetBytes([int64]$timeStep)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($stepBytes) }

    # ── HMAC-SHA1 ────────────────────────────────────────────────────────────────
    $hmac = [System.Security.Cryptography.HMACSHA1]::new($keyBytes)
    $hash = $hmac.ComputeHash($stepBytes)
    $hmac.Dispose()

    # ── Dynamic truncation → 6-digit code ───────────────────────────────────────
    $offset = $hash[19] -band 0x0F
    $code   = (($hash[$offset]     -band 0x7F) -shl 24) -bor
              (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
              (($hash[$offset + 2] -band 0xFF) -shl 8)  -bor
               ($hash[$offset + 3] -band 0xFF)

    return ($code % 1000000).ToString('000000')
}
