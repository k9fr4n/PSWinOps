#Requires -Version 5.1

function Get-RandomPassword {
    <#
.SYNOPSIS
    Generate a cryptographically secure random password

.DESCRIPTION
    Generates a random password using RNGCryptoServiceProvider with configurable
    character class requirements. Ensures minimum counts for uppercase, lowercase,
    numeric, and special characters are met. Uses iterative regeneration with a
    retry limit to prevent infinite loops.

.PARAMETER Length
    Total length of the password. Must be at least 8 characters.
    Default: 16

.PARAMETER UpperCount
    Minimum number of uppercase letters (A-Z) required.
    Default: 2

.PARAMETER LowerCount
    Minimum number of lowercase letters (a-z) required.
    Default: 2

.PARAMETER NumericCount
    Minimum number of digits (0-9) required.
    Default: 2

.PARAMETER SpecialCount
    Minimum number of special characters required.
    Default: 2
    Character set: @.+-=*!#$%&?

.PARAMETER MaxRetries
    Maximum number of regeneration attempts if constraints are not met.
    Default: 100

.EXAMPLE
    Get-RandomPassword

    Generates a 16-character password with default constraints (2 upper, 2 lower, 2 numeric, 2 special).

.EXAMPLE
    Get-RandomPassword -Length 24 -UpperCount 4 -LowerCount 4 -NumericCount 4 -SpecialCount 4

    Generates a 24-character password with higher complexity requirements.

.EXAMPLE
    1..5 | ForEach-Object { Get-RandomPassword -Length 20 }

    Generates 5 unique passwords with 20 characters each.

.NOTES
    Author:        PSWinOps Module
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+
    Permissions:   None required
    Module:        PSWinOps

    Uses System.Security.Cryptography.RNGCryptoServiceProvider for
    cryptographically secure random number generation.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(8, [int]::MaxValue)]
        [int]$Length = 16,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$UpperCount = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$LowerCount = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$NumericCount = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$SpecialCount = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$MaxRetries = 100
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting password generation"

        # Character sets
        $upperCharSet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $lowerCharSet = 'abcdefghijklmnopqrstuvwxyz'
        $numericCharSet = '0123456789'
        $specialCharSet = '@.+-=*!#$%&?'

        # Validate total constraints do not exceed length
        $totalRequired = $UpperCount + $LowerCount + $NumericCount + $SpecialCount
        if ($totalRequired -gt $Length) {
            throw "[$($MyInvocation.MyCommand)] Sum of character class minimums ($totalRequired) exceeds password length ($Length)"
        }

        # Build combined character set based on required counts
        $charSetBuilder = [System.Text.StringBuilder]::new()
        if ($UpperCount -gt 0) {
            [void]$charSetBuilder.Append($upperCharSet)
        }
        if ($LowerCount -gt 0) {
            [void]$charSetBuilder.Append($lowerCharSet)
        }
        if ($NumericCount -gt 0) {
            [void]$charSetBuilder.Append($numericCharSet)
        }
        if ($SpecialCount -gt 0) {
            [void]$charSetBuilder.Append($specialCharSet)
        }

        $charSet = $charSetBuilder.ToString().ToCharArray()

        if ($charSet.Count -eq 0) {
            throw "[$($MyInvocation.MyCommand)] At least one character class must have a count greater than zero"
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Character set size: $($charSet.Count)"
        Write-Verbose "[$($MyInvocation.MyCommand)] Required -- Upper: $UpperCount, Lower: $LowerCount, Numeric: $NumericCount, Special: $SpecialCount"
    }

    process {
        $rng = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
        $attempt = 0
        $passwordGenerated = $false

        try {
            while (-not $passwordGenerated -and $attempt -lt $MaxRetries) {
                $attempt++
                Write-Verbose "[$($MyInvocation.MyCommand)] Generation attempt: $attempt"

                # Generate random bytes
                $bytes = New-Object -TypeName 'byte[]' -ArgumentList $Length
                $rng.GetBytes($bytes)

                # Map bytes to character set
                $result = New-Object -TypeName 'char[]' -ArgumentList $Length
                for ($i = 0; $i -lt $Length; $i++) {
                    $result[$i] = $charSet[$bytes[$i] % $charSet.Count]
                }

                $password = -join $result

                # Validate constraints
                $upperActual = ($password.ToCharArray() | Where-Object { $_ -cin $upperCharSet.ToCharArray() }).Count
                $lowerActual = ($password.ToCharArray() | Where-Object { $_ -cin $lowerCharSet.ToCharArray() }).Count
                $numericActual = ($password.ToCharArray() | Where-Object { $_ -cin $numericCharSet.ToCharArray() }).Count
                $specialActual = ($password.ToCharArray() | Where-Object { $_ -cin $specialCharSet.ToCharArray() }).Count

                $valid = $true
                if ($UpperCount -gt $upperActual) {
                    $valid = $false; Write-Verbose "[$($MyInvocation.MyCommand)] Insufficient uppercase: $upperActual (need $UpperCount)"
                }
                if ($LowerCount -gt $lowerActual) {
                    $valid = $false; Write-Verbose "[$($MyInvocation.MyCommand)] Insufficient lowercase: $lowerActual (need $LowerCount)"
                }
                if ($NumericCount -gt $numericActual) {
                    $valid = $false; Write-Verbose "[$($MyInvocation.MyCommand)] Insufficient numeric: $numericActual (need $NumericCount)"
                }
                if ($SpecialCount -gt $specialActual) {
                    $valid = $false; Write-Verbose "[$($MyInvocation.MyCommand)] Insufficient special: $specialActual (need $SpecialCount)"
                }

                if ($valid) {
                    $passwordGenerated = $true
                    Write-Verbose "[$($MyInvocation.MyCommand)] Password generated successfully on attempt $attempt"
                    return $password
                }
            }

            # Max retries exceeded
            Write-Error "[$($MyInvocation.MyCommand)] Failed to generate valid password after $MaxRetries attempts. Consider adjusting constraints."
            throw "[$($MyInvocation.MyCommand)] Password generation failed -- constraints may be too restrictive for the specified length"
        } finally {
            if ($null -ne $rng) {
                $rng.Dispose()
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
