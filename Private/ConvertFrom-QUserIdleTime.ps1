#Requires -Version 5.1

function ConvertFrom-QUserIdleTime {
    <#
.SYNOPSIS
    Converts a quser idle time string into a TimeSpan object

.DESCRIPTION
    Parses the variable-format idle time string produced by quser.exe into a
    .NET TimeSpan for programmatic comparison and filtering. Handles all
    documented quser idle time representations: dot (active session), none,
    integer minutes, H:MM format, and D+H:MM format. Returns TimeSpan.Zero
    for active or unrecognised input.

.PARAMETER IdleTimeString
    The raw idle time value extracted from a quser output line.
    Valid inputs: '.', 'none', an integer string (minutes), 'H:MM', 'D+H:MM'.
    An empty or whitespace-only string is treated as zero idle time.

.EXAMPLE
    ConvertFrom-QUserIdleTime -IdleTimeString '.'
    Returns [TimeSpan]::Zero -- session is currently in active use (no idle time).

.EXAMPLE
    ConvertFrom-QUserIdleTime -IdleTimeString '1+08:15'
    Returns a TimeSpan of 1 day, 8 hours, and 15 minutes of idle time.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+
    Permissions:   None -- pure in-memory string parsing, no system calls
#>
    [CmdletBinding()]
    [OutputType([TimeSpan])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$IdleTimeString
    )

    process {
        if ([string]::IsNullOrWhiteSpace($IdleTimeString) -or
            $IdleTimeString -eq '.' -or
            $IdleTimeString -eq 'none') {
            return [TimeSpan]::Zero
        }

        # Format: D+H:MM -- e.g., "1+08:15"
        if ($IdleTimeString -match '^(?<d>\d+)\+(?<h>\d+):(?<m>\d+)
) {
            return [TimeSpan]::new([int]$Matches['d'], [int]$Matches['h'], [int]$Matches['m'], 0)
        }

        # Format: H:MM -- e.g., "8:05"
        if ($IdleTimeString -match '^(?<h>\d+):(?<m>\d+)
) {
            return [TimeSpan]::new([int]$Matches['h'], [int]$Matches['m'], 0)
        }

        # Format: minutes only -- e.g., "5"
        if ($IdleTimeString -match '^\d+
) {
            return [TimeSpan]::FromMinutes([int]$IdleTimeString)
        }

        return [TimeSpan]::Zero
    }
}
