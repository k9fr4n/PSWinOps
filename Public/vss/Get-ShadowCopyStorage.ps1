#Requires -Version 5.1
function Get-ShadowCopyStorage {
    <#
        .SYNOPSIS
            Show VSS storage allocation per volume on local or remote computers

        .DESCRIPTION
            Retrieves Volume Shadow Copy storage allocation details using Win32_ShadowStorage via CIM.
            Reports used space, allocated space, maximum space, and snapshot count per volume.
            Supports filtering by drive letter and remote execution via Invoke-RemoteOrLocal.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.

        .PARAMETER DriveLetter
            Single drive letter (A-Z) to filter storage information for a specific volume.

        .PARAMETER Credential
            PSCredential object for remote authentication.

        .EXAMPLE
            Get-ShadowCopyStorage

            Shows VSS storage allocation for all volumes on the local computer.

        .EXAMPLE
            Get-ShadowCopyStorage -ComputerName 'SRV01' -DriveLetter 'C'

            Shows VSS storage allocation for the C: drive on remote server SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-ShadowCopyStorage -Credential (Get-Credential)

            Shows VSS storage allocation on SRV01 and SRV02 using alternate credentials.

        .OUTPUTS
            PSWinOps.ShadowCopyStorage
            Returns objects with ComputerName, DriveLetter, UsedSpaceBytes, UsedSpaceMB,
            AllocatedSpaceMB, MaxSpaceMB, UsedPercent, SnapshotCount, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges for VSS queries

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-shadowstorage
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ShadowCopyStorage')]
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

        $unboundedThreshold = 1PB

        $driveLetterArg = if ($PSBoundParameters.ContainsKey('DriveLetter')) { $DriveLetter } else { '' }

        $scriptBlock = {
            param([string]$FilterDriveLetter)

            $volumeIndex = @{}
            foreach ($vol in (Get-CimInstance -ClassName Win32_Volume -ErrorAction SilentlyContinue)) {
                if ($vol.DeviceID -and $vol.DriveLetter) {
                    # Normalize: lowercase, strip trailing backslash for reliable matching
                    $normalizedId = $vol.DeviceID.TrimEnd('\').ToLower()
                    $volumeIndex[$normalizedId] = $vol.DriveLetter.TrimEnd(':')
                }
            }

            $shadowCountIndex = @{}
            foreach ($shadow in (Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction SilentlyContinue)) {
                $normalizedVol = $shadow.VolumeName.TrimEnd('\').ToLower()
                if ($shadowCountIndex.ContainsKey($normalizedVol)) {
                    $shadowCountIndex[$normalizedVol] += 1
                }
                else {
                    $shadowCountIndex[$normalizedVol] = 1
                }
            }

            $storageEntries = Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop

            foreach ($storage in $storageEntries) {
                $volumeRef = $storage.Volume.ToString()
                $deviceId = ''
                if ($volumeRef -match 'DeviceID="([^"]+)"') {
                    $deviceId = ($Matches[1] -replace '\\\\', '\').TrimEnd('\').ToLower()
                }

                $resolvedDrive = if ($deviceId -ne '' -and $volumeIndex.ContainsKey($deviceId)) {
                    $volumeIndex[$deviceId]
                }
                else {
                    '?'
                }

                if ($FilterDriveLetter -ne '' -and $resolvedDrive -ne $FilterDriveLetter) {
                    continue
                }

                $snapshotCount = if ($deviceId -ne '' -and $shadowCountIndex.ContainsKey($deviceId)) {
                    $shadowCountIndex[$deviceId]
                }
                else {
                    0
                }

                # MaxSpace can be UInt64.MaxValue (18446744073709551615) when unbounded
                # which overflows [long]/Int64. Detect and normalise to -1.
                $maxSpaceRaw = $storage.MaxSpace
                $maxSpaceLong = if ($maxSpaceRaw -is [UInt64] -and $maxSpaceRaw -gt [long]::MaxValue) {
                    [long]-1
                }
                else {
                    [long]$maxSpaceRaw
                }

                [PSCustomObject]@{
                    DriveLetter    = $resolvedDrive
                    DeviceID       = $deviceId
                    UsedSpace      = [long]$storage.UsedSpace
                    AllocatedSpace = [long]$storage.AllocatedSpace
                    MaxSpace       = $maxSpaceLong
                    SnapshotCount  = [int]$snapshotCount
                }
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying VSS storage on '$machine'"

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
                    $isUnbounded = ($item.MaxSpace -eq -1) -or ($item.MaxSpace -lt 0) -or ($item.MaxSpace -gt $unboundedThreshold)

                    $maxSpaceMB = if ($isUnbounded) { 'Unbounded' } else { [math]::Round($item.MaxSpace / 1MB, 2) }
                    $usedPercent = if ($isUnbounded -or $item.MaxSpace -eq 0) {
                        0
                    }
                    else {
                        [math]::Round(($item.UsedSpace / $item.MaxSpace) * 100, 1)
                    }

                    [PSCustomObject]@{
                        PSTypeName       = 'PSWinOps.ShadowCopyStorage'
                        ComputerName     = $machine
                        DriveLetter      = $item.DriveLetter
                        UsedSpaceBytes   = [long]$item.UsedSpace
                        UsedSpaceMB      = [math]::Round($item.UsedSpace / 1MB, 2)
                        AllocatedSpaceMB = [math]::Round($item.AllocatedSpace / 1MB, 2)
                        MaxSpaceMB       = $maxSpaceMB
                        UsedPercent      = $usedPercent
                        SnapshotCount    = [int]$item.SnapshotCount
                        Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
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
