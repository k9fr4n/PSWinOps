#Requires -Version 5.1
function Get-CrashDump {
    <#
    .SYNOPSIS
        Inventory Windows crash memory dumps with size, type and BugCheck code

    .DESCRIPTION
        Enumerates minidumps and the full/kernel MEMORY.DMP on one or more machines in a single
        pass, reporting size, creation time and configured dump type. The BugCheck code and
        symbol are correlated from WER System Error Reporting event 1001 by temporal proximity,
        so no binary dump parsing is required. Local and remote targets are dispatched through
        Invoke-RemoteOrLocal.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for
        local machine queries.

    .PARAMETER Path
        Override dump directory/glob. Default is '%SystemRoot%\Minidump\*.dmp' plus
        '%SystemRoot%\MEMORY.DMP'. When supplied, this path or glob is searched instead
        of the two defaults.

    .PARAMETER Newest
        Return only the N most recent dumps per machine, sorted by CreationTime
        descending. When omitted, all discovered dumps are returned.

    .EXAMPLE
        Get-CrashDump

        Returns every crash dump found on the local computer.

    .EXAMPLE
        Get-CrashDump -ComputerName 'SRV01' -Newest 5

        Returns the 5 most recent crash dumps on SRV01 via WinRM.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-CrashDump -Credential $cred

        Returns crash dumps for SRV01 and SRV02 via pipeline, using alternate credentials.

    .OUTPUTS
        PSWinOps.CrashDump
        One object per discovered dump file, with size, creation time, configured dump
        type, and the correlated BugCheck code/symbol when resolvable.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-05
        Requires: PowerShell 5.1+ / Windows only
        Requires: Read access to %SystemRoot%\Minidump and %SystemRoot%\MEMORY.DMP;
        WinRM enabled on target machines for remote queries

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://github.com/k9fr4n/PSWinOps/issues/66
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.CrashDump')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Newest
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting crash dump inventory"

        $hasNewest = $PSBoundParameters.ContainsKey('Newest')
        $newestVal = if ($hasNewest) { $Newest } else { 0 }
        $hasPath   = $PSBoundParameters.ContainsKey('Path')
        $pathVal   = if ($hasPath) { $Path } else { '' }

        $scriptBlock = {
            param(
                [bool]$HasPath,
                [string]$OverridePath,
                [bool]$HasNewest,
                [int]$NewestCount
            )

            # Bugcheck code -> human readable symbol lookup (common codes only)
            $bugCheckSymbols = @{
                '0X00000001' = 'APC_INDEX_MISMATCH'
                '0X0000000A' = 'IRQL_NOT_LESS_OR_EQUAL'
                '0X0000001A' = 'MEMORY_MANAGEMENT'
                '0X0000001E' = 'KMODE_EXCEPTION_NOT_HANDLED'
                '0X00000024' = 'NTFS_FILE_SYSTEM'
                '0X0000003B' = 'SYSTEM_SERVICE_EXCEPTION'
                '0X0000004E' = 'PFN_LIST_CORRUPT'
                '0X00000050' = 'PAGE_FAULT_IN_NONPAGED_AREA'
                '0X0000007A' = 'KERNEL_DATA_INPAGE_ERROR'
                '0X0000007E' = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED_M'
                '0X0000007F' = 'UNEXPECTED_KERNEL_MODE_TRAP'
                '0X0000008E' = 'KERNEL_MODE_EXCEPTION_NOT_HANDLED'
                '0X0000009F' = 'DRIVER_POWER_STATE_FAILURE'
                '0X000000C2' = 'BAD_POOL_CALLER'
                '0X000000CE' = 'DRIVER_UNLOADED_WITHOUT_CANCELLING_PENDING_OPERATIONS'
                '0X000000D1' = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'
                '0X000000EF' = 'CRITICAL_PROCESS_DIED'
                '0X000000F4' = 'CRITICAL_OBJECT_TERMINATION'
                '0X00000109' = 'CRITICAL_STRUCTURE_CORRUPTION'
                '0X00000119' = 'VIDEO_SCHEDULER_INTERNAL_ERROR'
                '0X00000124' = 'WHEA_UNCORRECTABLE_ERROR'
                '0X00000133' = 'DPC_WATCHDOG_VIOLATION'
                '0X00000139' = 'KERNEL_SECURITY_CHECK_FAILURE'
            }

            # Rule 5: CIM over WMI for the Windows directory
            $systemRoot = (Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop).WindowsDirectory

            $dumpFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

            if ($HasPath -and -not [string]::IsNullOrWhiteSpace($OverridePath)) {
                $resolvedOverride = $OverridePath
                if (Test-Path -Path $resolvedOverride -PathType Container -ErrorAction SilentlyContinue) {
                    $resolvedOverride = Join-Path -Path $resolvedOverride -ChildPath '*.dmp'
                }
                $found = @(Get-ChildItem -Path $resolvedOverride -File -ErrorAction SilentlyContinue)
                foreach ($item in $found) { $dumpFiles.Add($item) }
            } else {
                $miniDumpGlob = Join-Path -Path $systemRoot -ChildPath 'Minidump\*.dmp'
                $memoryDump   = Join-Path -Path $systemRoot -ChildPath 'MEMORY.DMP'

                $miniFound = @(Get-ChildItem -Path $miniDumpGlob -File -ErrorAction SilentlyContinue)
                foreach ($item in $miniFound) { $dumpFiles.Add($item) }

                $memoryFound = @(Get-Item -Path $memoryDump -ErrorAction SilentlyContinue)
                foreach ($item in $memoryFound) { $dumpFiles.Add($item) }
            }

            if ($dumpFiles.Count -eq 0) {
                return @()
            }

            # Configured dump type, read once, used to classify MEMORY.DMP
            $crashControlPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
            $crashDumpEnabled = (Get-ItemProperty -Path $crashControlPath -Name 'CrashDumpEnabled' -ErrorAction SilentlyContinue).CrashDumpEnabled

            # WER System Error Reporting 1001 events, fetched once and correlated by proximity
            $werEvents = @(Get-WinEvent -FilterHashtable @{
                    LogName      = 'Application'
                    ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
                    Id           = 1001
                } -ErrorAction SilentlyContinue)

            $results = [System.Collections.Generic.List[psobject]]::new()

            foreach ($dump in $dumpFiles) {
                $dumpType = if ($dump.Name -like 'Mini*.dmp') {
                    'Mini'
                } elseif ($crashDumpEnabled -eq 2) {
                    'Kernel'
                } else {
                    'Full'
                }

                $bugCheckCode   = $null
                $bugCheckSymbol = $null

                $closestEvent = $werEvents | Where-Object {
                    [math]::Abs(($_.TimeCreated - $dump.CreationTime).TotalMinutes) -le 10
                } | Sort-Object -Property { [math]::Abs(($_.TimeCreated - $dump.CreationTime).TotalMinutes) } | Select-Object -First 1

                if ($null -ne $closestEvent) {
                    $matched = [regex]::Match($closestEvent.Message, '0x[0-9A-Fa-f]{8}')
                    if ($matched.Success) {
                        $bugCheckCode = $matched.Value.ToUpperInvariant() -replace '^0X', '0x'
                        $lookupKey = $matched.Value.ToUpperInvariant()
                        if ($bugCheckSymbols.ContainsKey($lookupKey)) {
                            $bugCheckSymbol = $bugCheckSymbols[$lookupKey]
                        }
                    }
                }

                $results.Add([PSCustomObject]@{
                        PSTypeName      = 'PSWinOps.CrashDump'
                        ComputerName    = $env:COMPUTERNAME
                        DumpFile        = $dump.FullName
                        DumpType        = $dumpType
                        SizeMB          = [math]::Round($dump.Length / 1MB, 2)
                        CreationTime    = $dump.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                        BugCheckCode    = $bugCheckCode
                        BugCheckSymbol  = $bugCheckSymbol
                        Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                    })
            }

            $sorted = @($results | Sort-Object -Property CreationTime -Descending)

            if ($HasNewest -and $NewestCount -gt 0) {
                $sorted = @($sorted | Select-Object -First $NewestCount)
            }

            $sorted
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying crash dumps on '$targetComputer'"
                Invoke-RemoteOrLocal -ComputerName $targetComputer -Credential $Credential `
                    -ScriptBlock $scriptBlock `
                    -ArgumentList @($hasPath, $pathVal, $hasNewest, $newestVal)
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed crash dump inventory"
    }
}
