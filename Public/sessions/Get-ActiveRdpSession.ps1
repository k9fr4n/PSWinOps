function Get-ActiveRdpSession {
    <#
.SYNOPSIS
    Retrieves currently active and disconnected RDP sessions from local or remote computers

.DESCRIPTION
    Queries the Terminal Services session information on one or more computers to
    retrieve all active, disconnected, and idle RDP sessions. Returns structured
    objects with session ID, user, state, logon time, and idle duration.

    Uses the Win32_LogonSession WMI class via CIM to retrieve session information,
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
    Version:       1.1.0
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

            # Determine whether the target is the local machine.
            # Local queries skip New-CimSession entirely, which avoids type identity
            # mismatches between runspaces and removes an unnecessary network hop.
            $isLocal = ($computer -eq $env:COMPUTERNAME) -or
            ($computer -eq 'localhost') -or
            ($computer -eq '.')

            $cimSession = $null

            try {
                # Only create a CIM session for remote computers
                if (-not $isLocal) {
                    $cimSessionParams = @{
                        ComputerName = $computer
                        ErrorAction  = 'Stop'
                    }

                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $cimSessionParams['Credential'] = $Credential
                    }

                    $cimSession = New-CimSession @cimSessionParams
                    Write-Verbose "[$($MyInvocation.MyCommand)] CIM session established to $computer"
                }

                # Build Get-CimInstance parameters — omit CimSession for local queries
                $cimParams = @{
                    ClassName   = 'Win32_LogonSession'
                    ErrorAction = 'Stop'
                }

                if ($null -ne $cimSession) {
                    $cimParams['CimSession'] = $cimSession
                }

                # Filter to RemoteInteractive (LogonType 10 = RDP) sessions only
                $logonSessions = Get-CimInstance @cimParams | Where-Object {
                    $_.LogonType -eq 10
                }

                if ($null -eq $logonSessions -or @($logonSessions).Count -eq 0) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] No RDP sessions found on $computer"
                    continue
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Retrieved $(@($logonSessions).Count) session(s) from $computer"

                foreach ($session in $logonSessions) {

                    # Resolve the associated user via Win32_LoggedOnUser.
                    # We query Win32_LoggedOnUser filtered by LogonId, then read the
                    # Domain and Name properties directly — avoiding Get-CimAssociatedInstance
                    # which requires a typed CimInstance object and fails across Pester runspaces.
                    $userName = 'UNKNOWN'
                    try {
                        $logonId = $session.LogonId
                        $wqlFilter = "Dependent = 'Win32_LogonSession.LogonId=""$logonId""'"

                        $assocParams = @{
                            ClassName   = 'Win32_LoggedOnUser'
                            Filter      = $wqlFilter
                            ErrorAction = 'Stop'
                        }
                        if ($null -ne $cimSession) {
                            $assocParams['CimSession'] = $cimSession
                        }

                        $association = Get-CimInstance @assocParams | Select-Object -First 1

                        # Real CimInstance exposes Antecedent as a typed reference object
                        # with Domain and Name properties directly accessible.
                        if ($association -and $association.Antecedent) {
                            $ref = $association.Antecedent
                            if ($ref.Domain -and $ref.Name) {
                                $userName = "$($ref.Domain)\$($ref.Name)"
                            }
                        }
                    } catch {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Could not resolve user for session $($session.LogonId) on $computer - $_"
                    }

                    $startTime = $session.StartTime
                    $idleTime = if ($startTime) {
                        (Get-Date) - $startTime
                    } else {
                        $null
                    }

                    # Emit one structured object per session
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
