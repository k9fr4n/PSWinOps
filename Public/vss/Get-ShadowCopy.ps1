#Requires -Version 5.1
function Get-ShadowCopy {
    <#
        .SYNOPSIS
            List existing Volume Shadow Copies on local or remote Windows computers

        .DESCRIPTION
            Retrieves all Volume Shadow Copy snapshots using Win32_ShadowCopy via CIM.
            Supports filtering by drive letter, remote execution via Invoke-RemoteOrLocal,
            and pipeline input for multiple computer names.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.

        .PARAMETER DriveLetter
            Single drive letter (A-Z) to filter shadow copies for a specific volume.

        .PARAMETER Credential
            PSCredential object for remote authentication.

        .EXAMPLE
            Get-ShadowCopy

            Lists all shadow copies on the local computer.

        .EXAMPLE
            Get-ShadowCopy -ComputerName 'SRV01' -DriveLetter 'C'

            Lists shadow copies for the C: drive on remote server SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ShadowCopy -Credential (Get-Credential)

            Lists all shadow copies on SRV01 and SRV02 using alternate credentials.

        .OUTPUTS
            PSWinOps.ShadowCopy
            Returns objects with ComputerName, ShadowCopyId, DriveLetter, VolumeName,
            CreationTime, DeviceObject, ProviderName, State, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges for remote queries

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-shadowcopy
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ShadowCopy')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # VSS_SNAPSHOT_STATE enum — https://learn.microsoft.com/en-us/windows/win32/api/vss/ne-vss-vss_snapshot_state
        $stateMap = @{
            0  = 'Unknown'
            1  = 'Preparing'
            2  = 'ProcessingPrepare'
            3  = 'Prepared'
            4  = 'ProcessingPreCommit'
            5  = 'PreCommitted'
            6  = 'ProcessingCommit'
            7  = 'Committed'
            8  = 'ProcessingPostCommit'
            9  = 'ProcessingPreFinalCommit'
            10 = 'PreFinalCommitted'
            11 = 'ProcessingFinalCommit'
            12 = 'Created'
            13 = 'Aborted'
            14 = 'Deleted'
        }

        $driveLetterArg = if ($PSBoundParameters.ContainsKey('DriveLetter')) { $DriveLetter } else { '' }

        $scriptBlock = {
            param([string]$FilterDriveLetter)

            $volumeIndex = @{}
            foreach ($vol in (Get-CimInstance -ClassName Win32_Volume -ErrorAction SilentlyContinue)) {
                if ($vol.DeviceID) {
                    $normalizedId = $vol.DeviceID.TrimEnd('\').ToLower()
                    if ($vol.DriveLetter) {
                        $volumeIndex[$normalizedId] = $vol.DriveLetter.TrimEnd(':')
                    }
                    elseif ($vol.Label) {
                        $volumeIndex[$normalizedId] = "[$($vol.Label)]"
                    }
                    elseif ($vol.DeviceID -match '\{([^}]+)\}') {
                        $volumeIndex[$normalizedId] = $Matches[1].Substring(0, 8)
                    }
                }
            }

            $targetDeviceId = ''
            if ($FilterDriveLetter -ne '') {
                $filterExpression = "DriveLetter='$($FilterDriveLetter):'"
                $targetVolume = Get-CimInstance -ClassName Win32_Volume -Filter $filterExpression -ErrorAction SilentlyContinue
                if ($targetVolume) {
                    $targetDeviceId = $targetVolume.DeviceID.TrimEnd('\').ToLower()
                }
                else {
                    return
                }
            }

            $shadows = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop

            foreach ($shadow in $shadows) {
                $normalizedVolName = $shadow.VolumeName.TrimEnd('\').ToLower()

                if ($targetDeviceId -ne '' -and $normalizedVolName -ne $targetDeviceId) {
                    continue
                }
                $resolvedDrive = if ($volumeIndex.ContainsKey($normalizedVolName)) {
                    $volumeIndex[$normalizedVolName]
                }
                else {
                    '?'
                }

                [PSCustomObject]@{
                    ShadowCopyId = $shadow.ID
                    DriveLetter  = $resolvedDrive
                    VolumeName   = $shadow.VolumeName
                    CreationTime = $shadow.InstallDate
                    DeviceObject = $shadow.DeviceObject
                    ProviderName = $shadow.ProviderName
                    StateCode    = $shadow.State
                }
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying shadow copies on '$machine'"

            try {
                $invokeParams = @{
                    ComputerName = $machine
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @($driveLetterArg)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $raw = Invoke-RemoteOrLocal @invokeParams

                foreach ($item in $raw) {
                    $mappedState = if ($stateMap.ContainsKey([int]$item.StateCode)) {
                        $stateMap[[int]$item.StateCode]
                    }
                    else {
                        'Unknown'
                    }

                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.ShadowCopy'
                        ComputerName = $machine
                        ShadowCopyId = $item.ShadowCopyId
                        DriveLetter  = $item.DriveLetter
                        VolumeName   = $item.VolumeName
                        CreationTime = $item.CreationTime
                        DeviceObject = $item.DeviceObject
                        ProviderName = $item.ProviderName
                        State        = $mappedState
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
