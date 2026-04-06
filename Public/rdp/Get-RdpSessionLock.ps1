#Requires -Version 5.1

function Get-RdpSessionLock {
    <#
        .SYNOPSIS
            Retrieves RDP session lock and unlock event history from Windows Event Log

        .DESCRIPTION
            Queries the Microsoft-Windows-TerminalServices-LocalSessionManager/Operational
            and Security event logs on one or more computers to retrieve session lock
            (workstation lock) and unlock events for RDP sessions. Returns structured
            objects with user, timestamp, and lock/unlock action details.

            The function filters events by ID:
            - Event 4800 (Security): Workstation was locked
            - Event 4801 (Security): Workstation was unlocked

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Supports pipeline input by value and by property name.

        .PARAMETER StartTime
            The earliest event timestamp to retrieve. Events older than this time
            are excluded from results. Defaults to 7 days ago.

        .PARAMETER Credential
            Credential to use when querying remote computers. If not specified,
            uses the current user's credentials.

        .EXAMPLE
            Get-RdpSessionLock
            Retrieves all RDP session lock/unlock events from the local computer for the last 7 days.

        .EXAMPLE
            Get-RdpSessionLock -ComputerName 'SRV01' -StartTime (Get-Date).AddDays(-30)
            Retrieves 30 days of lock/unlock history from SRV01.

        .EXAMPLE
            $cred = Get-Credential -UserName 'DOMAIN\admin'
            'WEB01', 'APP01' | Get-RdpSessionLock -Credential $cred | Where-Object { $_.Action -eq 'Locked' }

            Pipeline example: retrieves only lock events (not unlocks) from multiple servers
            using alternate credentials.

        .EXAMPLE
            Get-ADComputer -Filter "OperatingSystem -like '*Server*'" | Get-RdpSessionLock -StartTime (Get-Date).AddHours(-24) | Group-Object -Property UserName
            Retrieves last 24 hours of lock events from all domain servers and groups by user.

        .OUTPUTS
            PSWinOps.RdpSessionLock
            Session lock and unlock events with timestamps.

        .NOTES
            Author:        Franck SALLET
            Version:       1.1.1
            Last Modified: 2026-04-02
            Requires:      PowerShell 5.1+
            Permissions:   Event Log Readers group or local Administrator on target machines
            Note:          Security log access requires elevated permissions

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4800
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.RdpSessionLock')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [datetime]$StartTime = (Get-Date).AddDays(-7),

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        # Event ID to Action mapping
        $lockActionMap = @{
            4800 = 'Locked'
            4801 = 'Unlocked'
        }

        # Filter configuration for Security log
        $securityFilter = @{
            LogName   = 'Security'
            ID        = 4800, 4801
            StartTime = $StartTime
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Querying events since: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing: $computer"

            # Build Get-WinEvent parameters
            $winEventParams = @{
                FilterHashtable = $securityFilter
                ComputerName    = $computer
                ErrorAction     = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Credential')) {
                $winEventParams['Credential'] = $Credential
            }

            try {
                # Query events from target computer
                $lockEvents = Get-WinEvent @winEventParams

                if ($null -eq $lockEvents -or $lockEvents.Count -eq 0) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] No lock/unlock events found on $computer"
                    continue
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Retrieved $($lockEvents.Count) event(s) from $computer"

                # Process each event
                foreach ($lockEvent in $lockEvents) {
                    try {
                        $eventXml = [xml]$lockEvent.ToXml()

                        # Extract user information from Security event
                        $eventData = $eventXml.Event.EventData.Data
                        $targetUserSid = ($eventData | Where-Object { $_.Name -eq 'TargetUserSid' }).'#text'
                        $targetUserName = ($eventData | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
                        $targetDomainName = ($eventData | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'
                        $sessionName = ($eventData | Where-Object { $_.Name -eq 'SessionName' }).'#text'

                        $fullUserName = if ($targetDomainName -and $targetUserName) {
                            "$targetDomainName\$targetUserName"
                        } elseif ($targetUserName) {
                            $targetUserName
                        } else {
                            $targetUserSid
                        }

                        # Emit structured object
                        [PSCustomObject]@{
                            PSTypeName   = 'PSWinOps.RdpSessionLock'
                            TimeCreated  = $lockEvent.TimeCreated
                            ComputerName = $computer
                            UserName     = $fullUserName
                            SessionName  = $sessionName
                            Action       = $lockActionMap[[int]$lockEvent.Id]
                            EventID      = $lockEvent.Id
                            UserSID      = $targetUserSid
                            Timestamp    = Get-Date -Format 'o'
                        }

                    } catch {
                        Write-Warning "[$($MyInvocation.MyCommand)] Failed to parse event ID $($lockEvent.Id) on $computer - $_"
                    }
                }

            } catch [System.Diagnostics.Eventing.Reader.EventLogException] {
                Write-Error "[$($MyInvocation.MyCommand)] Event log error on $computer - $_"
            } catch [System.UnauthorizedAccessException] {
                Write-Error "[$($MyInvocation.MyCommand)] Access denied to Security log on $computer - Requires elevated permissions"
            } catch [System.Exception] {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query $computer - $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
