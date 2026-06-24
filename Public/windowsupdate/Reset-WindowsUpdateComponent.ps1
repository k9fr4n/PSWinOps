#Requires -Version 5.1
function Reset-WindowsUpdateComponent {
    <#
        .SYNOPSIS
            Resets the Windows Update service stack to a clean state

        .DESCRIPTION
            Stops the Windows Update related services, deletes the BITS queue, backs up the
            SoftwareDistribution and Catroot2 folders, resets the BITS and wuauserv service
            security descriptors, and reregisters the Windows Update DLLs before restarting
            the services and triggering a fresh detection. Optionally resets the Winsock and
            WinHTTP proxy network stack. This is the PSWinOps equivalent of
            PSWindowsUpdate's Reset-WUComponents and is used to recover a corrupted Windows
            Update client.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local operations.

        .PARAMETER IncludeNetworkReset
            When specified, also resets the Winsock catalog (netsh winsock reset) and
            WinHTTP proxy settings (netsh winhttp reset proxy).
            WARNING: netsh winsock reset requires a reboot to take effect and resets the
            Winsock catalog. On a remote machine it can drop the WinRM session and
            connectivity until the machine is rebooted. Sets RebootRequired = $true.

        .EXAMPLE
            Reset-WindowsUpdateComponent

            Resets the Windows Update component stack on the local computer.

        .EXAMPLE
            Reset-WindowsUpdateComponent -ComputerName 'SRV01'

            Resets the Windows Update component stack on the remote server SRV01.

        .EXAMPLE
            Reset-WindowsUpdateComponent -ComputerName 'SRV01' -IncludeNetworkReset

            Resets the Windows Update stack on SRV01 and additionally resets the Winsock
            catalog and WinHTTP proxy. A reboot will be required on SRV01 after this runs.

        .EXAMPLE
            'SRV01', 'SRV02' | Reset-WindowsUpdateComponent

            Resets the Windows Update component stack on SRV01 and SRV02 via pipeline.

        .OUTPUTS
            PSWinOps.WindowsUpdateResetResult
            Returns one object per machine with ComputerName, Status, ServicesStopped,
            ServicesStarted, backup paths, DLL counts, network reset flags, Failures,
            Notes, and Timestamp.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-06-24
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (stops/starts services, edits SDDL, deletes system folders)
            WARNING: -IncludeNetworkReset resets Winsock/WinHTTP and requires a reboot; may drop a remote session.

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/additional-resources-for-windows-update
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.WindowsUpdateResetResult')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeNetworkReset
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $resetScriptBlock = ${Function:Invoke-WindowsUpdateReset}
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$computer'"

            # Elevation guard — local execution requires Administrator privileges
            if (-not (Test-IsAdministrator)) {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Administrator privileges are required. Failed on '$computer'."
                [PSCustomObject]@{
                    PSTypeName                 = 'PSWinOps.WindowsUpdateResetResult'
                    ComputerName               = $computer
                    Status                     = 'Failed'
                    ServicesStopped            = @()
                    ServicesStarted            = @()
                    SoftwareDistributionBackup = ''
                    Catroot2Backup             = ''
                    QmgrFilesDeleted           = 0
                    DllsReregistered           = 0
                    DllsFailed                 = 0
                    NetworkResetPerformed      = $false
                    RebootRequired             = $false
                    Failures                   = @('Not elevated: Administrator privileges required.')
                    Notes                      = @()
                    Timestamp                  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
                continue
            }

            # Main ShouldProcess gate
            $mainAction = 'Reset Windows Update service components. Cleanup SoftwareDistribution & Catroot2 folder, reset service security descriptors, and reregister Windows Update DLLs'
            if (-not $PSCmdlet.ShouldProcess($computer, $mainAction)) {
                continue
            }

            # Sub-check for destructive network reset
            $doNetworkReset = $false
            if ($IncludeNetworkReset) {
                $networkAction = 'Reset Winsock catalog and WinHTTP proxy settings (requires reboot; may drop remote WinRM session)'
                $doNetworkReset = $PSCmdlet.ShouldProcess($computer, $networkAction)
            }

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $resetScriptBlock
                    ArgumentList = @([bool]$doNetworkReset)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawResult = Invoke-RemoteOrLocal @invokeParams

                [PSCustomObject]@{
                    PSTypeName                 = 'PSWinOps.WindowsUpdateResetResult'
                    ComputerName               = $computer
                    Status                     = $rawResult.Status
                    ServicesStopped            = $rawResult.ServicesStopped
                    ServicesStarted            = $rawResult.ServicesStarted
                    SoftwareDistributionBackup = $rawResult.SoftwareDistributionBackup
                    Catroot2Backup             = $rawResult.Catroot2Backup
                    QmgrFilesDeleted           = $rawResult.QmgrFilesDeleted
                    DllsReregistered           = $rawResult.DllsReregistered
                    DllsFailed                 = $rawResult.DllsFailed
                    NetworkResetPerformed      = $rawResult.NetworkResetPerformed
                    RebootRequired             = $rawResult.RebootRequired
                    Failures                   = $rawResult.Failures
                    Notes                      = $rawResult.Notes
                    Timestamp                  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${computer}': $_"
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
