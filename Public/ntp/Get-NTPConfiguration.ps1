#Requires -Version 5.1

function Get-NTPConfiguration {
    <#
    .SYNOPSIS
        Retrieves the current Windows Time Service (W32Time) NTP configuration and status
    .DESCRIPTION
        This function queries the Windows Time Service using w32tm commands to retrieve
        the complete NTP configuration, including configured servers, poll intervals,
        synchronization status, peer details, and last successful sync time.

        Supports both local and remote computers. Remote queries use WinRM (Invoke-Command).
        For bulk queries, errors per computer are non-terminating to allow the pipeline
        to continue processing remaining computers.

        Returns a structured PSCustomObject with all relevant NTP configuration data
        for easy consumption by other scripts or for display purposes.
    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input.
        Defaults to the local computer ($env:COMPUTERNAME).
    .PARAMETER IncludePeerDetails
        When specified, includes detailed peer information in the output object.
        This adds verbose information about each configured NTP peer.
    .EXAMPLE
        Get-NTPConfiguration

        Retrieves the current NTP configuration for the local computer.
    .EXAMPLE
        Get-NTPConfiguration -ComputerName 'SRV01', 'SRV02'

        Retrieves NTP configuration for two remote servers.
    .EXAMPLE
        'SRV01', 'SRV02' | Get-NTPConfiguration

        Pipeline usage: queries NTP configuration on both servers.
    .EXAMPLE
        Get-NTPConfiguration -Verbose | Format-List

        Retrieves NTP configuration with verbose logging and displays all properties as a list.
    .EXAMPLE
        $ntpConfig = Get-NTPConfiguration -IncludePeerDetails
        $ntpConfig.ConfiguredServers
        $ntpConfig.PeerDetails

        Retrieves configuration with peer details and accesses specific properties.
    .OUTPUTS
    PSWinOps.NtpConfiguration
        NTP client configuration including source, type, and poll intervals.

    .NOTES
        Author:        Franck SALLET
        Version:       2.0.0
        Last Modified: 2026-03-19
        Requires:      PowerShell 5.1+, Windows Time Service (w32time)
        Permissions:   Standard user for local queries; WinRM + admin rights for remote
    
    .LINK
    https://docs.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [switch]$IncludePeerDetails
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        # Script block used for REMOTE execution only (Invoke-Command).
        # Uses full path to w32tm.exe because remote sessions don't inherit local mock context.
        $w32tmRemoteScriptBlock = {
            $w32tmPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\w32tm.exe'
            if (-not (Test-Path -Path $w32tmPath)) {
                throw "w32tm.exe not found at '$w32tmPath'"
            }
            @{
                ServiceStatus = (Get-Service -Name 'w32time' -ErrorAction Stop).Status
                Config        = & $w32tmPath /query /configuration 2>&1
                Status        = & $w32tmPath /query /status /verbose 2>&1
                Peers         = & $w32tmPath /query /peers 2>&1
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Querying '$computer'"

            try {
                $isLocal = ($computer -eq $env:COMPUTERNAME) -or
                           ($computer -eq 'localhost') -or
                           ($computer -eq '.')

                if ($isLocal) {
                    # Local execution: call commands by name so they are mockable in Pester
                    $rawData = @{
                        ServiceStatus = (Get-Service -Name 'w32time' -ErrorAction Stop).Status
                        Config        = w32tm /query /configuration 2>&1
                        Status        = w32tm /query /status /verbose 2>&1
                        Peers         = w32tm /query /peers 2>&1
                    }
                } else {
                    $rawData = Invoke-Command -ComputerName $computer `
                        -ScriptBlock $w32tmRemoteScriptBlock -ErrorAction Stop
                }

                $configOutput = $rawData.Config
                $statusOutput = $rawData.Status
                $peersOutput  = $rawData.Peers

                # Parse configuration
                $ntpServerLine = $configOutput | Select-String -Pattern 'NtpServer:\s*(.+)\s*\(.*\)' | Select-Object -First 1
                $configuredServers = if ($ntpServerLine) {
                    ($ntpServerLine.Matches.Groups[1].Value -split '\s+') | Where-Object { $_ -ne '' }
                } else {
                    @()
                }

                $typeMatch = $configOutput | Select-String -Pattern 'Type:\s*(.+)' | Select-Object -First 1
                $syncType = if ($typeMatch) { $typeMatch.Matches.Groups[1].Value.Trim() } else { 'Unknown' }

                $specialPollMatch = $configOutput | Select-String -Pattern 'SpecialPollInterval:\s*(\d+)' | Select-Object -First 1
                $specialPollInterval = if ($specialPollMatch) { [int]$specialPollMatch.Matches.Groups[1].Value } else { $null }

                $minPollMatch = $configOutput | Select-String -Pattern 'MinPollInterval:\s*(\d+)' | Select-Object -First 1
                $minPollInterval = if ($minPollMatch) { [int]$minPollMatch.Matches.Groups[1].Value } else { $null }

                $maxPollMatch = $configOutput | Select-String -Pattern 'MaxPollInterval:\s*(\d+)' | Select-Object -First 1
                $maxPollInterval = if ($maxPollMatch) { [int]$maxPollMatch.Matches.Groups[1].Value } else { $null }

                # Parse status
                $sourceMatch = $statusOutput | Select-String -Pattern 'Source:\s*(.+)' | Select-Object -First 1
                $currentSource = if ($sourceMatch) { $sourceMatch.Matches.Groups[1].Value.Trim() } else { 'Unknown' }

                $lastSyncMatch = $statusOutput | Select-String -Pattern 'Last Successful Sync Time:\s*(.+)' | Select-Object -First 1
                $lastSyncTime = if ($lastSyncMatch) { $lastSyncMatch.Matches.Groups[1].Value.Trim() } else { 'Never' }

                $stratumMatch = $statusOutput | Select-String -Pattern 'Stratum:\s*(\d+)' | Select-Object -First 1
                $stratum = if ($stratumMatch) { [int]$stratumMatch.Matches.Groups[1].Value } else { $null }

                $leapMatch = $statusOutput | Select-String -Pattern 'Leap Indicator:\s*(.+)' | Select-Object -First 1
                $leapIndicator = if ($leapMatch) { $leapMatch.Matches.Groups[1].Value.Trim() } else { 'Unknown' }

                # Build result object
                $result = [PSCustomObject]@{
                    PSTypeName          = 'PSWinOps.NtpConfiguration'
                    ComputerName        = $computer
                    ServiceName         = 'w32time'
                    ServiceStatus       = $rawData.ServiceStatus
                    SyncType            = $syncType
                    ConfiguredServers   = $configuredServers
                    CurrentSource       = $currentSource
                    LastSuccessfulSync  = $lastSyncTime
                    Stratum             = $stratum
                    LeapIndicator       = $leapIndicator
                    SpecialPollInterval = $specialPollInterval
                    MinPollInterval     = $minPollInterval
                    MaxPollInterval     = $maxPollInterval
                    MinPollIntervalSec  = if ($minPollInterval) { [math]::Pow(2, $minPollInterval) } else { $null }
                    MaxPollIntervalSec  = if ($maxPollInterval) { [math]::Pow(2, $maxPollInterval) } else { $null }
                    Timestamp           = Get-Date -Format 'o'
                }

                # Add peer details if requested
                if ($IncludePeerDetails) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Including peer details for '$computer'"
                    $result | Add-Member -MemberType NoteProperty -Name 'PeerDetails' -Value ($peersOutput -join "`n")
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Configuration retrieved successfully for '$computer'"
                $result

            } catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
                Write-Error "[$($MyInvocation.MyCommand)] Windows Time Service not found on '$computer': $_"
                continue
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to retrieve NTP configuration from '$computer': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
