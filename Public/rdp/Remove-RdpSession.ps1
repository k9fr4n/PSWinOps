#Requires -Version 5.1

function Remove-RdpSession {
    <#
        .SYNOPSIS
            Logs off (removes) an RDP session on local or remote computers

        .DESCRIPTION
            Forces a logoff of specified RDP sessions by session ID on one or more computers
            using logoff.exe. This terminates the session completely and closes all
            applications. Unsaved work will be lost. Use Disconnect-RdpSession for a
            graceful disconnect without logoff.

            Local machines are targeted directly via logoff.exe with no WinRM dependency.
            Remote machines are targeted via Invoke-Command (WinRM), which executes
            logoff.exe in the remote session. When -Credential is provided, it is
            forwarded to Invoke-Command for authentication.

            Supports ShouldProcess for -WhatIf and -Confirm operations.

        .PARAMETER ComputerName
            One or more computer names where sessions should be removed.
            Defaults to the local machine. Supports pipeline input by property name.

        .PARAMETER SessionID
            The session ID(s) to remove. Can be retrieved using Get-RdpSession.
            Supports pipeline input by value and by property name.

        .PARAMETER Credential
            Credential to use when connecting to remote computers via WinRM.
            If not specified, uses the current user's credentials. Not used for
            local session logoff.

        .PARAMETER Force
            Bypass confirmation prompts. Use with caution as this will forcefully
            terminate sessions and may result in data loss.

        .EXAMPLE
            Remove-RdpSession -SessionID 2
            Logs off session ID 2 on the local computer after confirmation.

        .EXAMPLE
            Get-RdpSession -ComputerName 'SRV01' | Where-Object { $_.IdleTime -gt (New-TimeSpan -Days 1) } | Remove-RdpSession -Force
            Forcefully removes all sessions idle for more than 1 day on SRV01 without confirmation.

        .EXAMPLE
            Remove-RdpSession -ComputerName 'WEB01' -SessionID 3 -WhatIf
            Shows what would happen if session 3 were removed from WEB01.

        .EXAMPLE
            $cred = Get-Credential -UserName 'DOMAIN\admin'
            'APP01' | Get-RdpSession | Where-Object { $_.UserName -eq 'DOMAIN\olduser' } | Remove-RdpSession -Credential $cred

            Removes all sessions for a specific user on APP01 using alternate credentials.

        .OUTPUTS
            PSWinOps.RdpSessionAction
            Logoff action result with session details and status.

        .NOTES
            Author:        Franck SALLET
            Version:       2.1.0
            Last Modified: 2026-04-02
            Requires:      PowerShell 5.1+, logoff.exe (built-in on all Windows editions)
            Permissions:   Local Administrator on target machines
            WinRM access required when using the -Credential parameter
            WARNING:       This operation terminates sessions forcefully and may cause data loss

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/logoff
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.RdpSessionAction')]
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

        $logoffCmd = Get-Command -Name 'logoff.exe' -CommandType Application -ErrorAction SilentlyContinue
        if ($null -eq $logoffCmd) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    'logoff.exe was not found on this system. Ensure Remote Desktop Services tools are available.'
                ),
                'LogoffNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                'logoff.exe'
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Found logoff.exe at: $($logoffCmd.Source)"

        # When -Force is used without explicit -Confirm, suppress confirmation prompts.
        # Setting $ConfirmPreference in function scope creates a local copy (does not leak).
        # Check -Confirm bound explicitly so that -Force -Confirm still prompts.
        if ($Force -and -not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = 'None'
        }

        $LOCAL_IDENTIFIERS = @($env:COMPUTERNAME, 'localhost', '.', '127.0.0.1', '::1')

        $logoffBlock = {
            param([int]$SessId)
            $null = & logoff.exe $SessId 2>&1
            return $LASTEXITCODE
        }
    }

    process {
        foreach ($session in $SessionID) {
            $targetDescription = "$ComputerName (Session ID: $session)"
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing $targetDescription"

            if ($PSCmdlet.ShouldProcess($targetDescription, 'Log off RDP session (FORCE TERMINATE)')) {
                $isLocalMachine = $ComputerName -in $LOCAL_IDENTIFIERS
                $success = $false

                try {
                    $invokeParams = @{
                        ScriptBlock  = $logoffBlock
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
                        Write-Verbose "[$($MyInvocation.MyCommand)] [OK] Logged off $targetDescription"
                    } else {
                        Write-Warning "[$($MyInvocation.MyCommand)] logoff.exe returned exit code $exitCode for $targetDescription"
                    }
                } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                    Write-Error "[$($MyInvocation.MyCommand)] WinRM connection failed to $ComputerName - $_"
                } catch [System.UnauthorizedAccessException] {
                    Write-Error "[$($MyInvocation.MyCommand)] Access denied to $ComputerName - Requires administrative permissions"
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to log off $targetDescription - $_"
                }

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.RdpSessionAction'
                    ComputerName = $ComputerName
                    SessionID    = $session
                    Action       = 'Logoff'
                    Success      = $success
                    Timestamp    = Get-Date -Format 'o'
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
