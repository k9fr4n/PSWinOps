function Remove-RdpSession {
    <#
.SYNOPSIS
    Logs off (removes) an RDP session on local or remote computers

.DESCRIPTION
    Forces a logoff of specified RDP sessions by session ID on one or more computers.
    This terminates the session completely and closes all applications. Unsaved work
    will be lost. Use Disconnect-RdpSession for a graceful disconnect without logoff.

    Supports ShouldProcess for -WhatIf and -Confirm operations.

.PARAMETER ComputerName
    One or more computer names where sessions should be removed.
    Defaults to the local machine. Supports pipeline input by property name.

.PARAMETER SessionID
    The session ID(s) to remove. Can be retrieved using Get-ActiveRdpSession.
    Supports pipeline input by value and by property name.

.PARAMETER Credential
    Credential to use when connecting to remote computers. If not specified,
    uses the current user's credentials.

.PARAMETER Force
    Bypass confirmation prompts. Use with caution as this will forcefully
    terminate sessions and may result in data loss.

.EXAMPLE
    Remove-RdpSession -SessionID 2
    Logs off session ID 2 on the local computer after confirmation.

.EXAMPLE
    Get-ActiveRdpSession -ComputerName 'SRV01' | Where-Object { $_.IdleTime -gt (New-TimeSpan -Days 1) } | Remove-RdpSession -Force
    Forcefully removes all sessions idle for more than 1 day on SRV01 without confirmation.

.EXAMPLE
    Remove-RdpSession -ComputerName 'WEB01' -SessionID 3 -WhatIf
    Shows what would happen if session 3 were removed from WEB01.

.EXAMPLE
    'APP01' | Get-RdpSession | Where-Object { $_.UserName -eq 'DOMAIN\olduser' } | Remove-RdpSession -Credential $cred
    Removes all sessions for a specific user on APP01 using provided credentials.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+
    Permissions:   Local Administrator on target machines
    WARNING:       This operation terminates sessions forcefully and may cause data loss

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
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        if ($Force -and -not $WhatIfPreference) {
            $ConfirmPreference = 'None'
        }
    }

    process {
        foreach ($session in $SessionID) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing session ID $session on $ComputerName"

            if ($PSCmdlet.ShouldProcess("$ComputerName - Session $session", 'Log off RDP session (FORCE TERMINATE)')) {
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

                    # Invoke LogoffSession method
                    $result = Invoke-CimMethod -InputObject $tsService -MethodName 'LogoffSession' -Arguments @{ SessionId = $session } -ErrorAction Stop

                    # Check return value
                    $success = ($result.ReturnValue -eq 0)

                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.RdpSessionAction'
                        ComputerName = $ComputerName
                        SessionID    = $session
                        Action       = 'Logoff'
                        Success      = $success
                        ReturnCode   = $result.ReturnValue
                        Timestamp    = Get-Date
                    }

                    if ($success) {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Successfully logged off session $session on $ComputerName"
                    } else {
                        Write-Warning "[$($MyInvocation.MyCommand)] Failed to log off session $session on $ComputerName - Return code: $($result.ReturnValue)"
                    }

                } catch [Microsoft.Management.Infrastructure.CimException] {
                    Write-Error "[$($MyInvocation.MyCommand)] CIM error on $ComputerName - $_"
                } catch [System.UnauthorizedAccessException] {
                    Write-Error "[$($MyInvocation.MyCommand)] Access denied to $ComputerName - Requires administrative permissions"
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to log off session $session on $ComputerName - $_"
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
