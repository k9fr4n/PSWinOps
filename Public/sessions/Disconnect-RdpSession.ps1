#Requires -Version 5.1

function Disconnect-RdpSession {
    <#
    .SYNOPSIS
        Disconnects one or more RDP sessions on a local or remote computer
    .DESCRIPTION
        Uses the built-in tsdiscon.exe utility to disconnect RDP sessions by session ID.
        Supports local and remote computers with optional credential pass-through via
        WinRM remoting. Accepts pipeline input from Get-RdpSession for bulk
        operations. Returns a result object per session indicating success or failure.
        For remote targets without credentials, Invoke-Command sends the disconnect
        command over WinRM. When credentials are provided, they are passed through
        Invoke-Command's -Credential parameter.
    .PARAMETER ComputerName
        The target computer name or IP address. Defaults to the local computer name.
        Accepts pipeline input by property name for integration with Get-RdpSession.
    .PARAMETER SessionID
        One or more RDP session IDs to disconnect. Valid range is 0 to 65536.
        Accepts pipeline input directly or by property name.
    .PARAMETER Credential
        Optional PSCredential for authenticating to remote computers. When provided,
        the disconnect command executes through Invoke-Command with WinRM remoting.
        Not used for local sessions.
    .EXAMPLE
        Disconnect-RdpSession -ComputerName 'SRV01' -SessionID 3
        Disconnects session ID 3 on server SRV01 after confirmation prompt.
    .EXAMPLE
        Get-RdpSession -ComputerName 'SRV01' | Disconnect-RdpSession -Confirm:$false
        Pipes all active sessions from SRV01 and disconnects them without prompting.
    .EXAMPLE
        Disconnect-RdpSession -ComputerName 'SRV01' -SessionID 3, 5 -Credential (Get-Credential) -Verbose
        Disconnects sessions 3 and 5 on SRV01 using alternate credentials with verbose output.
    .NOTES
        Author:        Franck SALLET
        Version:       2.0.0
        Last Modified: 2026-03-12
        Requires:      PowerShell 5.1+, tsdiscon.exe (built-in on all Windows editions)
        Permissions:   Local admin or Remote Desktop Services disconnect rights on the target
                       WinRM access required when using the -Credential parameter
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateRange(0, 65536)]
        [int[]]$SessionID,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        $tsdisconCmd = Get-Command -Name 'tsdiscon.exe' -CommandType Application -ErrorAction SilentlyContinue
        if ($null -eq $tsdisconCmd) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    'tsdiscon.exe was not found on this system. Ensure Remote Desktop Services tools are available.'
                ),
                'TsdisconNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                'tsdiscon.exe'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Found tsdiscon.exe at: $($tsdisconCmd.Source)"

        $LOCAL_IDENTIFIERS = @($env:COMPUTERNAME, 'localhost', '.', '127.0.0.1', '::1')

        $disconnectBlock = {
            param([int]$SessId)
            $null = & tsdiscon.exe $SessId 2>&1
            return $LASTEXITCODE
        }
    }

    process {
        foreach ($session in $SessionID) {
            $targetDescription = "$ComputerName (Session ID: $session)"
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing $targetDescription"

            if ($PSCmdlet.ShouldProcess($targetDescription, 'Disconnect RDP session')) {
                $isLocalMachine = $ComputerName -in $LOCAL_IDENTIFIERS
                $success = $false

                try {
                    $invokeParams = @{
                        ScriptBlock  = $disconnectBlock
                        ArgumentList = @($session)
                        ErrorAction  = 'Stop'
                    }

                    if (-not $isLocalMachine) {
                        $invokeParams['ComputerName'] = $ComputerName
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $invokeParams['Credential'] = $Credential
                        }
                    }

                    $exitCode = Invoke-Command @invokeParams
                    $success = ($null -ne $exitCode -and $exitCode -eq 0)

                    if ($success) {
                        Write-Verbose "[$($MyInvocation.MyCommand)] [OK] Disconnected $targetDescription"
                    } else {
                        Write-Warning "[$($MyInvocation.MyCommand)] tsdiscon.exe returned exit code $exitCode for $targetDescription"
                    }
                } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                    Write-Error "[$($MyInvocation.MyCommand)] WinRM connection failed to $ComputerName - $_"
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to disconnect $targetDescription - $_"
                }

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.RdpSessionAction'
                    ComputerName = $ComputerName
                    SessionID    = $session
                    Action       = 'Disconnect'
                    Success      = $success
                    Timestamp    = Get-Date
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
