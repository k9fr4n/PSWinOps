function Enter-RdpSession {
    <#
.SYNOPSIS
    Establishes remote control (shadow) connection to an active RDP session

.DESCRIPTION
    Connects to an active RDP session on a remote computer to observe or interactively
    control the user's session. This is equivalent to the "shadow" functionality in
    Remote Desktop Services, allowing administrators to provide remote assistance or
    monitor user activity.

    Requires appropriate Group Policy settings and administrative permissions.
    The target user may receive a notification prompt depending on policy configuration.

    Two modes are supported:
    - View: Observation only (read-only access to the session)
    - Control: Full interactive control (keyboard and mouse input enabled)

    Supports ShouldProcess for -WhatIf and -Confirm operations.

.PARAMETER ComputerName
    The computer name where the target RDP session is active.
    Defaults to the local machine. Supports pipeline input by property name.

.PARAMETER SessionID
    The session ID to shadow. Can be retrieved using Get-ActiveRdpSession.
    Supports pipeline input by value and by property name.

.PARAMETER ControlMode
    Specifies the shadow mode:
    - Control: Full interactive control with keyboard and mouse input (default)
    - View: Read-only observation without interaction capability

.PARAMETER NoUserPrompt
    Suppresses the user consent prompt on the target session. Requires appropriate
    Group Policy configuration. If not configured, the connection may be rejected.

.PARAMETER Credential
    Credential to use when connecting to remote computers. If not specified,
    uses the current user's credentials.

.EXAMPLE
    Enter-RdpSession -SessionID 2 -ComputerName 'SRV01'
    Establishes interactive control of session 2 on SRV01 with user consent prompt.

.EXAMPLE
    Get-ActiveRdpSession -ComputerName 'APP01' | Where-Object { $_.UserName -eq 'DOMAIN\helpdesk' } | Enter-RdpSession -ControlMode View
    Finds helpdesk user session and connects in view-only mode.

.EXAMPLE
    Enter-RdpSession -SessionID 3 -ComputerName 'WEB01' -NoUserPrompt -WhatIf
    Shows what would happen if entering session 3 without user prompt.

.EXAMPLE
    Enter-RdpSession -SessionID 5 -ControlMode View -Credential $adminCred
    Connects to session 5 in observation mode using specified credentials.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+, Remote Desktop Services
    Permissions:   Local Administrator on target machine
    Requirements:  Group Policy setting "Set rules for remote control of RDS user sessions" must allow shadowing
    Note:          This function initiates the shadow session. Use Ctrl+* (keypad) to exit shadow mode.

.LINK
    https://docs.microsoft.com/en-us/windows-server/remote/remote-desktop-services/rds-remote-control
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
        [int]$SessionID,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Control', 'View')]
        [string]$ControlMode = 'Control',

        [Parameter(Mandatory = $false)]
        [switch]$NoUserPrompt,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        # Shadow mode flags (from Microsoft Terminal Services documentation)
        $script:shadowModeMap = @{
            'Control' = 2  # Full control with user notification
            'View'    = 1  # View only with user notification
        }

        # If NoUserPrompt is specified, add 2 to the flag value
        # Control without prompt = 4, View without prompt = 3
        if ($NoUserPrompt) {
            Write-Verbose "[$($MyInvocation.MyCommand)] NoUserPrompt specified - user consent will be bypassed if policy allows"
        }
    }

    process {
        Write-Verbose "[$($MyInvocation.MyCommand)] Processing session ID $SessionID on $ComputerName"

        # Calculate shadow mode flag
        $shadowMode = $script:shadowModeMap[$ControlMode]
        if ($NoUserPrompt) {
            $shadowMode += 2
        }

        $actionDescription = if ($ControlMode -eq 'Control') {
            'Take interactive control of RDP session (SHADOW MODE)'
        } else {
            'Observe RDP session in view-only mode (SHADOW MODE)'
        }

        if ($PSCmdlet.ShouldProcess("$ComputerName - Session $SessionID", $actionDescription)) {
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

                # Verify target session exists and is active
                $targetSession = Get-CimInstance -CimSession $cimSession -ClassName 'Win32_LogonSession' -Filter "LogonId = '$SessionID'" -ErrorAction SilentlyContinue

                if ($null -eq $targetSession) {
                    Write-Error "[$($MyInvocation.MyCommand)] Session ID $SessionID not found on $ComputerName"
                    return
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Target session $SessionID verified on $ComputerName"

                # Get Terminal Service instance
                $tsService = Get-CimInstance -CimSession $cimSession -ClassName 'Win32_TerminalService' -Namespace 'root\cimv2\TerminalServices' -ErrorAction Stop

                # Invoke RemoteControl method (shadow connection)
                Write-Verbose "[$($MyInvocation.MyCommand)] Initiating shadow connection with mode: $ControlMode (flag: $shadowMode)"

                $invokeParams = @{
                    InputObject = $tsService
                    MethodName  = 'RemoteControl'
                    Arguments   = @{
                        SessionId       = $SessionID
                        HotKeyVK        = 0x6A  # VK_MULTIPLY (numpad *)
                        HotkeyModifiers = 0x2  # MOD_CONTROL
                    }
                    ErrorAction = 'Stop'
                }

                $result = Invoke-CimMethod @invokeParams

                # Check return value
                $success = ($result.ReturnValue -eq 0)

                # Return code meanings for RemoteControl method
                $returnCodeMap = @{
                    0  = 'Success - Shadow session initiated'
                    1  = 'Failed - Session not found'
                    2  = 'Failed - Session not active or not accepting shadow connections'
                    5  = 'Failed - Access denied - Insufficient permissions'
                    7  = 'Failed - Invalid parameter'
                    9  = 'Failed - Shadow session already in progress'
                    10 = 'Failed - User rejected the connection request'
                    11 = 'Failed - Shadow not enabled in Group Policy'
                }

                $resultMessage = if ($returnCodeMap.ContainsKey($result.ReturnValue)) {
                    $returnCodeMap[$result.ReturnValue]
                } else {
                    "Unknown return code: $($result.ReturnValue)"
                }

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.RdpSessionAction'
                    ComputerName = $ComputerName
                    SessionID    = $SessionID
                    Action       = 'RemoteControl'
                    ControlMode  = $ControlMode
                    Success      = $success
                    ReturnCode   = $result.ReturnValue
                    Message      = $resultMessage
                    Timestamp    = Get-Date
                }

                if ($success) {
                    Write-Information -MessageData "[OK] Shadow session initiated for session $SessionID on $ComputerName" -InformationAction Continue
                    Write-Information -MessageData '[INFO] Press Ctrl+* (keypad asterisk) to exit shadow mode' -InformationAction Continue
                } else {
                    Write-Warning "[$($MyInvocation.MyCommand)] $resultMessage"
                }

            } catch [Microsoft.Management.Infrastructure.CimException] {
                Write-Error "[$($MyInvocation.MyCommand)] CIM error on $ComputerName - $_"
            } catch [System.UnauthorizedAccessException] {
                Write-Error "[$($MyInvocation.MyCommand)] Access denied to $ComputerName - Requires administrative permissions"
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to establish shadow connection to session $SessionID on $ComputerName - $_"
            } finally {
                if ($null -ne $cimSession) {
                    Remove-CimSession -CimSession $cimSession
                    Write-Verbose "[$($MyInvocation.MyCommand)] CIM session closed for $ComputerName"
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
