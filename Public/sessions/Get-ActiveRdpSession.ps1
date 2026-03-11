function Get-ActiveRdpSession {
    <#
.SYNOPSIS
    Retrieves currently active and disconnected RDP sessions from local or remote computers

.DESCRIPTION
    Queries the Terminal Services session information on one or more computers to
    retrieve all active, disconnected, and idle RDP sessions. Returns structured
    objects with session ID, user, state, logon time, and idle duration.

    Uses the Win32_TSSession WMI class via CIM to retrieve session information,
    providing more reliable cross-version compatibility than legacy query commands.

.PARAMETER ComputerName
    One or more computer names to query. Defaults to the local machine.
    Supports pipeline input by value and by property name.

.PARAMETER Credential
    Credential to use when querying remote computers. If not specified,
    uses the current user's credentials.

.PARAMETER IncludeSystemSessions
    Include system sessions (Session 0, Services, Console) in the output.
    By default, only user sessions are returned.

.EXAMPLE
    Get-ActiveRdpSession
    Retrieves all active user sessions from the local computer.

.EXAMPLE
    Get-ActiveRdpSession -ComputerName 'SRV01', 'SRV02' -Credential $cred
    Retrieves active sessions from multiple remote servers using specified credentials.

.EXAMPLE
    'WEB01', 'APP01' | Get-ActiveRdpSession | Where-Object { $_.State -eq 'Disconnected' }
    Pipeline example: finds all disconnected sessions on multiple servers.

.EXAMPLE
    Get-ADComputer -Filter "OperatingSystem -like '*Server*'" | Get-ActiveRdpSession | Where-Object { $_.IdleTime -gt (New-TimeSpan -Hours 4) }
    Retrieves sessions idle for more than 4 hours across all domain servers.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+
    Permissions:   Remote Desktop Users group or local Administrator on target machines

.LINK
    https://docs.microsoft.com/en-us/windows/win32/termserv/win32-logonsession
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
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSystemSessions
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        # Session state mapping
        $script:stateMap = @{
            0 = 'Active'
            1 = 'Connected'
            2 = 'ConnectQuery'
            3 = 'Shadow'
            4 = 'Disconnected'
            5 = 'Idle'
            6 = 'Listen'
            7 = 'Reset'
            8 = 'Down'
            9 = 'Init'
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing: $computer"

            # Build CIM session parameters
            $cimSessionParams = @{
                ComputerName = $computer
                ErrorAction  = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Credential')) {
                $cimSessionParams['Credential'] = $Credential
            }

            $cimSession = $null

            try {
                # Create CIM session
                $cimSession = New-CimSession @cimSessionParams
                Write-Verbose "[$($MyInvocation.MyCommand)] CIM session established to $computer"

                # Query Terminal Services sessions
                $cimParams = @{
                    CimSession  = $cimSession
                    ClassName   = 'Win32_LogonSession'
                    ErrorAction = 'Stop'
                }

                $logonSessions = Get-CimInstance @cimParams | Where-Object {
                    $_.LogonType -eq 10  # RemoteInteractive (RDP)
                }

                if ($null -eq $logonSessions -or @($logonSessions).Count -eq 0) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] No RDP sessions found on $computer"
                    continue
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Retrieved $(@($logonSessions).Count) session(s) from $computer"

                # Process each session
                foreach ($session in $logonSessions) {
                    try {
                        # Get associated user account
                        $userQuery = Get-CimAssociatedInstance -InputObject $session -ResultClassName 'Win32_Account' -ErrorAction SilentlyContinue

                        $userName = if ($userQuery) {
                            "$($userQuery.Domain)\$($userQuery.Name)"
                        } else {
                            'UNKNOWN'
                        }

                        # Calculate idle time
                        $startTime = $session.StartTime
                        $idleTime = if ($startTime) {
                            (Get-Date) - $startTime
                        } else {
                            [timespan]::Zero
                        }

                        # Emit structured object
                        [PSCustomObject]@{
                            PSTypeName   = 'PSWinOps.ActiveRdpSession'
                            ComputerName = $computer
                            SessionID    = $session.LogonId
                            UserName     = $userName
                            LogonTime    = $startTime
                            IdleTime     = $idleTime
                            LogonType    = 'RemoteInteractive'
                            AuthPackage  = $session.AuthenticationPackage
                        }

                    } catch {
                        Write-Warning "[$($MyInvocation.MyCommand)] Failed to process session on $computer - $_"
                    }
                }

            } catch [Microsoft.Management.Infrastructure.CimException] {
                Write-Error "[$($MyInvocation.MyCommand)] CIM error on $computer - $_"
            } catch [System.UnauthorizedAccessException] {
                Write-Error "[$($MyInvocation.MyCommand)] Access denied to $computer - Requires administrative permissions"
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query $computer - $_"
            } finally {
                if ($null -ne $cimSession) {
                    Remove-CimSession -CimSession $cimSession
                    Write-Verbose "[$($MyInvocation.MyCommand)] CIM session closed for $computer"
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
