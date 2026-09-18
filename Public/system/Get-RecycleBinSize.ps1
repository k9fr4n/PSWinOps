#Requires -Version 5.1
function Get-RecycleBinSize {
    <#
    .SYNOPSIS
        Reports Recycle Bin size and item count per fixed volume

    .DESCRIPTION
        Enumerates fixed volumes via CIM and measures the contents of each
        volume's hidden $Recycle.Bin folder, returning one object per volume
        with the exact byte size, rounded MB/GB, item count, and the size as a
        percentage of the volume. Local calls run in-process (no WinRM needed);
        remote calls dispatch over WinRM through Invoke-RemoteOrLocal, and only
        the per-volume summary rows cross the wire.

    .PARAMETER ComputerName
        One or more computer names to query. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote computers.
        Not used for local queries.

    .EXAMPLE
        Get-RecycleBinSize

        Reports the Recycle Bin size for every fixed volume on the local computer.

    .EXAMPLE
        Get-RecycleBinSize -ComputerName 'SRV01'

        Reports the Recycle Bin size for every fixed volume on SRV01.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-RecycleBinSize

        Reports Recycle Bin sizes for multiple servers via the pipeline.

    .OUTPUTS
        PSWinOps.RecycleBinSize
        Returns one object per fixed volume with the byte size, rounded MB/GB,
        item count, and the size as a percentage of the volume.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-18
        Requires: PowerShell 5.1+ / Windows only
        Requires: Administrator rights to read other users' Recycle Bins. A
        non-elevated caller can read only its own SID folder under $Recycle.Bin,
        so the reported size can be understated. This is not gated on elevation.

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.RecycleBinSize')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            $volumes = @(Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3' -ErrorAction Stop)

            foreach ($volume in $volumes) {
                # $Recycle.Bin is hidden + system, so -Force is required. A volume
                # with no (or an unreadable) Recycle Bin is a normal state: the
                # SilentlyContinue swallows access-denied and missing-path errors,
                # leaving a zero size rather than skipping the volume.
                $recyclePath = "$($volume.DeviceID)\`$Recycle.Bin"
                $measure = Get-ChildItem -LiteralPath $recyclePath -Force -File -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum

                [PSCustomObject]@{
                    DriveLetter = $volume.DeviceID
                    SizeBytes   = [long]$measure.Sum
                    ItemCount   = [long]$measure.Count
                    VolumeSize  = [long]$volume.Size
                }
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Measuring Recycle Bins on '$machine'"
                $summaries = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential)

                foreach ($summary in $summaries) {
                    $sizeBytes = [long]$summary.SizeBytes
                    $volumeSize = [long]$summary.VolumeSize

                    $percentOfVolume = if ($volumeSize -gt 0) {
                        [math]::Round(($sizeBytes / $volumeSize) * 100, 2)
                    }
                    else { 0 }

                    [PSCustomObject]@{
                        PSTypeName      = 'PSWinOps.RecycleBinSize'
                        ComputerName    = $machine
                        DriveLetter     = $summary.DriveLetter
                        SizeBytes       = $sizeBytes
                        SizeMB          = [math]::Round($sizeBytes / 1MB, 2)
                        SizeGB          = [math]::Round($sizeBytes / 1GB, 2)
                        ItemCount       = [long]$summary.ItemCount
                        PercentOfVolume = $percentOfVolume
                        Timestamp       = Get-Date -Format 'o'
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
