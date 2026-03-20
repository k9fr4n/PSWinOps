#Requires -Version 5.1

function Get-RdpSessionHistory {
    <#
.SYNOPSIS
    Retrieves Remote Desktop Protocol (RDP) session history from Windows Event Log

.DESCRIPTION
    Queries the Microsoft-Windows-TerminalServices-LocalSessionManager/Operational
    event log on one or more computers to retrieve RDP session logon, logoff,
    disconnect, and reconnection events. Returns structured objects with user,
    IP address, and action details.

    The function filters events by ID:
    - 21: Logon
    - 23: Logoff
    - 24: Disconnected
    - 25: Reconnection

.PARAMETER ComputerName
    One or more computer names to query. Defaults to the local machine.
    Supports pipeline input by value and by property name.

.PARAMETER StartTime
    The earliest event timestamp to retrieve. Events older than this time
    are excluded from results. Defaults to January 1, 1970 (Unix epoch).

.PARAMETER Credential
    Credential to use when querying remote computers. If not specified,
    uses the current user's credentials.

.EXAMPLE
    Get-RdpSessionHistory

    Retrieves all RDP session events from the local computer since January 1, 1970.

.EXAMPLE
    Get-RdpSessionHistory -ComputerName 'SRV01', 'SRV02' -StartTime (Get-Date).AddDays(-7)

    Retrieves RDP session history from SRV01 and SRV02 for the last 7 days.

.EXAMPLE
    'WEB01', 'APP01' | Get-RdpSessionHistory -Credential $cred

    Pipeline example: queries multiple servers using specified credentials.

.EXAMPLE
    Get-ADComputer -Filter "OperatingSystem -like '*Server*'" | Get-RdpSessionHistory -StartTime (Get-Date).AddHours(-24)

    Retrieves last 24 hours of RDP session events from all domain servers.

.EXAMPLE
    Get-RdpSessionHistory -StartTime (Get-Date).AddDays(-30) | Where-Object { $_.Action -eq 'Logon' } | Group-Object -Property User

    Retrieves last 30 days of RDP logon events and groups them by user.

.NOTES
    Author:        Franck SALLET
    Version:       1.1.0
    Last Modified: 2026-03-19
    Requires:      PowerShell 5.1+
    Permissions:   Remote Event Log Readers group or local Administrator on target machines

.LINK
    https://docs.microsoft.com/en-us/windows/win32/termserv/terminal-services-events
#>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [datetime]$StartTime = [datetime]'1970-01-01',

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        # Event ID to Action mapping
        $eventActionMap = @{
            21 = 'Logon'
            23 = 'Logoff'
            24 = 'Disconnected'
            25 = 'Reconnection'
        }

        # Filter configuration
        $logFilter = @{
            LogName   = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
            ID        = 21, 23, 24, 25
            StartTime = $StartTime
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Querying events since: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing: $computer"

            # Build Get-WinEvent parameters
            $winEventParams = @{
                FilterHashtable = $logFilter
                ComputerName    = $computer
                ErrorAction     = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Credential')) {
                $winEventParams['Credential'] = $Credential
            }

            try {
                # Query events from target computer
                $allEvents = Get-WinEvent @winEventParams

                if ($null -eq $allEvents -or $allEvents.Count -eq 0) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] No events found on $computer"
                    continue
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Retrieved $($allEvents.Count) event(s) from $computer"

                # Process each event
                foreach ($eventEntry in $allEvents) {
                    try {
                        $eventXml = [xml]$eventEntry.ToXml()
                        $eventData = $eventXml.Event.UserData.EventXML

                        # Emit structured object
                        [PSCustomObject]@{
                            PSTypeName   = 'PSWinOps.RdpSessionHistory'
                            TimeCreated  = $eventEntry.TimeCreated
                            ComputerName = $computer
                            User         = $eventData.User
                            IPAddress    = $eventData.Address
                            Action       = $eventActionMap[[int]$eventEntry.Id]
                            EventID      = $eventEntry.Id
                            Timestamp    = Get-Date -Format 'o'
                        }
                    } catch {
                        Write-Warning "[$($MyInvocation.MyCommand)] Failed to parse event ID $($eventEntry.Id) on $computer - $_"
                    }
                }
            } catch [System.Diagnostics.Eventing.Reader.EventLogException] {
                Write-Error "[$($MyInvocation.MyCommand)] Event log error on $computer - $_"
            } catch [System.UnauthorizedAccessException] {
                Write-Error "[$($MyInvocation.MyCommand)] Access denied to $computer - Requires Event Log Readers permissions"
            } catch [System.Exception] {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query $computer - $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
