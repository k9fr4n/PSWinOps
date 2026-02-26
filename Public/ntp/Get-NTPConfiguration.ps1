#Requires -Version 5.1

function Get-NTPConfiguration {
    <#
.SYNOPSIS
    Retrieves the current Windows Time Service (W32Time) NTP configuration and status

.DESCRIPTION
    This function queries the Windows Time Service using w32tm commands to retrieve
    the complete NTP configuration, including configured servers, poll intervals,
    synchronization status, peer details, and last successful sync time.

    Returns a structured PSCustomObject with all relevant NTP configuration data
    for easy consumption by other scripts or for display purposes.

.PARAMETER IncludePeerDetails
    When specified, includes detailed peer information in the output object.
    This adds verbose information about each configured NTP peer.

.EXAMPLE
    Get-NTPConfiguration

    Retrieves the current NTP configuration and displays it as a structured object.

.EXAMPLE
    Get-NTPConfiguration -Verbose | Format-List

    Retrieves NTP configuration with verbose logging and displays all properties as a list.

.EXAMPLE
    $ntpConfig = Get-NTPConfiguration -IncludePeerDetails
    $ntpConfig.ConfiguredServers
    $ntpConfig.Peers

    Retrieves configuration with peer details and accesses specific properties.

.NOTES
    Author:        Ecritel IT Team
    Version:       1.0.0
    Last Modified: 2026-02-20
    Requires:      PowerShell 5.1+, Windows Time Service (w32time)
    Permissions:   Standard user rights (no elevation required for read-only operations)
#>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncludePeerDetails
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"
        $ErrorActionPreference = 'Stop'
    }

    process {
        try {
            # Verify W32Time service exists
            Write-Verbose "[$($MyInvocation.MyCommand)] Checking Windows Time Service..."
            $service = Get-Service -Name 'w32time' -ErrorAction Stop
            Write-Verbose "[$($MyInvocation.MyCommand)] Service status: $($service.Status)"

            # Query configuration
            Write-Verbose "[$($MyInvocation.MyCommand)] Querying w32tm configuration..."
            $configOutput = w32tm /query /configuration 2>&1

            # Query status
            Write-Verbose "[$($MyInvocation.MyCommand)] Querying w32tm status..."
            $statusOutput = w32tm /query /status /verbose 2>&1

            # Query peers
            Write-Verbose "[$($MyInvocation.MyCommand)] Querying w32tm peers..."
            $peersOutput = w32tm /query /peers 2>&1

            # Parse configuration
            $ntpServerLine = $configOutput | Select-String -Pattern 'NtpServer:\s*(.+)\s*\(.*\)' | Select-Object -First 1
            $configuredServers = if ($ntpServerLine) {
                ($ntpServerLine.Matches.Groups[1].Value -split '\s+') | Where-Object { $_ -ne '' }
            } else {
                @()
            }

            $typeMatch = $configOutput | Select-String -Pattern 'Type:\s*(.+)' | Select-Object -First 1
            $syncType = if ($typeMatch) {
                $typeMatch.Matches.Groups[1].Value.Trim()
            } else {
                'Unknown'
            }

            # Parse registry values from configuration output
            $specialPollMatch = $configOutput | Select-String -Pattern 'SpecialPollInterval:\s*(\d+)' | Select-Object -First 1
            $specialPollInterval = if ($specialPollMatch) {
                [int]$specialPollMatch.Matches.Groups[1].Value
            } else {
                $null
            }

            $minPollMatch = $configOutput | Select-String -Pattern 'MinPollInterval:\s*(\d+)' | Select-Object -First 1
            $minPollInterval = if ($minPollMatch) {
                [int]$minPollMatch.Matches.Groups[1].Value
            } else {
                $null
            }

            $maxPollMatch = $configOutput | Select-String -Pattern 'MaxPollInterval:\s*(\d+)' | Select-Object -First 1
            $maxPollInterval = if ($maxPollMatch) {
                [int]$maxPollMatch.Matches.Groups[1].Value
            } else {
                $null
            }

            # Parse status
            $sourceMatch = $statusOutput | Select-String -Pattern 'Source:\s*(.+)' | Select-Object -First 1
            $currentSource = if ($sourceMatch) {
                $sourceMatch.Matches.Groups[1].Value.Trim()
            } else {
                'Unknown'
            }

            $lastSyncMatch = $statusOutput | Select-String -Pattern 'Last Successful Sync Time:\s*(.+)' | Select-Object -First 1
            $lastSyncTime = if ($lastSyncMatch) {
                $lastSyncMatch.Matches.Groups[1].Value.Trim()
            } else {
                'Never'
            }

            $stratumMatch = $statusOutput | Select-String -Pattern 'Stratum:\s*(\d+)' | Select-Object -First 1
            $stratum = if ($stratumMatch) {
                [int]$stratumMatch.Matches.Groups[1].Value
            } else {
                $null
            }

            # Parse leap indicator
            $leapMatch = $statusOutput | Select-String -Pattern 'Leap Indicator:\s*(.+)' | Select-Object -First 1
            $leapIndicator = if ($leapMatch) {
                $leapMatch.Matches.Groups[1].Value.Trim()
            } else {
                'Unknown'
            }

            # Build result object
            $result = [PSCustomObject]@{
                ServiceName         = 'w32time'
                ServiceStatus       = $service.Status
                SyncType            = $syncType
                ConfiguredServers   = $configuredServers
                CurrentSource       = $currentSource
                LastSuccessfulSync  = $lastSyncTime
                Stratum             = $stratum
                LeapIndicator       = $leapIndicator
                SpecialPollInterval = $specialPollInterval
                MinPollInterval     = $minPollInterval
                MaxPollInterval     = $maxPollInterval
                MinPollIntervalSec  = if ($minPollInterval) {
                    [math]::Pow(2, $minPollInterval)
                } else {
                    $null
                }
                MaxPollIntervalSec  = if ($maxPollInterval) {
                    [math]::Pow(2, $maxPollInterval)
                } else {
                    $null
                }
                QueryTimestamp      = Get-Date -Format 'o'
            }

            # Add peer details if requested
            if ($IncludePeerDetails) {
                Write-Verbose "[$($MyInvocation.MyCommand)] Including peer details in output"
                $result | Add-Member -MemberType NoteProperty -Name 'PeerDetails' -Value ($peersOutput -join "`n")
            }

            Write-Verbose "[$($MyInvocation.MyCommand)] Configuration retrieved successfully"
            return $result
        } catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            Write-Error "[$($MyInvocation.MyCommand)] Windows Time Service not found or inaccessible: $_"
            throw
        } catch {
            Write-Error "[$($MyInvocation.MyCommand)] Failed to retrieve NTP configuration: $_"
            throw
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
