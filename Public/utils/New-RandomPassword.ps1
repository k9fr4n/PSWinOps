#Requires -Version 5.1

function New-RandomPassword {
    <#
        .SYNOPSIS
            Generate a cryptographically secure random password

        .DESCRIPTION
            Generates a random password using RandomNumberGenerator with configurable
            character class requirements. Ensures minimum counts for uppercase, lowercase,
            numeric, and special characters are met by guaranteeing placement of required
            characters followed by cryptographically secure shuffling.

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

        .EXAMPLE
            New-RandomPassword
            Generates a 16-character password with default constraints (2 upper, 2 lower, 2 numeric, 2 special).

        .EXAMPLE
            New-RandomPassword -Length 24 -UpperCount 4 -LowerCount 4 -NumericCount 4 -SpecialCount 4
            Generates a 24-character password with higher complexity requirements.

        .EXAMPLE
            1..5 | ForEach-Object { New-RandomPassword -Length 20 }
            Generates 5 unique passwords with 20 characters each.

        .OUTPUTS
            System.String
            A randomly generated password string.

        .NOTES
            Author:        Franck SALLET
            Version:       1.1.0
            Last Modified: 2026-03-11
            Requires:      PowerShell 5.1+
            Permissions:   None required
            Module:        PSWinOps

            Uses System.Security.Cryptography.RandomNumberGenerator for
            cryptographically secure random number generation. Uses the factory
            method RandomNumberGenerator.Create() which is compatible with both
            .NET Framework (PS 5.1) and .NET 6+ (PS 7.2+) without deprecation
            warnings. Guarantees constraint
            satisfaction by placing required characters first, then shuffling.

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.rngcryptoserviceprovider
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'New-RandomPassword generates a string in memory, it does not change system state')]
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
        [int]$SpecialCount = 2
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
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new(
                        "Sum of character class minimums ($totalRequired) exceeds password length ($Length)"
                    ),
                    'PasswordConstraintExceedsLength',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $Length
                )
            )
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
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new(
                        'At least one character class must have a count greater than zero'
                    ),
                    'NoCharacterClassSelected',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $null
                )
            )
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Character set size: $($charSet.Count)"
        Write-Verbose "[$($MyInvocation.MyCommand)] Required -- Upper: $UpperCount, Lower: $LowerCount, Numeric: $NumericCount, Special: $SpecialCount"
    }

    process {
        $rng = $null
        try {
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

            # Build password array
            $passwordChars = [System.Collections.Generic.List[char]]::new()

            # Helper function to get cryptographically random index
            # Uses rejection sampling to eliminate modulo bias (NIST SP 800-90A Rev.1 §A.5.1)
            $getRandomIndex = {
                param([int]$maxValue)
                $bytes = [byte[]]::new(4)
                # Largest uint32 multiple of $maxValue (rejection-sampling upper bound)
                $limit = [uint32]([math]::Floor([uint32]::MaxValue / $maxValue) * $maxValue)
                while ($true) {
                    $rng.GetBytes($bytes)
                    $r = [System.BitConverter]::ToUInt32($bytes, 0)
                    if ($r -lt $limit) { return [int]($r % $maxValue) }
                }
            }

            # Add required uppercase characters
            for ($i = 0; $i -lt $UpperCount; $i++) {
                $index = & $getRandomIndex $upperCharSet.Length
                $passwordChars.Add($upperCharSet[$index])
            }

            # Add required lowercase characters
            for ($i = 0; $i -lt $LowerCount; $i++) {
                $index = & $getRandomIndex $lowerCharSet.Length
                $passwordChars.Add($lowerCharSet[$index])
            }

            # Add required numeric characters
            for ($i = 0; $i -lt $NumericCount; $i++) {
                $index = & $getRandomIndex $numericCharSet.Length
                $passwordChars.Add($numericCharSet[$index])
            }

            # Add required special characters
            for ($i = 0; $i -lt $SpecialCount; $i++) {
                $index = & $getRandomIndex $specialCharSet.Length
                $passwordChars.Add($specialCharSet[$index])
            }

            # Fill remaining positions with random characters from full character set
            $remaining = $Length - $totalRequired
            for ($i = 0; $i -lt $remaining; $i++) {
                $index = & $getRandomIndex $charSet.Count
                $passwordChars.Add($charSet[$index])
            }

            Write-Verbose "[$($MyInvocation.MyCommand)] Generated $($passwordChars.Count) characters before shuffle"

            # Fisher-Yates shuffle using cryptographic RNG
            for ($i = $passwordChars.Count - 1; $i -gt 0; $i--) {
                $j = & $getRandomIndex ($i + 1)
                $temp = $passwordChars[$i]
                $passwordChars[$i] = $passwordChars[$j]
                $passwordChars[$j] = $temp
            }

            $password = -join $passwordChars.ToArray()

            Write-Verbose "[$($MyInvocation.MyCommand)] Password generated successfully (length: $($password.Length))"

            return $password

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
