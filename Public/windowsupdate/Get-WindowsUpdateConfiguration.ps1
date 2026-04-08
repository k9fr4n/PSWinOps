#Requires -Version 5.1
function Get-WindowsUpdateConfiguration {
    <#
        .SYNOPSIS
            Retrieves Windows Update configuration from local or remote computers

        .DESCRIPTION
            Reads Windows Update configuration from the registry on local or remote computers.
            The function queries two registry paths under HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
            to retrieve WSUS, Windows Update for Business (WUFB), and Auto Update GPO settings.
            When the WindowsUpdate policy key exists, the computer is considered GPO-configured.
            The UpdateSource property is determined by analyzing UseWUServer, WUServer, and deferral
            settings to classify the source as WSUS, WUFB, WindowsUpdate, or Unknown.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local queries or when the current user has sufficient permissions.

        .EXAMPLE
            Get-WindowsUpdateConfiguration

            Retrieves Windows Update configuration from the local computer.

        .EXAMPLE
            Get-WindowsUpdateConfiguration -ComputerName 'SRV01' -Credential (Get-Credential)

            Retrieves Windows Update configuration from SRV01 using explicit credentials.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-WindowsUpdateConfiguration | Where-Object -Property UpdateSource -NE -Value 'WSUS'

            Queries multiple servers via pipeline and filters for those not using WSUS.

        .OUTPUTS
            PSWinOps.WindowsUpdateConfiguration
            Returns an object per computer with UpdateSource, WSUS URLs, auto-update settings,
            deferral policies, branch readiness level, target group, and GPO configuration status.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.WindowsUpdateConfiguration')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $auOptionsMap = @{
            1 = 'Disabled'
            2 = 'NotifyDownload'
            3 = 'AutoDownload'
            4 = 'ScheduledInstall'
            5 = 'AllowLocalAdmin'
        }

        $scheduledInstallDayMap = @{
            0 = 'EveryDay'
            1 = 'Sunday'
            2 = 'Monday'
            3 = 'Tuesday'
            4 = 'Wednesday'
            5 = 'Thursday'
            6 = 'Friday'
            7 = 'Saturday'
        }

        $branchReadinessMap = @{
            16 = 'SemiAnnualPreview'
            32 = 'SemiAnnual'
            64 = 'LongTermServicing'
        }

        $registryScriptBlock = {
            $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            $auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'

            $gpoConfigured = Test-Path -Path $wuPath
            $wuProps = Get-ItemProperty -Path $wuPath -ErrorAction SilentlyContinue
            $auProps = Get-ItemProperty -Path $auPath -ErrorAction SilentlyContinue

            [PSCustomObject]@{
                IsGPOConfigured                = $gpoConfigured
                WUServer                       = $wuProps.WUServer
                WUStatusServer                 = $wuProps.WUStatusServer
                TargetGroup                    = $wuProps.TargetGroup
                TargetGroupEnabled             = $wuProps.TargetGroupEnabled
                DeferFeatureUpdates            = $wuProps.DeferFeatureUpdates
                DeferFeatureUpdatesPeriodInDays = $wuProps.DeferFeatureUpdatesPeriodInDays
                DeferQualityUpdates            = $wuProps.DeferQualityUpdates
                DeferQualityUpdatesPeriodInDays = $wuProps.DeferQualityUpdatesPeriodInDays
                BranchReadinessLevel           = $wuProps.BranchReadinessLevel
                PauseFeatureUpdatesStartTime   = $wuProps.PauseFeatureUpdatesStartTime
                PauseQualityUpdatesStartTime   = $wuProps.PauseQualityUpdatesStartTime
                UseWUServer                    = $auProps.UseWUServer
                NoAutoUpdate                   = $auProps.NoAutoUpdate
                AUOptions                      = $auProps.AUOptions
                ScheduledInstallDay            = $auProps.ScheduledInstallDay
                ScheduledInstallTime           = $auProps.ScheduledInstallTime
                NoAutoRebootWithLoggedOnUsers  = $auProps.NoAutoRebootWithLoggedOnUsers
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing $computer"

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $registryScriptBlock
                }

                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawData = Invoke-RemoteOrLocal @invokeParams

                # Determine UpdateSource
                $updateSource = 'Unknown'
                if ($rawData.UseWUServer -eq 1 -and -not [string]::IsNullOrEmpty($rawData.WUServer)) {
                    $updateSource = 'WSUS'
                }
                elseif ($rawData.DeferFeatureUpdates -eq 1 -or $rawData.DeferQualityUpdates -eq 1) {
                    $updateSource = 'WUFB'
                }
                elseif ($rawData.IsGPOConfigured -eq $false) {
                    $updateSource = 'WindowsUpdate'
                }

                # Map AUOptions
                $mappedAUOption = $null
                if ($null -ne $rawData.AUOptions) {
                    $mappedAUOption = $auOptionsMap[[int]$rawData.AUOptions]
                }

                # Map ScheduledInstallDay
                $mappedInstallDay = $null
                if ($null -ne $rawData.ScheduledInstallDay) {
                    $mappedInstallDay = $scheduledInstallDayMap[[int]$rawData.ScheduledInstallDay]
                }

                # Map BranchReadinessLevel
                $mappedBranchReadiness = $null
                if ($null -ne $rawData.BranchReadinessLevel) {
                    $mappedBranchReadiness = $branchReadinessMap[[int]$rawData.BranchReadinessLevel]
                }

                [PSCustomObject]@{
                    PSTypeName                    = 'PSWinOps.WindowsUpdateConfiguration'
                    ComputerName                  = $computer
                    UpdateSource                  = $updateSource
                    WUServerUrl                   = $rawData.WUServer
                    WUStatusServerUrl             = $rawData.WUStatusServer
                    UseWUServer                   = ($rawData.UseWUServer -eq 1)
                    AutoUpdateEnabled             = ($rawData.NoAutoUpdate -ne 1)
                    AutoUpdateOption              = $mappedAUOption
                    ScheduledInstallDay           = $mappedInstallDay
                    ScheduledInstallTime          = $rawData.ScheduledInstallTime
                    NoAutoRebootWithLoggedOnUsers = ($rawData.NoAutoRebootWithLoggedOnUsers -eq 1)
                    DeferFeatureUpdatesDays       = $rawData.DeferFeatureUpdatesPeriodInDays
                    DeferQualityUpdatesDays       = $rawData.DeferQualityUpdatesPeriodInDays
                    BranchReadinessLevel          = $mappedBranchReadiness
                    PauseFeatureUpdatesStartTime  = $rawData.PauseFeatureUpdatesStartTime
                    PauseQualityUpdatesStartTime  = $rawData.PauseQualityUpdatesStartTime
                    TargetGroup                   = $rawData.TargetGroup
                    TargetGroupEnabled            = ($rawData.TargetGroupEnabled -eq 1)
                    IsGPOConfigured               = $rawData.IsGPOConfigured
                    Timestamp                     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to retrieve Windows Update configuration from ${computer}: $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}