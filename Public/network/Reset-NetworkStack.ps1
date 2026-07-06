#Requires -Version 5.1

function Reset-NetworkStack {
    <#
    .SYNOPSIS
        Reset the Windows network stack (winsock, TCP/IP, DNS cache, ARP)

    .DESCRIPTION
        Encapsulates the classic netsh network-repair sequence (netsh winsock reset and
        netsh int ip reset) plus a DNS client cache flush and ARP cache clear into one
        idempotent, ShouldProcess-guarded action. Returns a structured result listing
        each step that ran with its exit code, overall success, and RebootRequired
        (always true). Requires administrator privileges and ALWAYS needs a reboot to
        finalize. WARNING: on a remote target `netsh int ip reset` can drop the WinRM
        session mid-run, so verify results out-of-band after running remotely.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote computers. Ignored for
        local machine operations.

    .PARAMETER IncludeFirewall
        Opt-in switch. Adds a `netsh advfirewall reset` step, which is more intrusive
        (resets all Windows Firewall profiles and rules to their default state).

    .PARAMETER SkipDnsFlush
        Opt-in switch. Skips the DNS client cache flush step (Clear-DnsClientCache).

    .EXAMPLE
        Reset-NetworkStack
        Local usage example.

    .EXAMPLE
        Reset-NetworkStack -ComputerName SRV01 -IncludeFirewall
        Remote single-machine example.

    .EXAMPLE
        'SRV01', 'SRV02' | Reset-NetworkStack -SkipDnsFlush
        Pipeline usage example.

    .OUTPUTS
        PSWinOps.NetworkStackResetResult
        One object per target machine describing the steps that ran, their exit
        codes, overall Success, and RebootRequired (always $true).

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-06
        Requires: PowerShell 5.1+ / Windows only
        Requires: Administrator privileges (winsock/int ip/advfirewall reset)
        WARNING: netsh int ip reset can drop the WinRM session on a remote target
        mid-run; verify results out-of-band after running remotely.

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-interface-ip
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.NetworkStackResetResult')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeFirewall,

        [Parameter(Mandatory = $false)]
        [switch]$SkipDnsFlush
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network stack reset"

        if (-not (Test-IsAdministrator)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new('Reset-NetworkStack requires Administrator privileges.'),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }

        $netshPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
        if (-not (Test-Path -Path $netshPath -PathType Leaf)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new("netsh.exe not found at '$netshPath'."),
                    'NetshNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $netshPath
                )
            )
        }

        $resetScriptBlock = {
            param(
                [string]$NetshPath,
                [bool]$SkipDns,
                [bool]$IncludeFw
            )

            $stepsRun = [System.Collections.Generic.List[psobject]]::new()

            # WinsockReset — always run
            $winsockResult = Invoke-NativeCommand -FilePath $NetshPath -ArgumentList @('winsock', 'reset')
            $stepsRun.Add([PSCustomObject]@{ Step = 'WinsockReset'; ExitCode = $winsockResult.ExitCode })

            # IpReset — always run (may drop WinRM on a remote target)
            $ipResult = Invoke-NativeCommand -FilePath $NetshPath -ArgumentList @('int', 'ip', 'reset')
            $stepsRun.Add([PSCustomObject]@{ Step = 'IpReset'; ExitCode = $ipResult.ExitCode })

            # DnsFlush — skipped when SkipDns is set
            if (-not $SkipDns) {
                try {
                    Clear-DnsClientCache -ErrorAction Stop
                    $stepsRun.Add([PSCustomObject]@{ Step = 'DnsFlush'; ExitCode = 0 })
                } catch {
                    $stepsRun.Add([PSCustomObject]@{ Step = 'DnsFlush'; ExitCode = 1 })
                }
            }

            # ArpClear — always run
            try {
                Clear-Arp -Confirm:$false -ErrorAction Stop
                $stepsRun.Add([PSCustomObject]@{ Step = 'ArpClear'; ExitCode = 0 })
            } catch {
                $stepsRun.Add([PSCustomObject]@{ Step = 'ArpClear'; ExitCode = 1 })
            }

            # FirewallReset — opt-in only
            if ($IncludeFw) {
                $fwResult = Invoke-NativeCommand -FilePath $NetshPath -ArgumentList @('advfirewall', 'reset')
                $stepsRun.Add([PSCustomObject]@{ Step = 'FirewallReset'; ExitCode = $fwResult.ExitCode })
            }

            $overallSuccess = -not ($stepsRun | Where-Object { $_.ExitCode -ne 0 })

            [PSCustomObject]@{
                StepsRun = $stepsRun.ToArray()
                Success  = [bool]$overallSuccess
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $shouldProcessTarget = "network stack on $targetComputer"
                $shouldProcessAction = 'Reset (winsock + int ip + dns + arp' + $(if ($IncludeFirewall) { ' + firewall' } else { '' }) + ')'

                if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, $shouldProcessAction)) {
                    continue
                }

                $invokeParams = @{
                    ComputerName = $targetComputer
                    ScriptBlock  = $resetScriptBlock
                    ArgumentList = @($netshPath, [bool]$SkipDnsFlush, [bool]$IncludeFirewall)
                    Credential   = $Credential
                }

                $rawResult = Invoke-RemoteOrLocal @invokeParams

                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.NetworkStackResetResult'
                    ComputerName   = $targetComputer
                    StepsRun       = $rawResult.StepsRun
                    Success        = $rawResult.Success
                    RebootRequired = $true
                    Timestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network stack reset"
    }
}
