#Requires -Version 5.1

function Get-ComputerUptime {
    <#
    .SYNOPSIS
        Retrieves system uptime for one or more Windows computers.
    .DESCRIPTION
        Queries Win32_OperatingSystem via CIM to retrieve the last boot time and
        calculates the current uptime for each target machine. Uses direct CIM queries
        for local machines and CimSession-based queries for remote machines, with
        optional credential support for remote authentication.

        Unlike the built-in Get-Uptime cmdlet (PowerShell 6.1+), this function
        supports remote computers, credentials, pipeline input, and structured output
        with UptimeDays for sorting/filtering.
    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input by value and
        by property name. Defaults to the local machine ($env:COMPUTERNAME).
    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries. Use Get-Credential or SecretManagement to obtain.
    .EXAMPLE
        Get-ComputerUptime

        Returns uptime information for the local machine using a direct CIM query.
    .EXAMPLE
        Get-ComputerUptime -ComputerName 'SRV01', 'SRV02'

        Returns uptime information for two remote servers via CimSession.
    .EXAMPLE
        'SRV01', 'SRV02' | Get-ComputerUptime -Credential (Get-Credential)

        Queries multiple servers via pipeline with explicit credentials.
    .NOTES
        Author:        PSWinOps
        Version:       1.0.0
        Last Modified: 2026-03-15
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   No admin required for reading uptime
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting uptime query"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
    }

    process {
        foreach ($machine in $ComputerName) {
            $cimSession = $null
            try {
                $isLocal = $localNames -contains $machine

                if ($isLocal) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Querying local machine: $machine"
                    $osInfo = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
                }
                else {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Querying remote machine: $machine"
                    $sessionParams = @{
                        ComputerName = $machine
                        ErrorAction  = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $sessionParams['Credential'] = $Credential
                    }
                    $cimSession = New-CimSession @sessionParams
                    $osInfo = Get-CimInstance -ClassName 'Win32_OperatingSystem' -CimSession $cimSession -ErrorAction Stop
                }

                $lastBoot = $osInfo.LastBootUpTime
                $uptime = (Get-Date) - $lastBoot
                $uptimeDisplay = '{0} days, {1} hours, {2} minutes' -f $uptime.Days, $uptime.Hours, $uptime.Minutes

                [PSCustomObject]@{
                    ComputerName  = $machine
                    LastBootTime  = $lastBoot
                    Uptime        = $uptime
                    UptimeDays    = [math]::Round($uptime.TotalDays, 4)
                    UptimeDisplay = $uptimeDisplay
                    Timestamp     = Get-Date -Format 'o'
                }
            }
            catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query '${machine}': $_"
            }
            finally {
                if ($null -ne $cimSession) {
                    Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
                    Write-Verbose "[$($MyInvocation.MyCommand)] Cleaned up CimSession for: $machine"
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed uptime query"
    }
}