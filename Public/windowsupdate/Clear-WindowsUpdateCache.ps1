#Requires -Version 5.1
function Clear-WindowsUpdateCache {
    <#
        .SYNOPSIS
            Clears the Windows Update download cache to free disk space

        .DESCRIPTION
            Stops the Windows Update (wuaserv) and BITS services, removes all files
            from the SoftwareDistribution\Download folder, then restarts both services.
            Reports the amount of disk space freed.
            This is useful when the cache becomes corrupted, takes up excessive space,
            or when troubleshooting Windows Update failures. The cache is automatically
            rebuilt on the next update scan.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local operations.

        .PARAMETER IncludeDataStore
            When specified, also clears the DataStore folder which contains the
            Windows Update database. This forces a full resync with the update
            source. Use with caution.

        .EXAMPLE
            Clear-WindowsUpdateCache

            Clears the download cache on the local computer.

        .EXAMPLE
            Clear-WindowsUpdateCache -ComputerName 'SRV01' -IncludeDataStore

            Clears both the download cache and the DataStore on SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Clear-WindowsUpdateCache

            Clears the download cache on SRV01 and SRV02 via pipeline.

        .OUTPUTS
            PSWinOps.WindowsUpdateCacheResult
            Returns objects with ComputerName, CachePath, FileCount, SizeFreedMB,
            DataStoreCleared, Result, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (to stop services and delete cache)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/additional-resources-for-windows-update
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.WindowsUpdateCacheResult')]
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
        [switch]$IncludeDataStore
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $clearScriptBlock = {
            param(
                [bool]$ClearDataStore
            )

            $basePath = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution'
            $downloadPath = Join-Path -Path $basePath -ChildPath 'Download'
            $dataStorePath = Join-Path -Path $basePath -ChildPath 'DataStore'

            # Measure cache size before clearing
            $totalSize = 0
            $totalFiles = 0

            if (Test-Path -Path $downloadPath -PathType Container) {
                $items = Get-ChildItem -Path $downloadPath -Recurse -Force -ErrorAction SilentlyContinue
                $totalFiles = @($items | Where-Object -FilterScript { -not $_.PSIsContainer }).Count
                $totalSize = ($items | Measure-Object -Property 'Length' -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $totalSize) {
                    $totalSize = 0
                }
            }

            if ($ClearDataStore -and (Test-Path -Path $dataStorePath -PathType Container)) {
                $dsItems = Get-ChildItem -Path $dataStorePath -Recurse -Force -ErrorAction SilentlyContinue
                $dsFileCount = @($dsItems | Where-Object -FilterScript { -not $_.PSIsContainer }).Count
                $dsSize = ($dsItems | Measure-Object -Property 'Length' -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $dsSize) {
                    $dsSize = 0
                }
                $totalFiles += $dsFileCount
                $totalSize += $dsSize
            }

            # Stop services
            $servicesToStop = @('wuauserv', 'bits', 'cryptsvc')
            $stoppedServices = [System.Collections.Generic.List[string]]::new()

            foreach ($svcName in $servicesToStop) {
                try {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -eq 'Running') {
                        Stop-Service -Name $svcName -Force -ErrorAction Stop
                        $stoppedServices.Add($svcName)
                    }
                } catch {
                    Write-Warning "Could not stop service '$svcName': $_"
                }
            }

            # Wait for services to fully stop
            Start-Sleep -Seconds 2

            # Clear download cache
            $errors = [System.Collections.Generic.List[string]]::new()

            if (Test-Path -Path $downloadPath -PathType Container) {
                try {
                    Get-ChildItem -Path $downloadPath -Force -ErrorAction Stop |
                        Remove-Item -Recurse -Force -ErrorAction Stop
                } catch {
                    $errors.Add("Download folder: $_")
                }
            }

            # Clear DataStore if requested
            if ($ClearDataStore -and (Test-Path -Path $dataStorePath -PathType Container)) {
                try {
                    Get-ChildItem -Path $dataStorePath -Force -ErrorAction Stop |
                        Remove-Item -Recurse -Force -ErrorAction Stop
                } catch {
                    $errors.Add("DataStore folder: $_")
                }
            }

            # Restart services
            foreach ($svcName in $stoppedServices) {
                try {
                    Start-Service -Name $svcName -ErrorAction Stop
                } catch {
                    $errors.Add("Failed to restart service '$svcName': $_")
                }
            }

            $result = if ($errors.Count -eq 0) {
                'Succeeded'
            } else {
                'PartialSuccess'
            }

            return [PSCustomObject]@{
                CachePath        = $downloadPath
                FileCount        = $totalFiles
                SizeBytes        = $totalSize
                DataStoreCleared = $ClearDataStore
                Result           = $result
                Errors           = @($errors)
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$computer'"

            $targetDesc = if ($IncludeDataStore) {
                "Clear Windows Update cache + DataStore on '$computer'"
            } else {
                "Clear Windows Update download cache on '$computer'"
            }

            if (-not $PSCmdlet.ShouldProcess($computer, $targetDesc)) {
                continue
            }

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $clearScriptBlock
                    ArgumentList = @([bool]$IncludeDataStore)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $clearResult = Invoke-RemoteOrLocal @invokeParams

                $sizeFreedMB = [math]::Round($clearResult.SizeBytes / 1MB, 2)

                if ($clearResult.Errors.Count -gt 0) {
                    foreach ($err in $clearResult.Errors) {
                        Write-Warning -Message "[$($MyInvocation.MyCommand)] '$computer' — $err"
                    }
                }

                Write-Verbose -Message "[$($MyInvocation.MyCommand)] '$computer' — Freed $sizeFreedMB MB ($($clearResult.FileCount) files)"

                [PSCustomObject]@{
                    PSTypeName       = 'PSWinOps.WindowsUpdateCacheResult'
                    ComputerName     = $computer
                    CachePath        = $clearResult.CachePath
                    FileCount        = $clearResult.FileCount
                    SizeFreedMB      = $sizeFreedMB
                    DataStoreCleared = $clearResult.DataStoreCleared
                    Result           = $clearResult.Result
                    Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
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
