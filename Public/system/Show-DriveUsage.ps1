#Requires -Version 5.1
function Show-DriveUsage {
    <#
    .SYNOPSIS
        Shows fixed-volume disk usage as a visual bar per drive

    .DESCRIPTION
        A presentation wrapper over Get-DiskSpace: it calls Get-DiskSpace
        internally and re-emits the same per-volume data under the
        PSWinOps.DriveUsage type, whose default format view renders a fixed-width
        usage bar. This command owns no CIM code and adds no second data path -
        use Get-DiskSpace when you want the numeric view to script against, and
        Show-DriveUsage when you want the at-a-glance bar in the console.

    .PARAMETER ComputerName
        One or more computer names to query. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER WarningThreshold
        Percentage of free space below which the status is set to Warning.
        Forwarded to Get-DiskSpace. Defaults to 20 percent.

    .PARAMETER CriticalThreshold
        Percentage of free space below which the status is set to Critical.
        Forwarded to Get-DiskSpace. Defaults to 10 percent.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote computers.
        Not used for local queries.

    .EXAMPLE
        Show-DriveUsage

        Shows a usage bar for every fixed volume on the local computer.

    .EXAMPLE
        Show-DriveUsage -ComputerName 'SRV01'

        Shows a usage bar for every fixed volume on SRV01.

    .EXAMPLE
        'SRV01', 'SRV02' | Show-DriveUsage

        Shows usage bars for multiple servers via the pipeline.

    .OUTPUTS
        PSWinOps.DriveUsage
        Returns one object per fixed volume with size, used, free, usage
        percentages and a health status. The default view renders a usage bar.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-18
        Requires: PowerShell 5.1+ / Windows only

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DriveUsage')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$WarningThreshold = 20,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$CriticalThreshold = 10,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying disk usage on '$machine'"

                $diskParams = @{
                    ComputerName      = $machine
                    WarningThreshold  = $WarningThreshold
                    CriticalThreshold = $CriticalThreshold
                    ErrorAction       = 'Stop'
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $diskParams['Credential'] = $Credential
                }

                $volumes = @(Get-DiskSpace @diskParams)

                foreach ($volume in $volumes) {
                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.DriveUsage'
                        ComputerName = $volume.ComputerName
                        DriveLetter  = $volume.DriveLetter
                        VolumeName   = $volume.VolumeName
                        SizeGB       = $volume.SizeGB
                        UsedGB       = $volume.UsedSpaceGB
                        FreeGB       = $volume.FreeSpaceGB
                        PercentUsed  = $volume.PercentUsed
                        PercentFree  = $volume.PercentFree
                        Status       = $volume.Status
                        Timestamp    = Get-Date -Format 'o'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
