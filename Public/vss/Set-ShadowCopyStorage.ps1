#Requires -Version 5.1
function Set-ShadowCopyStorage {
    <#
        .SYNOPSIS
            Configure the maximum shadow copy storage size for a specified drive

        .DESCRIPTION
            Sets or modifies the maximum shadow copy (VSS) storage allocation for a given drive letter.
            Uses vssadmin resize shadowstorage which is more reliable than Set-CimInstance for
            modifying Win32_ShadowStorage. Supports both explicit size limits and unbounded storage.

        .PARAMETER DriveLetter
            The single drive letter (A-Z) to configure shadow copy storage for.

        .PARAMETER MaxSizeMB
            The maximum shadow copy storage size in megabytes. Valid range is 1 to 10485760 MB.

        .PARAMETER Unbounded
            Sets the shadow copy storage to unbounded (no maximum limit).

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.

        .PARAMETER Credential
            Optional credential for remote execution.

        .EXAMPLE
            Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 20480

            Sets the VSS max storage for drive C: to 20480 MB on the local machine.

        .EXAMPLE
            Set-ShadowCopyStorage -DriveLetter 'D' -Unbounded -ComputerName 'SRV01'

            Sets the VSS storage for drive D: to unbounded on remote server SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Set-ShadowCopyStorage -DriveLetter 'C' -MaxSizeMB 10240

            Sets the VSS max storage for drive C: to 10240 MB on multiple remote servers.

        .OUTPUTS
            PSWinOps.ShadowCopyStorageResult
            Returns an object with ComputerName, DriveLetter, PreviousMaxSpaceMB, NewMaxSpaceMB,
            Success, Message, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (vssadmin requires elevation)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/vssadmin-resize-shadowstorage
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'BySize')]
    [OutputType('PSWinOps.ShadowCopyStorageResult')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter,

        [Parameter(Mandatory = $true, ParameterSetName = 'BySize')]
        [ValidateRange(1, 10485760)]
        [long]$MaxSizeMB,

        [Parameter(Mandatory = $true, ParameterSetName = 'Unbounded')]
        [switch]$Unbounded,

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

        $DriveLetter = $DriveLetter.ToUpper()

        if ($Unbounded) {
            $effectiveMaxSizeMB = -1
            $displaySize = 'Unbounded'
        } else {
            $effectiveMaxSizeMB = $MaxSizeMB
            $displaySize = "$MaxSizeMB MB"
        }

        $scriptBlock = {
            param(
                [string]$DrvLetter,
                [long]$MaxMB
            )

            $previousMaxSpaceBytes = 0

            try {
                $storageList = Get-CimInstance -ClassName 'Win32_ShadowStorage' -ErrorAction Stop
                foreach ($storageItem in $storageList) {
                    $volumeRef = $storageItem.Volume
                    if ($null -ne $volumeRef) {
                        $volDeviceId = $volumeRef.ToString()
                        $allVolumes = Get-CimInstance -ClassName 'Win32_Volume' -ErrorAction SilentlyContinue
                        foreach ($volObj in $allVolumes) {
                            if ($volObj.DriveLetter -eq "${DrvLetter}:" -and $volDeviceId -like "*$($volObj.DeviceID)*") {
                                $previousMaxSpaceBytes = $storageItem.MaxSpace
                                break
                            }
                        }
                    }
                }
            } catch {
                $previousMaxSpaceBytes = 0
            }

            if ($MaxMB -eq -1) {
                $vssArgs = "resize shadowstorage /For=${DrvLetter}: /On=${DrvLetter}: /MaxSize=UNBOUNDED"
            } else {
                $vssArgs = "resize shadowstorage /For=${DrvLetter}: /On=${DrvLetter}: /MaxSize=${MaxMB}MB"
            }

            $processInfo = New-Object -TypeName 'System.Diagnostics.ProcessStartInfo'
            $processInfo.FileName = 'vssadmin.exe'
            $processInfo.Arguments = $vssArgs
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true

            $proc = New-Object -TypeName 'System.Diagnostics.Process'
            $proc.StartInfo = $processInfo
            $null = $proc.Start()
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            $exitCode = $proc.ExitCode

            $combinedOutput = $stdout.Trim()
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $combinedOutput = $combinedOutput + ' ' + $stderr.Trim()
            }

            @{
                DriveLetter           = $DrvLetter
                PreviousMaxSpaceBytes = $previousMaxSpaceBytes
                NewMaxSizeArg         = $MaxMB
                ExitCode              = $exitCode
                Output                = $combinedOutput
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $shouldProcessTarget = "Set VSS max storage on $machine for ${DriveLetter}: to $displaySize"

            if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, 'Set-ShadowCopyStorage')) {
                continue
            }

            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$machine' - Drive ${DriveLetter}: --> $displaySize"

            try {
                $invokeParams = @{
                    ComputerName = $machine
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @($DriveLetter, $effectiveMaxSizeMB)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $raw = Invoke-RemoteOrLocal @invokeParams

                $previousMB = 0
                if ($raw.PreviousMaxSpaceBytes -gt 0) {
                    $previousMB = [math]::Round($raw.PreviousMaxSpaceBytes / 1MB, 2)
                }

                $isSuccess = ($raw.ExitCode -eq 0)

                $newMaxDisplay = if ($raw.NewMaxSizeArg -eq -1) {
                    'Unbounded' 
                } else {
                    [math]::Round($raw.NewMaxSizeArg, 2) 
                }

                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.ShadowCopyStorageResult'
                    ComputerName       = $machine
                    DriveLetter        = $raw.DriveLetter
                    PreviousMaxSpaceMB = $previousMB
                    NewMaxSpaceMB      = $newMaxDisplay
                    Success            = $isSuccess
                    Message            = $raw.Output
                    Timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"

                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.ShadowCopyStorageResult'
                    ComputerName       = $machine
                    DriveLetter        = $DriveLetter
                    PreviousMaxSpaceMB = 0
                    NewMaxSpaceMB      = $displaySize
                    Success            = $false
                    Message            = "Error: $_"
                    Timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
