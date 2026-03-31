#Requires -Version 5.1

function Get-ComputerUptime {
    <#
        .SYNOPSIS
            Retrieves system uptime for one or more Windows computers

        .DESCRIPTION
            Queries Win32_OperatingSystem via CIM to retrieve the last boot time and
            calculates the current uptime for each target machine. Uses direct CIM queries
            for the local machine and CIM remoting (-ComputerName) for remote machines.

            When the -Credential parameter is specified, a temporary CimSession is created
            for authentication and automatically cleaned up after use.

            Unlike the built-in Get-Uptime cmdlet (PowerShell 6.1+), this function
            supports remote computers, credentials, pipeline input, and structured output
            with UptimeDays for sorting/filtering.

        .PARAMETER ComputerName
            One or more computer names to query. Accepts pipeline input by value and
            by property name. Defaults to the local machine ($env:COMPUTERNAME).

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote machines. Ignored for
            local machine queries. When specified, a temporary CimSession is created.

        .EXAMPLE
            Get-ComputerUptime

            Returns uptime information for the local machine using a direct CIM query.

        .EXAMPLE
            Get-ComputerUptime -ComputerName 'SRV01', 'SRV02'

            Returns uptime information for two remote servers via CIM remoting.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ComputerUptime -Credential (Get-Credential)

            Queries multiple servers via pipeline with explicit credentials.

        .OUTPUTS
            PSWinOps.ComputerUptime
            Uptime details including last boot time and duration.

        .NOTES
            Author:        Franck SALLET
            Version:       1.2.0
            Last Modified: 2026-03-15
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required for reading uptime
            Remote:        Requires WinRM / WS-Man enabled on target machines

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ComputerUptime')]
    param(
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting uptime query"

        $scriptBlock = {
            $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
            $os.LastBootUpTime
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying uptime on '$machine'"
                $lastBoot = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential
                $uptime = (Get-Date) - $lastBoot
                $uptimeDisplay = '{0} days, {1} hours, {2} minutes' -f $uptime.Days, $uptime.Hours, $uptime.Minutes

                [PSCustomObject]@{
                    PSTypeName    = 'PSWinOps.ComputerUptime'
                    ComputerName  = $machine
                    LastBootTime  = $lastBoot
                    Uptime        = $uptime
                    UptimeDays    = [math]::Round($uptime.TotalDays, 4)
                    UptimeDisplay = $uptimeDisplay
                    Timestamp     = Get-Date -Format 'o'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query '${machine}': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed uptime query"
    }
}
