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

        $resetScriptBlock = {
            param(
                [bool]$DoNetworkReset
            )

            $failures = [System.Collections.Generic.List[string]]::new()
            $notes    = [System.Collections.Generic.List[string]]::new()

            # ----------------------------------------------------------------
            # Step 1 — Stop services: BITS, wuauserv, appidsvc, cryptsvc
            # ----------------------------------------------------------------
            $servicesToStop  = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
            $stoppedServices = [System.Collections.Generic.List[string]]::new()

            foreach ($svcName in $servicesToStop) {
                try {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -ne 'Stopped') {
                        Stop-Service -Name $svcName -Force -ErrorAction Stop
                        $stoppedServices.Add($svcName)
                    }
                } catch {
                    $failures.Add("Stop service '$svcName': $_")
                }
            }

            # Allow services to fully stop before filesystem operations
            Start-Sleep -Seconds 2

            # ----------------------------------------------------------------
            # Step 2 — Delete qmgr*.dat files
            # ----------------------------------------------------------------
            $qmgrFolder = Join-Path -Path $env:ALLUSERSPROFILE `
                -ChildPath 'Application Data\Microsoft\Network\Downloader'
            $qmgrCount = 0

            if (Test-Path -Path $qmgrFolder -PathType Container) {
                $qmgrFiles = Get-ChildItem -Path $qmgrFolder -Filter 'qmgr*.dat' `
                    -Force -ErrorAction SilentlyContinue
                foreach ($f in $qmgrFiles) {
                    try {
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                        $qmgrCount++
                    } catch {
                        $failures.Add("Delete '$($f.FullName)': $_")
                    }
                }
            }

            # ----------------------------------------------------------------
            # Step 3 — Backup-rename SoftwareDistribution and Catroot2
            # ----------------------------------------------------------------
            $sdPath     = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution'
            $sdBak      = "${sdPath}.bak"
            $cr2Path    = Join-Path -Path $env:SystemRoot -ChildPath 'System32\Catroot2'
            $cr2Bak     = "${cr2Path}.bak"
            $sdBackupResult  = ''
            $cr2BackupResult = ''

            foreach ($pair in @(
                [pscustomobject]@{ Src = $sdPath;  Bak = $sdBak;  ResultVar = 'sd'  }
                [pscustomobject]@{ Src = $cr2Path; Bak = $cr2Bak; ResultVar = 'cr2' }
            )) {
                if (Test-Path -Path $pair.Src -PathType Container) {
                    # Tolerate a pre-existing .bak — remove it or suffix it
                    if (Test-Path -Path $pair.Bak) {
                        try {
                            Remove-Item -LiteralPath $pair.Bak -Recurse -Force -ErrorAction Stop
                        } catch {
                            # Could not remove existing .bak — use a timestamped suffix
                            $suffix   = Get-Date -Format 'yyyyMMddHHmmss'
                            $pair.Bak = "$($pair.Bak).$suffix"
                        }
                    }
                    try {
                        Rename-Item -LiteralPath $pair.Src -NewName ([System.IO.Path]::GetFileName($pair.Bak)) `
                            -ErrorAction Stop
                        if ($pair.ResultVar -eq 'sd') {
                            $sdBackupResult = $pair.Bak
                        } else {
                            $cr2BackupResult = $pair.Bak
                        }
                    } catch {
                        $failures.Add("Backup '$($pair.Src)': $_")
                        if ($pair.ResultVar -eq 'sd') {
                            $sdBackupResult = "Skipped: $_"
                        } else {
                            $cr2BackupResult = "Skipped: $_"
                        }
                    }
                } else {
                    if ($pair.ResultVar -eq 'sd') {
                        $sdBackupResult = 'Skipped: folder not present'
                    } else {
                        $cr2BackupResult = 'Skipped: folder not present'
                    }
                }
            }

            # ----------------------------------------------------------------
            # Step 4 — Remove WindowsUpdate.log
            # ----------------------------------------------------------------
            $wuLog = Join-Path -Path $env:SystemRoot -ChildPath 'WindowsUpdate.log'
            if (Test-Path -Path $wuLog -PathType Leaf) {
                try {
                    Remove-Item -LiteralPath $wuLog -Force -ErrorAction Stop
                } catch {
                    $failures.Add("Remove WindowsUpdate.log: $_")
                }
            }

            # ----------------------------------------------------------------
            # Step 5 — Reset service SDDL for BITS and wuauserv
            # ----------------------------------------------------------------
            $scPath       = Join-Path -Path $env:SystemRoot -ChildPath 'System32\sc.exe'
            $defaultSddl  = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'

            foreach ($svcTarget in @('bits', 'wuauserv')) {
                $scResult = Invoke-NativeCommand -FilePath $scPath `
                    -ArgumentList @('sdset', $svcTarget, $defaultSddl)
                if ($scResult.ExitCode -ne 0) {
                    $failures.Add("sc.exe sdset $svcTarget exited $($scResult.ExitCode): $($scResult.Output)")
                }
            }

            # ----------------------------------------------------------------
            # Step 6 — Reregister Windows Update DLLs
            # ----------------------------------------------------------------
            $regsvr32Path = Join-Path -Path $env:SystemRoot -ChildPath 'System32\regsvr32.exe'
            $dllNames     = @(
                'atl', 'urlmon', 'mshtml', 'shdocvw', 'browseui', 'jscript', 'vbscript',
                'scrrun', 'msxml', 'msxml3', 'msxml6', 'actxprxy', 'softpub', 'wintrust',
                'dssenh', 'rsaenh', 'gpkcsp', 'sccbase', 'slbcsp', 'cryptdlg', 'oleaut32',
                'ole32', 'shell32', 'initpki', 'wuapi', 'wuaueng', 'wuaueng1', 'wucltui',
                'wups', 'wups2', 'wuweb', 'qmgr', 'qmgrprxy', 'wucltux', 'muweb', 'wuwebv'
            )
            $dllsRegistered = 0
            $dllsFailed     = 0

            foreach ($dll in $dllNames) {
                $dllPath = Join-Path -Path $env:SystemRoot -ChildPath "System32\${dll}.dll"
                if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
                    # Missing DLL on this OS build is non-fatal
                    $dllsFailed++
                    $failures.Add("DLL not found (non-fatal): $dllPath")
                    continue
                }
                $regResult = Invoke-NativeCommand -FilePath $regsvr32Path `
                    -ArgumentList @('/s', $dllPath)
                if ($regResult.ExitCode -eq 0) {
                    $dllsRegistered++
                } else {
                    $dllsFailed++
                    $failures.Add("regsvr32 failed for '${dll}.dll' (exit $($regResult.ExitCode)): $($regResult.Output)")
                }
            }

            # ----------------------------------------------------------------
            # Steps 7 & 8 — Network reset (optional, gated by DoNetworkReset)
            # ----------------------------------------------------------------
            $networkResetPerformed = $false
            $rebootRequired        = $false
            $netshPath             = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'

            if ($DoNetworkReset) {
                # Step 7 — netsh winsock reset
                $winsockResult = Invoke-NativeCommand -FilePath $netshPath `
                    -ArgumentList @('winsock', 'reset')
                if ($winsockResult.ExitCode -eq 0) {
                    $networkResetPerformed = $true
                    $rebootRequired        = $true
                } else {
                    $failures.Add("netsh winsock reset exited $($winsockResult.ExitCode): $($winsockResult.Output)")
                }

                # Step 8 — netsh winhttp reset proxy
                $winhttpResult = Invoke-NativeCommand -FilePath $netshPath `
                    -ArgumentList @('winhttp', 'reset', 'proxy')
                if ($winhttpResult.ExitCode -ne 0) {
                    $failures.Add("netsh winhttp reset proxy exited $($winhttpResult.ExitCode): $($winhttpResult.Output)")
                }
            }

            # ----------------------------------------------------------------
            # Step 9 — Restart services: cryptsvc, appidsvc, wuauserv, BITS
            # ----------------------------------------------------------------
            $servicesToStart  = @('cryptsvc', 'appidsvc', 'wuauserv', 'BITS')
            $startedServices  = [System.Collections.Generic.List[string]]::new()

            foreach ($svcName in $servicesToStart) {
                try {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($null -ne $svc) {
                        Start-Service -Name $svcName -ErrorAction Stop
                        $startedServices.Add($svcName)
                    }
                } catch {
                    $failures.Add("Start service '$svcName': $_")
                }
            }

            # ----------------------------------------------------------------
            # Step 10 — Trigger detection: wuauclt, fall back to usoclient
            # ----------------------------------------------------------------
            $wuaucltPath   = Join-Path -Path $env:SystemRoot -ChildPath 'System32\wuauclt.exe'
            $usoclientPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\usoclient.exe'

            if (Test-Path -LiteralPath $wuaucltPath -PathType Leaf) {
                $wuaucltResult = Invoke-NativeCommand -FilePath $wuaucltPath `
                    -ArgumentList @('/resetauthorization', '/detectnow')
                if ($wuaucltResult.ExitCode -ne 0) {
                    # wuauclt is deprecated on newer Windows builds; try usoclient
                    $notes.Add("wuauclt exited $($wuaucltResult.ExitCode); attempting usoclient fallback.")
                    if (Test-Path -LiteralPath $usoclientPath -PathType Leaf) {
                        $usoResult = Invoke-NativeCommand -FilePath $usoclientPath `
                            -ArgumentList @('StartScan')
                        if ($usoResult.ExitCode -ne 0) {
                            $failures.Add("usoclient StartScan exited $($usoResult.ExitCode): $($usoResult.Output)")
                        } else {
                            $notes.Add('Detection triggered via usoclient StartScan.')
                        }
                    } else {
                        $notes.Add('usoclient.exe not found; detection trigger skipped.')
                    }
                }
            } else {
                $notes.Add('wuauclt.exe not found on this OS build; falling back to usoclient StartScan.')
                if (Test-Path -LiteralPath $usoclientPath -PathType Leaf) {
                    $usoResult = Invoke-NativeCommand -FilePath $usoclientPath `
                        -ArgumentList @('StartScan')
                    if ($usoResult.ExitCode -ne 0) {
                        $failures.Add("usoclient StartScan exited $($usoResult.ExitCode): $($usoResult.Output)")
                    } else {
                        $notes.Add('Detection triggered via usoclient StartScan.')
                    }
                } else {
                    $notes.Add('Neither wuauclt.exe nor usoclient.exe found; detection trigger skipped.')
                }
            }

            # ----------------------------------------------------------------
            # Determine overall status
            # ----------------------------------------------------------------
            $status = if ($failures.Count -eq 0) {
                'Succeeded'
            } else {
                'PartialSuccess'
            }

            return [PSCustomObject]@{
                Status                     = $status
                ServicesStopped            = @($stoppedServices)
                ServicesStarted            = @($startedServices)
                SoftwareDistributionBackup = $sdBackupResult
                Catroot2Backup             = $cr2BackupResult
                QmgrFilesDeleted           = $qmgrCount
                DllsReregistered           = $dllsRegistered
                DllsFailed                 = $dllsFailed
                NetworkResetPerformed      = $networkResetPerformed
                RebootRequired             = $rebootRequired
                Failures                   = @($failures)
                Notes                      = @($notes)
            }
        }
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
