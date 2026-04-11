#Requires -Version 5.1
function New-ShadowCopy {
    <#
        .SYNOPSIS
            Create a VSS shadow copy on a specified volume

        .DESCRIPTION
            Creates a Volume Shadow Copy Service (VSS) snapshot for the specified drive letter
            on one or more computers. Uses CIM methods to invoke Win32_ShadowCopy.Create and
            returns a structured result object with the shadow copy ID and status information.

        .PARAMETER DriveLetter
            Single letter (A-Z) identifying the volume to snapshot. Do not include the colon.

        .PARAMETER ComputerName
            One or more target computer names. Defaults to the local machine.
            Accepts pipeline input by property name.

        .PARAMETER Credential
            Optional credential for remote execution. When omitted the current
            user context is used.

        .EXAMPLE
            New-ShadowCopy -DriveLetter 'C'

            Creates a shadow copy of volume C: on the local computer.

        .EXAMPLE
            New-ShadowCopy -DriveLetter 'D' -ComputerName 'SRV01'

            Creates a shadow copy of volume D: on the remote server SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | New-ShadowCopy -DriveLetter 'C' -Credential (Get-Credential)

            Creates a shadow copy of volume C: on SRV01 and SRV02 using explicit credentials.

        .OUTPUTS
            PSWinOps.ShadowCopyResult
            Returns one object per target computer with ComputerName, DriveLetter,
            ShadowCopyId, CreationTime, Success, ReturnCode, ReturnMessage and Timestamp.

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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType('PSWinOps.ShadowCopyResult')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter,

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
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting - Drive: ${DriveLetter}"

        $returnCodeMap = @{
            0 = 'Success'
            1 = 'AccessDenied'
            2 = 'InvalidArgument'
            3 = 'VolumeNotSupported'
            4 = 'InsufficientStorage'
            5 = 'VolumeShadowCopyInProgress'
            6 = 'MaxShadowCopiesReached'
        }

        $scriptBlock = {
            param([string]$drv)

            $resultHash = @{
                ReturnValue = [uint32]99
                ShadowId    = ''
                VolumePath  = ''
            }

            try {
                $filterString = "DriveLetter='${drv}:'"
                $volume = Get-CimInstance -ClassName Win32_Volume -Filter $filterString -ErrorAction Stop

                if (-not $volume) {
                    $resultHash['ReturnValue'] = [uint32]2
                    return $resultHash
                }

                $resultHash['VolumePath'] = $volume.DeviceID

                $cimResult = Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{
                    Volume = $volume.DeviceID
                } -ErrorAction Stop

                $resultHash['ReturnValue'] = [uint32]$cimResult.ReturnValue

                if ($cimResult.ReturnValue -eq 0) {
                    $resultHash['ShadowId'] = $cimResult.ShadowID
                }
            } catch {
                $resultHash['ReturnValue'] = [uint32]99
                $resultHash['ErrorDetail'] = $_.ToString()
            }

            return $resultHash
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            if ($PSCmdlet.ShouldProcess($machine, "Create VSS shadow copy for volume ${DriveLetter}:")) {
                try {
                    $invokeParams = @{
                        ComputerName = $machine
                        ScriptBlock  = $scriptBlock
                        ArgumentList = @($DriveLetter.ToUpper())
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $invokeParams['Credential'] = $Credential
                    }

                    $raw = Invoke-RemoteOrLocal @invokeParams

                    $code = [uint32]$raw.ReturnValue
                    $isSuccess = ($code -eq 0)

                    $message = if ($returnCodeMap.ContainsKey([int]$code)) {
                        $returnCodeMap[[int]$code]
                    } else {
                        'Unknown'
                    }

                    if (-not $isSuccess -and $raw.ErrorDetail) {
                        $message = "${message} - $($raw.ErrorDetail)"
                    }

                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.ShadowCopyResult'
                        ComputerName  = $machine
                        DriveLetter   = $DriveLetter.ToUpper()
                        ShadowCopyId  = if ($isSuccess) {
                            $raw.ShadowId 
                        } else {
                            '' 
                        }
                        CreationTime  = Get-Date
                        Success       = $isSuccess
                        ReturnCode    = $code
                        ReturnMessage = $message
                        Timestamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                } catch {
                    Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"

                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.ShadowCopyResult'
                        ComputerName  = $machine
                        DriveLetter   = $DriveLetter.ToUpper()
                        ShadowCopyId  = ''
                        CreationTime  = Get-Date
                        Success       = $false
                        ReturnCode    = [uint32]99
                        ReturnMessage = "Exception: $_"
                        Timestamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
