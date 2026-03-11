function Disconnect-RdpSession {
    <#
.SYNOPSIS
    Disconnects an active RDP session on local or remote computers

.DESCRIPTION
    Disconnects specified RDP sessions by session ID on one or more computers.
    The session remains in a disconnected state and can be reconnected by the user.
    This function does not log the user off - use Remove-RdpSession for logoff.

    Supports ShouldProcess for -WhatIf and -Confirm operations.

.PARAMETER ComputerName
    One or more computer names where sessions should be disconnected.
    Defaults to the local machine. Supports pipeline input by property name.

.PARAMETER SessionID
    The session ID(s) to disconnect. Can be retrieved using Get-ActiveRdpSession.
    Supports pipeline input by value and by property name.

.PARAMETER Credential
    Credential to use when connecting to remote computers. If not specified,
    uses the current user's credentials.

.EXAMPLE
    Disconnect-RdpSession -SessionID 2
    Disconnects session ID 2 on the local computer.

.EXAMPLE
    Get-ActiveRdpSession -ComputerName 'SRV01' | Where-Object { $_.IdleTime -gt (New-TimeSpan -Hours 2) } | Disconnect-RdpSession
    Disconnects all sessions idle for more than 2 hours on SRV01.

.EXAMPLE
    Disconnect-RdpSession -ComputerName 'WEB01' -SessionID 3, 5 -WhatIf
    Shows what would happen if sessions 3 and 5 were disconnected on WEB01.

.EXAMPLE
    'APP01', 'APP02' | Get-ActiveRdpSession | Where-Object { $_.UserName -eq 'DOMAIN\testuser' } | Disconnect-RdpSession -Confirm:$false
    Disconnects all sessions for a specific user on multiple servers without confirmation.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+
    Permissions:   Remote Desktop Users group or local Administrator on target machines

.LINK
    https://docs.microsoft.com/en-us/windows/win32/termserv/win32-terminalservice
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(0, 65536)]
        [int[]]$SessionID,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"
    }

    process {
        foreach ($session in $SessionID) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing session ID $session on $ComputerName"

            if ($PSCmdlet.ShouldProcess("$ComputerName - Session $session", 'Disconnect RDP session')) {
                # Build CIM session parameters
                $cimSessionParams = @{
                    ComputerName = $ComputerName
                    ErrorAction  = 'Stop'
                }

                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $cimSessionParams['Credential'] = $Credential
                }

                $cimSession = $null

                try {
                    # Create CIM session
                    $cimSession = New-CimSession @cimSessionParams
                    Write-Verbose "[$($MyInvocation.MyCommand)] CIM session established to $ComputerName"

                    # Get Terminal Service instance
                    $tsService = Get-CimInstance -CimSession $cimSession -ClassName 'Win32_TerminalService' -Namespace 'root\cimv2\TerminalServices' -ErrorAction Stop

                    # Invoke DisconnectSession method
                    $result = Invoke-CimMethod -InputObject $tsService -MethodName 'DisconnectSession' -Arguments @{ SessionId = $session } -ErrorAction Stop

                    # Check return value
                    $success = ($result.ReturnValue -eq 0)

                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.RdpSessionAction'
                        ComputerName = $ComputerName
                        SessionID    = $session
                        Action       = 'Disconnect'
                        Success      = $success
                        ReturnCode   = $result.ReturnValue
                        Timestamp    = Get-Date
                    }

                    if ($success) {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Successfully disconnected session $session on $ComputerName"
                    } else {
                        Write-Warning "[$($MyInvocation.MyCommand)] Failed to disconnect session $session on $ComputerName - Return code: $($result.ReturnValue)"
                    }

                } catch [Microsoft.Management.Infrastructure.CimException] {
                    Write-Error "[$($MyInvocation.MyCommand)] CIM error on $ComputerName - $_"
                } catch [System.UnauthorizedAccessException] {
                    Write-Error "[$($MyInvocation.MyCommand)] Access denied to $ComputerName - Requires administrative permissions"
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to disconnect session $session on $ComputerName - $_"
                } finally {
                    if ($null -ne $cimSession) {
                        Remove-CimSession -CimSession $cimSession
                        Write-Verbose "[$($MyInvocation.MyCommand)] CIM session closed for $ComputerName"
                    }
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
