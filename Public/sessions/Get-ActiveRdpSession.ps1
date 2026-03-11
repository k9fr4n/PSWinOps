#Requires -Version 5.1

<#
.SYNOPSIS
    Provides Get-ActiveRdpSession to enumerate live Terminal Services user sessions.

.DESCRIPTION
    Dot-source this file to load ConvertFrom-QUserIdleTime and Get-ActiveRdpSession.

    This version replaces the original Win32_LogonSession-based implementation.
    Win32_LogonSession with LogonType=10 queries the LSA session database, which:
      - Retains records for weeks after sessions are closed (stale entries).
      - Creates two entries per RDP connection (one per auth package: Negotiate
        and Kerberos), causing duplicates for every live or past session.

    This script uses quser.exe, which queries the live Terminal Services session
    table maintained by the Windows Session Manager, returning exactly one row per
    active or disconnected user session with no historical artefacts.

.EXAMPLE
    . .\Get-ActiveRdpSession.ps1
    Get-ActiveRdpSession

    Dot-sources the script then lists all live user sessions on the local computer.

.EXAMPLE
    . .\Get-ActiveRdpSession.ps1
    'SRV01', 'SRV02' | Get-ActiveRdpSession -Credential (Get-Credential)

    Dot-sources the script then queries two remote servers.

.NOTES
    Author:        Franck SALLET
    Version:       2.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+; WinRM enabled on remote targets
    Permissions:   Local Administrator or Remote Desktop Users on each target

.LINK
    https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/quser
#>


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
        if ($IdleTimeString -match '^(?<d>\d+)\+(?<h>\d+):(?<m>\d+)$') {
            return [TimeSpan]::new([int]$Matches['d'], [int]$Matches['h'], [int]$Matches['m'], 0)
        }

        # Format: H:MM -- e.g., "8:05"
        if ($IdleTimeString -match '^(?<h>\d+):(?<m>\d+)$') {
            return [TimeSpan]::new([int]$Matches['h'], [int]$Matches['m'], 0)
        }

        # Format: minutes only -- e.g., "5"
        if ($IdleTimeString -match '^\d+$') {
            return [TimeSpan]::FromMinutes([int]$IdleTimeString)
        }

        return [TimeSpan]::Zero
    }
}


function Get-ActiveRdpSession {
    <#
.SYNOPSIS
    Retrieves live RDP and console user sessions from local or remote computers

.DESCRIPTION
    Queries the Terminal Services session manager on one or more computers using
    quser.exe (Query User). This executable reads directly from the Windows
    session table maintained by the Session Manager and returns exactly one row
    per live session -- no stale LSA records from past connections, no duplicate
    entries caused by multi-package authentication (Negotiate + Kerberos).

    Local machines are queried directly. Remote machines are queried via
    Invoke-Command (WinRM), which executes quser.exe in the remote session and
    returns its output. Each session is emitted as a structured PSCustomObject
    containing user name, session name, state, idle time, and logon time.

    State values returned by quser: Active, Disc (disconnected).
    Idle time of zero ([TimeSpan]::Zero) means the session is currently in use.

.PARAMETER ComputerName
    One or more computer names or IP addresses to query.
    Defaults to the local machine ($env:COMPUTERNAME).
    Accepts pipeline input by value and by property name.
    Aliases: CN, Name, DNSHostName.

.PARAMETER Credential
    Optional PSCredential used when connecting to remote computers via
    Invoke-Command (WinRM). When omitted, the current user context is used.
    Has no effect for local machine queries.

.EXAMPLE
    Get-ActiveRdpSession
    Lists all live user sessions on the local computer.

.EXAMPLE
    Get-ActiveRdpSession -ComputerName 'SRV01', 'SRV02' -Credential (Get-Credential)
    Queries two remote servers, prompting once for credentials.

.EXAMPLE
    'WEB01', 'APP01' | Get-ActiveRdpSession | Where-Object { $_.State -eq 'Disc' }
    Finds all disconnected sessions across multiple servers via pipeline input.

.EXAMPLE
    Get-ActiveRdpSession | Where-Object { $_.IdleTime -gt [TimeSpan]::FromHours(4) }
    Returns all sessions idle for more than 4 hours on the local machine.

.NOTES
    Author:        Franck SALLET
    Version:       2.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+; WinRM enabled on remote targets
    Permissions:   Local Administrator or Remote Desktop Users on each target
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
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting -- PowerShell $($PSVersionTable.PSVersion)"
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing: $computer"

            $isLocal = ($computer -eq $env:COMPUTERNAME) -or
            ($computer -eq 'localhost') -or
            ($computer -eq '.')

            try {
                # Run quser.exe on the target.
                # $env:SystemRoot inside the remote scriptblock is NOT prefixed with
                # $using:, so it is evaluated in the remote session -- correct for
                # all targets regardless of drive letter or installation path.
                if ($isLocal) {
                    $rawLines = & "$env:SystemRoot\System32\quser.exe" 2>&1
                } else {
                    $invokeParams = @{
                        ComputerName = $computer
                        ScriptBlock  = { & "$env:SystemRoot\System32\quser.exe" 2>&1 }
                        ErrorAction  = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $rawLines = Invoke-Command @invokeParams
                }

                # Collect only string lines; discard ErrorRecord objects that result
                # from quser writing "No user exists for *" to stderr when no users
                # are logged on.
                $lineList = [System.Collections.Generic.List[string]]::new()
                foreach ($rawLine in $rawLines) {
                    if ($rawLine -is [string]) {
                        $lineList.Add($rawLine)
                    }
                }

                # Fewer than 2 lines means no users are logged on (0 data rows).
                if ($lineList.Count -lt 2) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] No user sessions found on '$computer'"
                    continue
                }

                # Derive column start offsets from the header line.
                # quser.exe always outputs an English-language header regardless of
                # the system locale, so these key names are stable across regions.
                $header = $lineList[0]
                $colUser = 1
                $colSession = $header.IndexOf('SESSIONNAME')
                $colId = $header.IndexOf(' ID ') + 1
                $colState = $header.IndexOf('STATE')
                $colIdle = $header.IndexOf('IDLE TIME')
                $colLogon = $header.IndexOf('LOGON TIME')

                if ($colSession -lt 0 -or $colId -le 0 -or $colState -lt 0 -or
                    $colIdle -lt 0 -or $colLogon -lt 0) {
                    Write-Warning "[$($MyInvocation.MyCommand)] Unrecognised quser header on '$computer' -- skipping"
                    continue
                }

                for ($idx = 1; $idx -lt $lineList.Count; $idx++) {
                    $sessionLine = $lineList[$idx]
                    if ([string]::IsNullOrWhiteSpace($sessionLine)) {
                        continue
                    }
                    if ($sessionLine.Length -le $colState) {
                        continue
                    }

                    $isCurrentSession = ($sessionLine[0] -eq '>')

                    # Fields up to STATE are guaranteed present once the length check passes.
                    $parsedUser = $sessionLine.Substring($colUser, $colSession - $colUser).Trim()
                    $parsedSession = $sessionLine.Substring($colSession, $colId - $colSession).Trim()
                    $parsedIdStr = $sessionLine.Substring($colId, $colState - $colId).Trim()

                    # STATE: read up to IDLE TIME column, or end-of-line if line is shorter.
                    $stateEnd = if ($sessionLine.Length -gt $colIdle) {
                        $colIdle
                    } else {
                        $sessionLine.Length
                    }
                    $parsedState = $sessionLine.Substring($colState, $stateEnd - $colState).Trim()

                    # IDLE TIME: read between IDLE TIME and LOGON TIME columns.
                    $parsedIdleStr = if ($sessionLine.Length -gt $colIdle) {
                        $idleEnd = if ($sessionLine.Length -gt $colLogon) {
                            $colLogon
                        } else {
                            $sessionLine.Length
                        }
                        $sessionLine.Substring($colIdle, $idleEnd - $colIdle).Trim()
                    } else {
                        [string]::Empty
                    }

                    # LOGON TIME: read from column to end of line.
                    $parsedLogonStr = if ($sessionLine.Length -gt $colLogon) {
                        $sessionLine.Substring($colLogon).Trim()
                    } else {
                        [string]::Empty
                    }

                    $parsedId = 0
                    [void][int]::TryParse($parsedIdStr, [ref]$parsedId)

                    $idleTime = ConvertFrom-QUserIdleTime -IdleTimeString $parsedIdleStr

                    $logonTime = $null
                    if (-not [string]::IsNullOrEmpty($parsedLogonStr)) {
                        $parsedDt = [datetime]::MinValue
                        if ([datetime]::TryParse($parsedLogonStr, [ref]$parsedDt)) {
                            $logonTime = $parsedDt
                        }
                    }

                    [PSCustomObject]@{
                        PSTypeName       = 'PSWinOps.ActiveRdpSession'
                        ComputerName     = $computer
                        SessionID        = $parsedId
                        SessionName      = $parsedSession
                        UserName         = $parsedUser
                        State            = $parsedState
                        IdleTime         = $idleTime
                        LogonTime        = $logonTime
                        IsCurrentSession = $isCurrentSession
                    }
                }

            } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                Write-Error "[$($MyInvocation.MyCommand)] WinRM connection failed to '$computer': $_"
            } catch [System.UnauthorizedAccessException] {
                Write-Error "[$($MyInvocation.MyCommand)] Access denied to '$computer' -- requires local Administrator or Remote Desktop Users membership"
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query '$computer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
