#Requires -Version 5.1
function Get-DiskSpace {
    <#
        .SYNOPSIS
            Retrieves disk space information from local or remote computers

        .DESCRIPTION
            Queries Win32_LogicalDisk via CIM to return disk usage statistics for fixed
            drives (DriveType 3). Calculates percentage free and applies configurable
            warning and critical thresholds to set a health status per volume.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER WarningThreshold
            Percentage of free space below which the status is set to Warning.
            Defaults to 20 percent.

        .PARAMETER CriticalThreshold
            Percentage of free space below which the status is set to Critical.
            Defaults to 10 percent.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-DiskSpace

            Retrieves disk space for all fixed drives on the local computer.

        .EXAMPLE
            Get-DiskSpace -ComputerName 'SRV01' -WarningThreshold 30 -CriticalThreshold 15

            Retrieves disk space from SRV01 with custom alert thresholds.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-DiskSpace

            Retrieves disk space from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.DiskSpace
            Returns one object per fixed drive with size, free space, usage
            percentages, and a health status based on configurable thresholds.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DiskSpace')]
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

        $scriptBlock = {
            @(Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3' -ErrorAction Stop)
        }

        if ($CriticalThreshold -ge $WarningThreshold) {
            Write-Warning -Message "[$($MyInvocation.MyCommand)] CriticalThreshold ($CriticalThreshold%) is >= WarningThreshold ($WarningThreshold%). Adjusting CriticalThreshold to $($WarningThreshold - 1)%."
            $CriticalThreshold = $WarningThreshold - 1
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying Win32_LogicalDisk on '$machine'"
                $disks = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential)

                $displayName = $machine

                foreach ($disk in $disks) {
                    $sizeGB = [math]::Round($disk.Size / 1GB, 2)
                    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                    $usedGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)

                    $percentFree = if ($disk.Size -gt 0) {
                        [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
                    }
                    else { 0 }

                    $percentUsed = [math]::Round(100 - $percentFree, 1)

                    $status = if ($percentFree -le $CriticalThreshold) {
                        'Critical'
                    }
                    elseif ($percentFree -le $WarningThreshold) {
                        'Warning'
                    }
                    else {
                        'OK'
                    }

                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.DiskSpace'
                        ComputerName = $displayName
                        DriveLetter  = $disk.DeviceID
                        VolumeName   = $disk.VolumeName
                        FileSystem   = $disk.FileSystem
                        SizeGB       = $sizeGB
                        FreeSpaceGB  = $freeGB
                        UsedSpaceGB  = $usedGB
                        PercentFree  = $percentFree
                        PercentUsed  = $percentUsed
                        Status       = $status
                        Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
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
