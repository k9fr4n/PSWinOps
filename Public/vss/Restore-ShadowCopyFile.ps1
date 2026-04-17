#Requires -Version 5.1
function Restore-ShadowCopyFile {
    <#
        .SYNOPSIS
            Restore a file from a VSS shadow copy snapshot to a destination path

        .DESCRIPTION
            Restores a specific file from a Volume Shadow Copy snapshot identified by its ShadowCopyId.
            The SourcePath is relative to the drive root of the shadow copy volume. The function locates
            the shadow copy device object, constructs the full shadow path, and copies the file to the
            specified destination. Supports -Force to overwrite existing files.

        .PARAMETER ShadowCopyId
            The unique identifier (GUID) of the shadow copy to restore from.

        .PARAMETER SourcePath
            The path to the file relative to the drive root. Example: 'Data\report.xlsx' for C:\Data\report.xlsx.

        .PARAMETER DestinationPath
            The full destination path where the file will be restored to.

        .PARAMETER Force
            Overwrite the destination file if it already exists.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.

        .PARAMETER Credential
            Optional credential for remote execution.

        .EXAMPLE
            Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Data\report.xlsx' -DestinationPath 'C:\Restore\report.xlsx'

            Restores report.xlsx from the specified shadow copy to C:\Restore on the local machine.

        .EXAMPLE
            Restore-ShadowCopyFile -ShadowCopyId '{AB12CD34-EF56-7890-AB12-CD34EF567890}' -SourcePath 'Logs\app.log' -DestinationPath 'D:\Recovery\app.log' -Force -ComputerName 'SRV01'

            Restores app.log from a shadow copy on SRV01, overwriting any existing file.

        .EXAMPLE
            Get-ShadowCopy -DriveLetter 'C' | Select-Object -First 1 | Restore-ShadowCopyFile -SourcePath 'Config\settings.json' -DestinationPath 'C:\Backup\settings.json'

            Restores settings.json using shadow copy information piped from Get-ShadowCopy.

        .OUTPUTS
            PSWinOps.ShadowCopyRestoreResult
            Returns an object with ComputerName, ShadowCopyId, SourcePath, DestinationPath,
            Restored, SizeBytes, SizeMB, ErrorMessage, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (access to shadow copy device objects)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/vss/volume-shadow-copy-service-overview
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('PSWinOps.ShadowCopyRestoreResult')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ShadowCopyId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

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
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $forceFlag = $Force.IsPresent

        $scriptBlock = {
            param(
                [string]$shadowId,
                [string]$sourcePath,
                [string]$destPath,
                [bool]$forceOverwrite
            )

            $resultHash = @{
                ShadowCopyId    = $shadowId
                SourcePath      = $sourcePath
                DestinationPath = $destPath
                Restored        = $false
                SizeBytes       = [long]0
                ErrorMessage    = ''
            }

            try {
                $shadow = Get-CimInstance -ClassName 'Win32_ShadowCopy' -ErrorAction Stop |
                    Where-Object -Property 'ID' -EQ -Value $shadowId

                if ($null -eq $shadow) {
                    $resultHash.ErrorMessage = "Shadow copy with ID '$shadowId' not found"
                    return $resultHash
                }

                $shadowRoot = $shadow.DeviceObject + '\'
                $fullSource = Join-Path -Path $shadowRoot -ChildPath $sourcePath

                if (-not (Test-Path -LiteralPath $fullSource)) {
                    $resultHash.ErrorMessage = "Source file '$sourcePath' not found in shadow copy at '$fullSource'"
                    return $resultHash
                }

                if ((Test-Path -LiteralPath $destPath) -and (-not $forceOverwrite)) {
                    $resultHash.ErrorMessage = "Destination '$destPath' already exists. Use -Force to overwrite."
                    return $resultHash
                }

                $destDir = Split-Path -Path $destPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($destDir)) {
                    $null = New-Item -ItemType 'Directory' -Path $destDir -Force -ErrorAction SilentlyContinue
                }

                Copy-Item -LiteralPath $fullSource -Destination $destPath -Force:$forceOverwrite -ErrorAction Stop

                $copiedFile = Get-Item -LiteralPath $destPath -ErrorAction Stop
                $resultHash.SizeBytes = $copiedFile.Length
                $resultHash.Restored = $true
            } catch {
                $resultHash.ErrorMessage = $_.Exception.Message
                $resultHash.Restored = $false
            }

            return $resultHash
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $shouldProcessTarget = "Restore '$SourcePath' from shadow copy $ShadowCopyId to '$DestinationPath' on $machine"

            if (-not $PSCmdlet.ShouldProcess($shouldProcessTarget, 'Restore-ShadowCopyFile')) {
                continue
            }

            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$machine' - Restoring '$SourcePath' from $ShadowCopyId"

            try {
                $invokeParams = @{
                    ComputerName = $machine
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @($ShadowCopyId, $SourcePath, $DestinationPath, $forceFlag)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $raw = Invoke-RemoteOrLocal @invokeParams

                $sizeBytes = [long]$raw.SizeBytes
                $sizeMB = [math]::Round($sizeBytes / 1MB, 2)

                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.ShadowCopyRestoreResult'
                    ComputerName    = $machine
                    ShadowCopyId    = $raw.ShadowCopyId
                    SourcePath      = $raw.SourcePath
                    DestinationPath = $raw.DestinationPath
                    Restored        = $raw.Restored
                    SizeBytes       = $sizeBytes
                    SizeMB          = $sizeMB
                    ErrorMessage    = $raw.ErrorMessage
                    Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"

                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.ShadowCopyRestoreResult'
                    ComputerName    = $machine
                    ShadowCopyId    = $ShadowCopyId
                    SourcePath      = $SourcePath
                    DestinationPath = $DestinationPath
                    Restored        = $false
                    SizeBytes       = [long]0
                    SizeMB          = 0
                    ErrorMessage    = "$_"
                    Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
