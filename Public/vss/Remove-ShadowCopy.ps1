#Requires -Version 5.1
function Remove-ShadowCopy {
    <#
        .SYNOPSIS
            Remove one or more VSS shadow copies from target computers

        .DESCRIPTION
            Deletes Volume Shadow Copy Service snapshots either by their specific shadow copy ID
            or by drive letter with an optional age filter. Supports pipeline input from
            Get-ShadowCopy for streamlined bulk removal workflows.

        .PARAMETER ShadowCopyId
            One or more shadow copy GUIDs to remove. Accepts pipeline input by property name
            from Get-ShadowCopy output objects.

        .PARAMETER DriveLetter
            Single letter (A-Z) identifying the volume whose shadow copies should be removed.
            Used with the ByDrive parameter set.

        .PARAMETER OlderThanDays
            When used with DriveLetter, only removes shadow copies older than the specified
            number of days. Valid range is 1 to 3650.

        .PARAMETER ComputerName
            One or more target computer names. Defaults to the local machine.
            Accepts pipeline input by property name.

        .PARAMETER Credential
            Optional credential for remote execution. When omitted the current
            user context is used.

        .EXAMPLE
            Remove-ShadowCopy -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}'

            Removes a specific shadow copy by ID on the local computer.

        .EXAMPLE
            Remove-ShadowCopy -DriveLetter 'C' -ComputerName 'SRV01'

            Removes all shadow copies for volume C: on the remote server SRV01.

        .EXAMPLE
            Get-ShadowCopy -ComputerName 'SRV01' | Remove-ShadowCopy

            Pipes shadow copy objects from Get-ShadowCopy to remove them.

        .EXAMPLE
            Remove-ShadowCopy -DriveLetter 'D' -OlderThanDays 30 -ComputerName 'SRV01', 'SRV02'

            Removes shadow copies older than 30 days on volume D: across two remote servers.

        .OUTPUTS
            PSWinOps.ShadowCopyRemoveResult
            Returns one object per shadow copy processed with ComputerName, ShadowCopyId,
            DriveLetter, Removed, ErrorMessage and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/vss/volume-shadow-copy-service-overview
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    [OutputType('PSWinOps.ShadowCopyRemoveResult')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ShadowCopyId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByDrive')]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByDrive')]
        [ValidateRange(1, 3650)]
        [int]$OlderThanDays,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
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
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting - ParameterSet: $($PSCmdlet.ParameterSetName)"

        $scriptBlock = {
            param(
                [string]$Mode,
                [string]$DataJson,
                [int]$AgeDays
            )

            $resultList = [System.Collections.Generic.List[hashtable]]::new()

            try {
                if ($Mode -eq 'ById') {
                    $idArray = $DataJson | ConvertFrom-Json

                    foreach ($shadowId in $idArray) {
                        $entry = @{
                            ShadowCopyId = $shadowId
                            DriveLetter  = ''
                            Removed      = $false
                            ErrorMessage = ''
                        }

                        try {
                            $shadow = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop |
                                Where-Object -Property ID -EQ -Value $shadowId

                            if (-not $shadow) {
                                $entry['ErrorMessage'] = "Shadow copy not found: ${shadowId}"
                                $resultList.Add($entry)
                                continue
                            }

                            $volFilter = "DeviceID='$($shadow.VolumeName.Replace('\','\\'))'"
                            $vol = Get-CimInstance -ClassName Win32_Volume -Filter $volFilter -ErrorAction SilentlyContinue
                            if ($vol -and $vol.DriveLetter) {
                                $entry['DriveLetter'] = $vol.DriveLetter.TrimEnd(':')
                            }

                            $shadow | Remove-CimInstance -ErrorAction Stop
                            $entry['Removed'] = $true
                        } catch {
                            $entry['ErrorMessage'] = $_.ToString()
                        }

                        $resultList.Add($entry)
                    }
                } elseif ($Mode -eq 'ByDrive') {
                    $drvLetter = $DataJson
                    $filterString = "DriveLetter='${drvLetter}:'"
                    $volume = Get-CimInstance -ClassName Win32_Volume -Filter $filterString -ErrorAction Stop

                    if (-not $volume) {
                        $resultList.Add(@{
                                ShadowCopyId = ''
                                DriveLetter  = $drvLetter
                                Removed      = $false
                                ErrorMessage = "Volume not found: ${drvLetter}:"
                            })
                        return $resultList.ToArray()
                    }

                    $shadows = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop |
                        Where-Object -Property VolumeName -EQ -Value $volume.DeviceID

                    if ($AgeDays -gt 0) {
                        $cutoffDate = (Get-Date).AddDays(-$AgeDays)
                        $shadows = $shadows | Where-Object -FilterScript { $_.InstallDate -lt $cutoffDate }
                    }

                    if (-not $shadows) {
                        $resultList.Add(@{
                                ShadowCopyId = ''
                                DriveLetter  = $drvLetter
                                Removed      = $false
                                ErrorMessage = 'No matching shadow copies found'
                            })
                        return $resultList.ToArray()
                    }

                    foreach ($shadow in $shadows) {
                        $entry = @{
                            ShadowCopyId = $shadow.ID
                            DriveLetter  = $drvLetter
                            Removed      = $false
                            ErrorMessage = ''
                        }

                        try {
                            $shadow | Remove-CimInstance -ErrorAction Stop
                            $entry['Removed'] = $true
                        } catch {
                            $entry['ErrorMessage'] = $_.ToString()
                        }

                        $resultList.Add($entry)
                    }
                }
            } catch {
                $resultList.Add(@{
                        ShadowCopyId = ''
                        DriveLetter  = ''
                        Removed      = $false
                        ErrorMessage = $_.ToString()
                    })
            }

            return $resultList.ToArray()
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            switch ($PSCmdlet.ParameterSetName) {
                'ById' {
                    $confirmedIds = [System.Collections.Generic.List[string]]::new()
                    foreach ($shadowId in $ShadowCopyId) {
                        if ($PSCmdlet.ShouldProcess($machine, "Remove shadow copy ${shadowId}")) {
                            $confirmedIds.Add($shadowId)
                        }
                    }

                    if ($confirmedIds.Count -eq 0) {
                        continue 
                    }

                    try {
                        $idsJson = $confirmedIds.ToArray() | ConvertTo-Json -Compress
                        if ($confirmedIds.Count -eq 1) {
                            $idsJson = "[${idsJson}]"
                        }

                        $invokeParams = @{
                            ComputerName = $machine
                            ScriptBlock  = $scriptBlock
                            ArgumentList = @('ById', $idsJson, 0)
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $invokeParams['Credential'] = $Credential
                        }

                        $rawResults = Invoke-RemoteOrLocal @invokeParams

                        foreach ($entry in $rawResults) {
                            [PSCustomObject]@{
                                PSTypeName   = 'PSWinOps.ShadowCopyRemoveResult'
                                ComputerName = $machine
                                ShadowCopyId = $entry.ShadowCopyId
                                DriveLetter  = if ($entry.DriveLetter) {
                                    $entry.DriveLetter.ToUpper() 
                                } else {
                                    '' 
                                }
                                Removed      = $entry.Removed
                                ErrorMessage = $entry.ErrorMessage
                                Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                    } catch {
                        Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"

                        foreach ($shadowId in $confirmedIds) {
                            [PSCustomObject]@{
                                PSTypeName   = 'PSWinOps.ShadowCopyRemoveResult'
                                ComputerName = $machine
                                ShadowCopyId = $shadowId
                                DriveLetter  = ''
                                Removed      = $false
                                ErrorMessage = "Exception: $_"
                                Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                    }
                }

                'ByDrive' {
                    $driveUpper = $DriveLetter.ToUpper()
                    $ageFilter = if ($PSBoundParameters.ContainsKey('OlderThanDays')) {
                        $OlderThanDays 
                    } else {
                        0 
                    }
                    $shouldProcessMsg = "Remove shadow copies for volume ${driveUpper}:"
                    if ($ageFilter -gt 0) {
                        $shouldProcessMsg = "${shouldProcessMsg} older than ${ageFilter} days"
                    }

                    if (-not $PSCmdlet.ShouldProcess($machine, $shouldProcessMsg)) {
                        continue 
                    }

                    try {
                        $invokeParams = @{
                            ComputerName = $machine
                            ScriptBlock  = $scriptBlock
                            ArgumentList = @('ByDrive', $driveUpper, $ageFilter)
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $invokeParams['Credential'] = $Credential
                        }

                        $rawResults = Invoke-RemoteOrLocal @invokeParams

                        foreach ($entry in $rawResults) {
                            [PSCustomObject]@{
                                PSTypeName   = 'PSWinOps.ShadowCopyRemoveResult'
                                ComputerName = $machine
                                ShadowCopyId = $entry.ShadowCopyId
                                DriveLetter  = if ($entry.DriveLetter) {
                                    $entry.DriveLetter.ToUpper() 
                                } else {
                                    $driveUpper 
                                }
                                Removed      = $entry.Removed
                                ErrorMessage = $entry.ErrorMessage
                                Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                    } catch {
                        Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"

                        [PSCustomObject]@{
                            PSTypeName   = 'PSWinOps.ShadowCopyRemoveResult'
                            ComputerName = $machine
                            ShadowCopyId = ''
                            DriveLetter  = $driveUpper
                            Removed      = $false
                            ErrorMessage = "Exception: $_"
                            Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        }
                    }
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
