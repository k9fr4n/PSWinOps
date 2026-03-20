#Requires -Version 5.1

function Connect-RdpSession {
    <#
.SYNOPSIS
    Establishes a remote control (shadow) connection to an active RDP session

.DESCRIPTION
    Connects to an active RDP session on a remote computer using mstsc.exe shadow
    mode to observe or interactively control the user's session. Session existence
    is verified via Invoke-QwinstaQuery (private helper wrapping qwinsta.exe) before
    the shadow window is opened.

    v1.2.0 fix: removed reliance on Win32_TSSession (class unavailable in
    root\cimv2\TerminalServices) and Win32_TerminalService.RemoteControl()
    (method does not exist). Both are replaced by qwinsta.exe and mstsc.exe /shadow,
    which are the documented Windows mechanisms for RDP session shadowing.

    Group Policy "Set rules for remote control of RDS user sessions" must permit
    shadowing on the target server. Press Ctrl+* (numpad asterisk) to exit shadow mode.

.PARAMETER ComputerName
    The remote computer hosting the target RDP session. Defaults to the local
    machine. Accepts pipeline input by property name.
    Accepts a single computer name only — mstsc.exe shadow mode opens one
    interactive window per call. To shadow sessions on multiple machines,
    pipe objects from Get-RdpSession individually.

.PARAMETER SessionID
    The numeric session ID to shadow. Retrieve this value with Get-RdpSession.
    Accepts pipeline input by value and by property name.

.PARAMETER ControlMode
    Shadow interaction mode.
    Control (default): full keyboard and mouse input forwarded to the session.
    View: read-only observation -- no input is sent to the session.

.PARAMETER NoUserPrompt
    Passes /noConsentPrompt to mstsc.exe, suppressing the consent dialog on the
    target session. Requires the matching Group Policy setting to be configured.

.PARAMETER Credential
    Runs mstsc.exe under the specified account via Start-Process -Credential.
    If omitted, the current user context is used. Note that the mstsc process
    must be able to display a window on the current desktop.

.EXAMPLE
    Connect-RdpSession -SessionID 2 -ComputerName 'SERVER01'
    Shadows session 2 on SERVER01 in interactive control mode.
    The user receives a consent prompt (default behavior).

.EXAMPLE
    Get-RdpSession -ComputerName 'APP01' |
        Where-Object { $_.UserName -eq 'admin-jdoe' } |
        Connect-RdpSession -ControlMode View
    Finds the session for admin-jdoe via pipeline and connects in view-only mode.

.EXAMPLE
    Connect-RdpSession -SessionID 3 -ComputerName 'WEB01' -NoUserPrompt -WhatIf
    Dry-run: shows what would happen without opening the shadow window.

.EXAMPLE
    Connect-RdpSession -SessionID 5 -ControlMode View -Credential $adminCred
    Opens a view-only shadow of session 5, with mstsc.exe running as $adminCred.

.OUTPUTS
PSWinOps.RdpSessionAction
    Connection action result with session details and status.

.NOTES
    Author:        Franck SALLET
    Version:       1.2.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+, mstsc.exe, qwinsta.exe
    Permissions:   Local Administrator on target machine

    Changelog v1.2.0:
      - [FIX] Replaced Win32_TSSession CIM check with qwinsta.exe session lookup.
              Win32_TSSession does not exist in root\cimv2\TerminalServices;
              -ErrorAction SilentlyContinue was silently hiding the error,
              causing every session lookup to return null (false negative).
      - [FIX] Replaced Win32_TerminalService.RemoteControl() with
              mstsc.exe /shadow, the documented Windows shadow mechanism.
              Win32_TerminalService has no RemoteControl() instance method.
      - [FIX] Extracted qwinsta call into private Invoke-QwinstaQuery to isolate
              $LASTEXITCODE dependency and enable reliable unit testing.
      - [KEEP] Credential now forwarded to Start-Process -Credential.

.LINK
    https://docs.microsoft.com/en-us/windows-server/remote/remote-desktop-services/rds-remote-control
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
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting -- PowerShell $($PSVersionTable.PSVersion)"

        $script:mstscPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\mstsc.exe'

        if (-not (Test-Path -Path $script:mstscPath -PathType Leaf)) {
            throw "[$($MyInvocation.MyCommand)] mstsc.exe not found at: $script:mstscPath"
        }
    }

    process {
        Write-Verbose "[$($MyInvocation.MyCommand)] Processing session ID $SessionID on $ComputerName"

        # -------------------------------------------------------------------
        # Step 1 -- Verify session exists via Invoke-QwinstaQuery
        # -------------------------------------------------------------------
        # qwinsta output format (header + data lines):
        #   [>]SessionName   [UserName]   ID   State   [Type]   [Device]
        # The ID column is always a standalone integer token.
        # We skip the header line and search each data line for a token that
        # matches the requested session ID exactly.
        # -------------------------------------------------------------------
        Write-Verbose "[$($MyInvocation.MyCommand)] Verifying session $SessionID on $ComputerName via qwinsta"

        $qwinstaResult = Invoke-QwinstaQuery -ServerName $ComputerName

        if ($qwinstaResult.ExitCode -ne 0) {
            Write-Error ("[$($MyInvocation.MyCommand)] qwinsta failed on $ComputerName " +
                "(exit $($qwinstaResult.ExitCode)). Verify network connectivity and permissions.")
            return
        }

        $sessionFound = $false
        $targetIdToken = $SessionID.ToString()

        foreach ($qwinstaLine in ($qwinstaResult.Output | Select-Object -Skip 1)) {
            # Strip the leading '>' marker that qwinsta uses for the current session
            $lineText = ($qwinstaLine -replace '^>', ' ').Trim()
            $tokens = $lineText -split '\s+'
            foreach ($lineToken in $tokens) {
                if ($lineToken -eq $targetIdToken) {
                    $sessionFound = $true
                    break
                }
            }
            if ($sessionFound) {
                break
            }
        }

        if (-not $sessionFound) {
            Write-Error "[$($MyInvocation.MyCommand)] Session ID $SessionID not found on $ComputerName"
            return
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Session $SessionID confirmed on $ComputerName"

        # -------------------------------------------------------------------
        # Step 2 -- Build mstsc.exe /shadow argument list
        # -------------------------------------------------------------------
        $mstscArgList = [System.Collections.Generic.List[string]]::new()
        $mstscArgList.Add("/shadow:$SessionID")
        $mstscArgList.Add("/v:$ComputerName")

        if ($ControlMode -eq 'Control') {
            $mstscArgList.Add('/control')
        }

        if ($NoUserPrompt) {
            $mstscArgList.Add('/noConsentPrompt')
        }

        $actionDescription = if ($ControlMode -eq 'Control') {
            'Take interactive control of RDP session (SHADOW MODE)'
        } else {
            'Observe RDP session in view-only mode (SHADOW MODE)'
        }

        # -------------------------------------------------------------------
        # Step 3 -- Launch shadow session via mstsc.exe
        # -------------------------------------------------------------------
        if ($PSCmdlet.ShouldProcess("$ComputerName - Session $SessionID", $actionDescription)) {

            Write-Verbose "[$($MyInvocation.MyCommand)] Launching: mstsc.exe $($mstscArgList -join ' ')"

            $startParams = @{
                FilePath     = $script:mstscPath
                ArgumentList = $mstscArgList.ToArray()
                Wait         = $true
                PassThru     = $true
                ErrorAction  = 'Stop'
            }

            if ($PSBoundParameters.ContainsKey('Credential')) {
                $startParams['Credential'] = $Credential
            }

            try {
                $mstscProcess = Start-Process @startParams
                $exitSuccess = ($mstscProcess.ExitCode -eq 0)

                $resultMessage = if ($exitSuccess) {
                    '[OK] Shadow session ended normally'
                } else {
                    "[WARN] mstsc.exe exited with code $($mstscProcess.ExitCode)"
                }

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.RdpSessionAction'
                    ComputerName = $ComputerName
                    SessionID    = $SessionID
                    Action       = 'Shadow'
                    ControlMode  = $ControlMode
                    Success      = $exitSuccess
                    ExitCode     = $mstscProcess.ExitCode
                    Message      = $resultMessage
                    Timestamp    = Get-Date -Format 'o'
                }

                if ($exitSuccess) {
                    Write-Information -MessageData "[OK] Shadow session ended for session $SessionID on $ComputerName" -InformationAction Continue
                    Write-Information -MessageData '[INFO] Use Ctrl+* (numpad asterisk) next time to exit shadow mode early' -InformationAction Continue
                } else {
                    Write-Warning "[$($MyInvocation.MyCommand)] $resultMessage"
                }
            } catch {
                Write-Error ("[$($MyInvocation.MyCommand)] Failed to launch mstsc.exe for " +
                    "shadow session $SessionID on $ComputerName -- $_")
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
