#Requires -Version 5.1
function Install-WindowsUpdate {
    <#
        .SYNOPSIS
            Installs available Windows Updates on local or remote computers

        .DESCRIPTION
            Scans for available Windows Updates, downloads them if not already cached,
            then installs them using the COM API (Microsoft.Update.Session).
            Internally calls Get-WindowsUpdate to discover available updates, downloads
            any that are not yet cached, then installs each one using IUpdateInstaller.
            A progress bar displays installation status with estimated time remaining.
            Returns detailed results for each update including success/failure status
            and whether a reboot is required.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local queries.

        .PARAMETER MicrosoftUpdate
            When specified, queries the full Microsoft Update catalog instead of the
            machine's configured source (WSUS, WUFB, or Windows Update).

        .PARAMETER KBArticleID
            Optional filter to install only updates matching the specified KB article IDs.
            Accepts one or more KB identifiers with or without the 'KB' prefix.

        .PARAMETER Classification
            Optional filter to install only updates matching the specified classifications.
            When not specified, all classifications are installed.

        .PARAMETER Product
            Optional filter to install only updates matching the specified product names.
            When not specified, all products are installed.

        .PARAMETER IncludeHidden
            When specified, includes updates that have been hidden (declined).

        .PARAMETER AcceptEula
            When specified, automatically accepts the End User License Agreement for each
            update before installation. Required for updates whose EULA has not been
            previously accepted.

        .PARAMETER AutoReboot
            When specified, automatically restarts the computer after installation if any
            installed update requires a reboot. Use with caution.

        .EXAMPLE
            Install-WindowsUpdate -AcceptEula

            Installs all available updates on the local computer, accepting EULAs.

        .EXAMPLE
            Install-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441' -AcceptEula

            Installs a specific update on SRV01, accepting the EULA automatically.

        .EXAMPLE
            'SRV01', 'SRV02' | Install-WindowsUpdate -Classification 'Security Updates' -AcceptEula -AutoReboot

            Installs security updates on SRV01 and SRV02 with automatic reboot if required.

        .OUTPUTS
            PSWinOps.WindowsUpdateInstallResult
            Returns objects with ComputerName, Title, KBArticle, SizeMB, Result, HResult,
            RebootRequired, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges for installing updates

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iupdateinstaller
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.WindowsUpdateInstallResult')]
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
        [switch]$MicrosoftUpdate,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KBArticleID,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Classification,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Product,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeHidden,

        [Parameter(Mandatory = $false)]
        [switch]$AcceptEula,

        [Parameter(Mandatory = $false)]
        [switch]$AutoReboot
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $resultCodeMap = @{
            0 = 'NotStarted'
            1 = 'InProgress'
            2 = 'Succeeded'
            3 = 'SucceededWithErrors'
            4 = 'Failed'
            5 = 'Aborted'
        }

        $installScriptBlock = {
            param(
                [string]$UpdateIdToInstall,
                [bool]$UseMicrosoftUpdate,
                [bool]$DoAcceptEula
            )

            try {
                $session = New-Object -ComObject 'Microsoft.Update.Session'
                $session.ClientApplicationID = 'PSWinOps'
                $searcher = $session.CreateUpdateSearcher()

                if ($UseMicrosoftUpdate) {
                    $serviceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
                    $serviceManager.ClientApplicationID = 'PSWinOps'
                    $service = $serviceManager.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
                    $searcher.ServerSelection = 3
                    $searcher.ServiceID = $service.ServiceID
                }

                $searchResult = $searcher.Search("UpdateID='$UpdateIdToInstall'")

                if ($searchResult.Updates.Count -eq 0) {
                    throw "Update '$UpdateIdToInstall' not found"
                }

                $update = $searchResult.Updates.Item(0)

                if ($DoAcceptEula -and -not $update.EulaAccepted) {
                    $update.AcceptEula()
                }

                if (-not $update.EulaAccepted) {
                    throw "EULA not accepted for '$($update.Title)'. Use -AcceptEula to accept automatically."
                }

                $updateColl = New-Object -ComObject 'Microsoft.Update.UpdateColl'
                $updateColl.Add($update) | Out-Null

                # Download if not already cached
                if (-not $update.IsDownloaded) {
                    $downloader = $session.CreateUpdateDownloader()
                    $downloader.Updates = $updateColl
                    $dlResult = $downloader.Download()
                    if ($dlResult.ResultCode -eq 4 -or $dlResult.ResultCode -eq 5) {
                        throw "Download failed for '$($update.Title)' (HResult: 0x$($dlResult.HResult.ToString('X8')))"
                    }
                }

                # Install
                $installer = $session.CreateUpdateInstaller()
                $installer.Updates = $updateColl
                $installResult = $installer.Install()

                return [PSCustomObject]@{
                    ResultCode     = [int]$installResult.ResultCode
                    HResult        = [int]$installResult.HResult
                    RebootRequired = [bool]$installResult.RebootRequired
                }
            } catch {
                throw "Failed to install update '$UpdateIdToInstall': $_"
            }
        }

        $rebootScriptBlock = {
            Restart-Computer -Force
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$computer'"

            try {
                # Step 1: Scan for available updates using Get-WindowsUpdate
                $getParams = @{ ComputerName = $computer }
                if ($MicrosoftUpdate) {
                    $getParams['MicrosoftUpdate'] = $true
                }
                if ($KBArticleID) {
                    $getParams['KBArticleID'] = $KBArticleID
                }
                if ($Classification) {
                    $getParams['Classification'] = $Classification
                }
                if ($Product) {
                    $getParams['Product'] = $Product
                }
                if ($IncludeHidden) {
                    $getParams['IncludeHidden'] = $true
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $getParams['Credential'] = $Credential
                }

                $activityLabel = "Install-WindowsUpdate — $computer"

                # Step 1: Scan
                Write-Progress -Activity $activityLabel -Status 'Scanning for available updates...' -PercentComplete 0
                $updates = @(Get-WindowsUpdate @getParams)
                Write-Progress -Activity $activityLabel -Status 'Scan complete' -PercentComplete 0

                if ($updates.Count -eq 0) {
                    Write-Progress -Activity $activityLabel -Completed
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No updates to install on '$computer'"
                    continue
                }

                $totalUpdates = $updates.Count
                $totalSizeMB = ($updates | Measure-Object -Property 'SizeMB' -Sum).Sum
                Write-Information -MessageData "[$($MyInvocation.MyCommand)] $computer — $totalUpdates update(s) to install ($([math]::Round($totalSizeMB, 1)) MB)" -InformationAction Continue

                # Step 2: Install each update with progress
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $rebootNeeded = $false

                for ($i = 0; $i -lt $totalUpdates; $i++) {
                    $update = $updates[$i]
                    $kbLabel = if ($update.KBArticle) {
                        " ($($update.KBArticle))"
                    } else {
                        ''
                    }

                    # Progress
                    $percentComplete = [math]::Min([math]::Floor($i / $totalUpdates * 100), 99)
                    $elapsedSec = $stopwatch.Elapsed.TotalSeconds
                    $avgPerUpdate = if ($i -gt 0) {
                        $elapsedSec / $i
                    } else {
                        0
                    }
                    $etaSeconds = if ($avgPerUpdate -gt 0) {
                        [int](($totalUpdates - $i) * $avgPerUpdate)
                    } else {
                        -1
                    }

                    $progressParams = @{
                        Activity         = $activityLabel
                        Status           = "($($i + 1)/$totalUpdates) Downloading + installing..."
                        CurrentOperation = "$($update.Title)$kbLabel [$($update.SizeMB) MB]"
                        PercentComplete  = $percentComplete
                    }
                    if ($etaSeconds -ge 0) {
                        $progressParams['SecondsRemaining'] = $etaSeconds
                    }

                    Write-Progress @progressParams

                    if ($PSCmdlet.ShouldProcess("$($update.Title)$kbLabel [$($update.SizeMB) MB]", "Install update on '$computer'")) {
                        $invokeParams = @{
                            ComputerName = $computer
                            ScriptBlock  = $installScriptBlock
                            ArgumentList = @($update.UpdateId, [bool]$MicrosoftUpdate, [bool]$AcceptEula)
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $invokeParams['Credential'] = $Credential
                        }

                        try {
                            $instResult = Invoke-RemoteOrLocal @invokeParams

                            $resultString = if ($resultCodeMap.ContainsKey($instResult.ResultCode)) {
                                $resultCodeMap[$instResult.ResultCode]
                            } else {
                                'Unknown'
                            }

                            if ($instResult.RebootRequired) {
                                $rebootNeeded = $true
                            }

                            $hResultHex = if ($instResult.HResult -ne 0) {
                                '0x{0:X8}' -f $instResult.HResult
                            } else {
                                '0x00000000'
                            }

                            [PSCustomObject]@{
                                PSTypeName     = 'PSWinOps.WindowsUpdateInstallResult'
                                ComputerName   = $computer
                                Title          = $update.Title
                                KBArticle      = $update.KBArticle
                                SizeMB         = $update.SizeMB
                                Result         = $resultString
                                HResult        = $hResultHex
                                RebootRequired = $instResult.RebootRequired
                                Timestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        } catch {
                            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to install '$($update.Title)' on '${computer}': $_"

                            [PSCustomObject]@{
                                PSTypeName     = 'PSWinOps.WindowsUpdateInstallResult'
                                ComputerName   = $computer
                                Title          = $update.Title
                                KBArticle      = $update.KBArticle
                                SizeMB         = $update.SizeMB
                                Result         = 'Failed'
                                HResult        = 'Error'
                                RebootRequired = $false
                                Timestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                    }
                }

                Write-Progress -Activity $activityLabel -Completed
                $stopwatch.Stop()
                $elapsed = $stopwatch.Elapsed
                Write-Information -MessageData "[$($MyInvocation.MyCommand)] $computer — Done in $($elapsed.ToString('mm\:ss'))" -InformationAction Continue

                # Handle reboot
                if ($rebootNeeded) {
                    if ($AutoReboot) {
                        if ($PSCmdlet.ShouldProcess($computer, 'Restart computer after update installation')) {
                            Write-Warning -Message "[$($MyInvocation.MyCommand)] Restarting '$computer' as required by installed updates"
                            $rebootParams = @{
                                ComputerName = $computer
                                ScriptBlock  = $rebootScriptBlock
                            }
                            if ($PSBoundParameters.ContainsKey('Credential')) {
                                $rebootParams['Credential'] = $Credential
                            }
                            Invoke-RemoteOrLocal @rebootParams
                        }
                    } else {
                        Write-Warning -Message "[$($MyInvocation.MyCommand)] '$computer' requires a reboot to complete update installation. Use -AutoReboot or restart manually."
                    }
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
