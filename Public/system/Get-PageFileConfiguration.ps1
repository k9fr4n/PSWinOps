#Requires -Version 5.1
function Get-PageFileConfiguration {
    <#
        .SYNOPSIS
            Retrieves pagefile configuration and usage from local or remote computers

        .DESCRIPTION
            Queries Win32_ComputerSystem, Win32_PageFileSetting, and Win32_PageFileUsage via CIM
            to return detailed pagefile configuration, current usage, and system memory information.
            Supports pipeline input and remote execution with optional credentials.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for remote authentication.
            Not used when targeting the local machine.

        .EXAMPLE
            Get-PageFileConfiguration

            Retrieves pagefile configuration from the local computer.

        .EXAMPLE
            Get-PageFileConfiguration -ComputerName 'SRV01'

            Retrieves pagefile configuration from a single remote server.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-PageFileConfiguration

            Retrieves pagefile configuration from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.PageFileConfiguration
            Returns one object per pagefile found on each target computer,
            including path, sizes, current usage, and auto-managed status.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pagefilesetting
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.PageFileConfiguration')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            @{
                ComputerSystem  = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop
                PageFileSettings = @(Get-CimInstance -ClassName 'Win32_PageFileSetting' -ErrorAction Stop)
                PageFileUsages   = @(Get-CimInstance -ClassName 'Win32_PageFileUsage' -ErrorAction Stop)
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying pagefile configuration on '$machine'"
                $rawData = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                $compSystem = $rawData.ComputerSystem
                $pageFileSettings = @($rawData.PageFileSettings)
                $pageFileUsages = @($rawData.PageFileUsages)

                $displayName = $machine
                $ramTotalGB = [decimal][math]::Round($compSystem.TotalPhysicalMemory / 1GB, 2)
                $autoManaged = [bool]$compSystem.AutomaticManagedPagefile

                # Build a lookup of usage by pagefile path for O(1) access
                $usageIndex = @{}
                foreach ($usageEntry in $pageFileUsages) {
                    $usageIndex[$usageEntry.Name] = $usageEntry
                }

                if ($pageFileSettings.Count -gt 0) {
                    foreach ($pageFile in $pageFileSettings) {
                        $driveLetter = if ($pageFile.Name -and $pageFile.Name.Length -ge 2) {
                            $pageFile.Name.Substring(0, 2)
                        }
                        else {
                            'N/A'
                        }

                        $usage = $usageIndex[$pageFile.Name]

                        [PSCustomObject]@{
                            PSTypeName          = 'PSWinOps.PageFileConfiguration'
                            ComputerName        = $displayName
                            DriveLetter         = $driveLetter
                            PageFilePath        = $pageFile.Name
                            InitialSizeMB       = [int]$pageFile.InitialSize
                            MaximumSizeMB       = [int]$pageFile.MaximumSize
                            CurrentUsageMB      = if ($usage) { [int]$usage.CurrentUsage } else { 0 }
                            AllocatedSizeMB     = if ($usage) { [int]$usage.AllocatedBaseSize } else { 0 }
                            PeakUsageMB         = if ($usage) { [int]$usage.PeakUsage } else { 0 }
                            AutoManagedPagefile = $autoManaged
                            RamTotalGB          = $ramTotalGB
                            EnsureCompleteDump  = $false
                            RestartRequired     = $false
                            Status              = 'Current'
                            Timestamp           = Get-Date -Format 'o'
                        }
                    }
                }
                elseif ($autoManaged) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] System-managed pagefile on '$machine'"

                    $firstUsage = if ($pageFileUsages.Count -gt 0) { $pageFileUsages[0] } else { $null }

                    [PSCustomObject]@{
                        PSTypeName          = 'PSWinOps.PageFileConfiguration'
                        ComputerName        = $displayName
                        DriveLetter         = 'N/A'
                        PageFilePath        = 'System Managed'
                        InitialSizeMB       = 0
                        MaximumSizeMB       = 0
                        CurrentUsageMB      = if ($firstUsage) { [int]$firstUsage.CurrentUsage } else { 0 }
                        AllocatedSizeMB     = if ($firstUsage) { [int]$firstUsage.AllocatedBaseSize } else { 0 }
                        PeakUsageMB         = if ($firstUsage) { [int]$firstUsage.PeakUsage } else { 0 }
                        AutoManagedPagefile = $autoManaged
                        RamTotalGB          = $ramTotalGB
                        EnsureCompleteDump  = $false
                        RestartRequired     = $false
                        Status              = 'Current'
                        Timestamp           = Get-Date -Format 'o'
                    }
                }
                else {
                    Write-Warning "[$($MyInvocation.MyCommand)] No pagefile configured on '$machine'"
                }
            }
            catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query '$machine': $_"
                continue
            }

        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
