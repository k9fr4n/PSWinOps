#Requires -Version 5.1
function Set-PageFile {
    <#
    .SYNOPSIS
        Configure the Windows pagefile on local or remote computers

    .DESCRIPTION
        Configures the Windows pagefile by disabling automatic management and setting explicit
        initial and maximum sizes. Supports auto-calculation based on installed RAM, manual size
        specification, restoring automatic management, and ensuring the pagefile is large enough
        for a complete memory dump. All changes require a restart to take effect.

    .PARAMETER ComputerName
        One or more computer names to configure. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER DriveLetter
        The drive letter where the pagefile resides, in the format 'X:'.
        Defaults to 'C:'.

    .PARAMETER InitialSizeMB
        The initial (minimum) pagefile size in megabytes.
        Used with the Manual parameter set.

    .PARAMETER MaximumSizeMB
        The maximum pagefile size in megabytes.
        Must be greater than or equal to InitialSizeMB. Used with the Manual parameter set.

    .PARAMETER AutoCalculate
        Automatically calculate pagefile sizes based on the installed RAM.
        Uses a tiered sizing table derived from Microsoft best practices.

    .PARAMETER EnsureCompleteDump
        Ensure the initial pagefile size is at least RAM + 257 MB so that a
        complete memory dump can be written. Can be combined with AutoCalculate or Manual.

    .PARAMETER RestoreAutoManaged
        Re-enable Windows automatic pagefile management and remove any custom
        pagefile settings. This effectively reverts all manual configuration.

    .EXAMPLE
        Set-PageFile -AutoCalculate

        Configures the pagefile on the local computer with sizes calculated from installed RAM.

    .EXAMPLE
        Set-PageFile -ComputerName 'SRV01' -InitialSizeMB 8192 -MaximumSizeMB 16384

        Sets the pagefile on SRV01 to a fixed 8 GB initial / 16 GB maximum size.

    .EXAMPLE
        'SRV01', 'SRV02' | Set-PageFile -AutoCalculate -EnsureCompleteDump

        Calculates pagefile sizes for each server via pipeline and ensures the size
        is sufficient for a complete memory dump.

    .EXAMPLE
        Set-PageFile -RestoreAutoManaged -ComputerName 'SRV01'

        Restores automatic pagefile management on SRV01.

    .OUTPUTS
        PSWinOps.PageFileConfiguration
        Returns an object per computer with pagefile configuration details and status.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-03-25
        Requires: PowerShell 5.1+ / Windows only
        Requires: Administrator privileges on each target computer

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AutoCalculate',
        Justification = 'Switch drives parameter-set selection, not used as a variable.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RestoreAutoManaged',
        Justification = 'Switch drives parameter-set selection, not used as a variable.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Auto')]
    [OutputType('PSWinOps.PageFileConfiguration')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[A-Z]:$')]
        [string]$DriveLetter = 'C:',

        [Parameter(Mandatory = $true, ParameterSetName = 'Manual')]
        [ValidateRange(0, 65536)]
        [int]$InitialSizeMB,

        [Parameter(Mandatory = $true, ParameterSetName = 'Manual')]
        [ValidateRange(0, 65536)]
        [int]$MaximumSizeMB,

        [Parameter(Mandatory = $true, ParameterSetName = 'Auto')]
        [switch]$AutoCalculate,

        [Parameter(Mandatory = $false, ParameterSetName = 'Auto')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Manual')]
        [switch]$EnsureCompleteDump,

        [Parameter(Mandatory = $true, ParameterSetName = 'Restore')]
        [switch]$RestoreAutoManaged
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # --- Admin check -------------------------------------------------------
        $isAdmin = Test-IsAdministrator
        if (-not $isAdmin) {
            $adminException = [System.Security.SecurityException]::new(
                'This function requires administrator privileges.'
            )
            $adminRecord = [System.Management.Automation.ErrorRecord]::new(
                $adminException,
                'InsufficientPrivilege',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )
            $PSCmdlet.ThrowTerminatingError($adminRecord)
        }

        # --- Manual parameter-set cross-validation -----------------------------
        if ($PSCmdlet.ParameterSetName -eq 'Manual') {
            if ($MaximumSizeMB -lt $InitialSizeMB) {
                $validationException = [System.ArgumentException]::new(
                    "MaximumSizeMB ($MaximumSizeMB) must be greater than or equal to InitialSizeMB ($InitialSizeMB)."
                )
                $validationRecord = [System.Management.Automation.ErrorRecord]::new(
                    $validationException,
                    'InvalidSizeRange',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $null
                )
                $PSCmdlet.ThrowTerminatingError($validationRecord)
            }
        }

        # --- Registry path constant -------------------------------------------
        $registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing $targetComputer"

            $isLocal = ($targetComputer -eq $env:COMPUTERNAME) -or
            ($targetComputer -eq 'localhost') -or
            ($targetComputer -eq '.')

            try {
                # ===============================================================
                # RESTORE AUTO-MANAGED
                # ===============================================================
                if ($PSCmdlet.ParameterSetName -eq 'Restore') {
                    if ($PSCmdlet.ShouldProcess($targetComputer, 'Restore automatic pagefile management')) {
                        if ($isLocal) {
                            $compSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop
                            $ramBytes = $compSystem.TotalPhysicalMemory
                            $ramGB = [math]::Round($ramBytes / 1GB, 2)

                            Set-CimInstance -Query 'SELECT * FROM Win32_ComputerSystem' -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop

                            $existingPageFiles = Get-CimInstance -ClassName 'Win32_PageFileSetting' -ErrorAction SilentlyContinue
                            if ($existingPageFiles) {
                                Remove-CimInstance -Query 'SELECT * FROM Win32_PageFileSetting' -ErrorAction Stop
                            }

                            Set-ItemProperty -Path $registryPath -Name 'PagingFiles' -Value '?:\pagefile.sys' -ErrorAction Stop
                        } else {
                            $restoreResult = Invoke-Command -ComputerName $targetComputer -ScriptBlock {
                                $regPath = $using:registryPath
                                $cs = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop
                                $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
                                $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
                                $existing = Get-CimInstance -ClassName 'Win32_PageFileSetting' -ErrorAction SilentlyContinue
                                if ($existing) {
                                    $existing | Remove-CimInstance -ErrorAction Stop
                                }
                                Set-ItemProperty -Path $regPath -Name 'PagingFiles' -Value '?:\pagefile.sys' -ErrorAction Stop
                                [PSCustomObject]@{ RamGB = $ramGB }
                            } -ErrorAction Stop

                            $ramGB = $restoreResult.RamGB
                        }

                        [PSCustomObject]@{
                            PSTypeName          = 'PSWinOps.PageFileConfiguration'
                            ComputerName        = $targetComputer
                            DriveLetter         = $DriveLetter
                            PageFilePath        = "$DriveLetter\pagefile.sys"
                            InitialSizeMB       = 0
                            MaximumSizeMB       = 0
                            AutoManagedPagefile = $true
                            RamTotalGB          = $ramGB
                            EnsureCompleteDump  = $false
                            RestartRequired     = $true
                            Status              = 'RestoredAutoManaged'
                            Timestamp           = Get-Date -Format 'o'
                        }
                    }
                    continue
                }

                # ===============================================================
                # DETECT RAM
                # ===============================================================
                if ($isLocal) {
                    $compSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop
                } else {
                    $compSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ComputerName $targetComputer -ErrorAction Stop
                }

                $ramBytes = $compSystem.TotalPhysicalMemory
                $ramGB = [math]::Round($ramBytes / 1GB, 2)

                Write-Verbose -Message "[$($MyInvocation.MyCommand)] $targetComputer --> RAM detected: $ramGB GB"

                # ===============================================================
                # DETERMINE SIZES
                # ===============================================================
                if ($PSCmdlet.ParameterSetName -eq 'Auto') {
                    if ($ramGB -le 4) {
                        $initial = 4096
                        $maximum = 6144
                    } elseif ($ramGB -le 8) {
                        $initial = 6144
                        $maximum = 8192
                    } elseif ($ramGB -le 16) {
                        $initial = 8192
                        $maximum = 12288
                    } else {
                        # RAM > 16 GB (covers both <=32 and >32)
                        $initial = 8192
                        $maximum = 16384
                    }
                } else {
                    $initial = $InitialSizeMB
                    $maximum = $MaximumSizeMB
                }

                # ===============================================================
                # ENSURE COMPLETE DUMP
                # ===============================================================
                if ($EnsureCompleteDump.IsPresent) {
                    $ramMB = [math]::Ceiling($ramBytes / 1MB)
                    $dumpMinimumMB = $ramMB + 257

                    if ($initial -lt $dumpMinimumMB) {
                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Adjusting InitialSizeMB from $initial to $dumpMinimumMB for complete memory dump"
                        $initial = $dumpMinimumMB
                    }
                    if ($maximum -lt $initial) {
                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Adjusting MaximumSizeMB from $maximum to $initial to match InitialSizeMB"
                        $maximum = $initial
                    }
                }

                Write-Verbose -Message "[$($MyInvocation.MyCommand)] $targetComputer --> Sizes: Initial=$initial MB, Maximum=$maximum MB"

                # ===============================================================
                # APPLY CONFIGURATION
                # ===============================================================
                $pageFilePath = "$DriveLetter\pagefile.sys"
                $pagingFileValue = "$pageFilePath $initial $maximum"
                $shouldMsg = "Set pagefile $pageFilePath to Initial=$initial MB, Maximum=$maximum MB"

                if ($PSCmdlet.ShouldProcess($targetComputer, $shouldMsg)) {
                    if ($isLocal) {
                        # Disable auto-managed
                        Set-CimInstance -Query 'SELECT * FROM Win32_ComputerSystem' -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop

                        # Remove existing custom pagefiles
                        $existingPageFiles = Get-CimInstance -ClassName 'Win32_PageFileSetting' -ErrorAction SilentlyContinue
                        if ($existingPageFiles) {
                            Remove-CimInstance -Query 'SELECT * FROM Win32_PageFileSetting' -ErrorAction Stop
                        }

                        # Create new pagefile setting via CIM
                        $newPageFileArgs = @{
                            ClassName   = 'Win32_PageFileSetting'
                            Property    = @{
                                Name        = $pageFilePath
                                InitialSize = [uint32]$initial
                                MaximumSize = [uint32]$maximum
                            }
                            ErrorAction = 'Stop'
                        }
                        $null = New-CimInstance @newPageFileArgs

                        # Update registry
                        Set-ItemProperty -Path $registryPath -Name 'PagingFiles' -Value $pagingFileValue -ErrorAction Stop
                    } else {
                        $null = Invoke-Command -ComputerName $targetComputer -ScriptBlock {
                            $pfPath = $using:pageFilePath; $pfInitial = $using:initial; $pfMaximum = $using:maximum
                            $pfPagingValue = $using:pagingFileValue; $regPath = $using:registryPath

                            $cs = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop
                            $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop

                            $existing = Get-CimInstance -ClassName 'Win32_PageFileSetting' -ErrorAction SilentlyContinue
                            if ($existing) {
                                $existing | Remove-CimInstance -ErrorAction Stop
                            }

                            $null = New-CimInstance -ClassName 'Win32_PageFileSetting' -Property @{
                                Name        = $pfPath
                                InitialSize = [uint32]$pfInitial
                                MaximumSize = [uint32]$pfMaximum
                            } -ErrorAction Stop

                            Set-ItemProperty -Path $regPath -Name 'PagingFiles' -Value $pfPagingValue -ErrorAction Stop
                        } -ErrorAction Stop
                    }

                    [PSCustomObject]@{
                        PSTypeName          = 'PSWinOps.PageFileConfiguration'
                        ComputerName        = $targetComputer
                        DriveLetter         = $DriveLetter
                        PageFilePath        = $pageFilePath
                        InitialSizeMB       = $initial
                        MaximumSizeMB       = $maximum
                        AutoManagedPagefile = $false
                        RamTotalGB          = $ramGB
                        EnsureCompleteDump  = $EnsureCompleteDump.IsPresent
                        RestartRequired     = $true
                        Status              = 'Configured'
                        Timestamp           = Get-Date -Format 'o'
                    }
                }
            } catch [System.UnauthorizedAccessException] {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Access denied on ${targetComputer}: $_"
                continue
            } catch [System.Runtime.InteropServices.COMException] {
                Write-Error -Message "[$($MyInvocation.MyCommand)] CIM/WMI error on ${targetComputer}: $_"
                continue
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to configure pagefile on ${targetComputer}: $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
