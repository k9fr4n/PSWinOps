#Requires -Version 5.1
function Get-SystemSummary {
    <#
    .SYNOPSIS
        Gather comprehensive system information from Windows machines
    .DESCRIPTION
        Queries six WMI/CIM classes to build a detailed system summary for local or remote
        Windows machines. Supports pipeline input, explicit credentials for remote hosts,
        and returns a structured PSCustomObject per machine. CIM session management and
        cleanup are handled automatically.
    .PARAMETER ComputerName
        One or more computer names or IP addresses to query. Defaults to the local machine.
        Accepts pipeline input by value and by property name.
    .PARAMETER Credential
        Optional PSCredential used to authenticate against remote machines. Ignored for
        local queries. Obtain via Get-Credential or SecretManagement.
    .EXAMPLE
        Get-SystemSummary
        Returns a full system summary for the local machine.
    .EXAMPLE
        Get-SystemSummary -ComputerName 'SRV01', 'SRV02' -Credential (Get-Credential)
        Returns system summaries for two remote servers using explicit credentials.
    .EXAMPLE
        'WEB01', 'WEB02' | Get-SystemSummary -Verbose
        Queries two machines via pipeline input with verbose logging.
    .OUTPUTS
    PSWinOps.SystemSummary
        System information summary including OS, CPU, RAM, and uptime.

    .NOTES
        Author:        Franck SALLET
        Version:       1.0.0
        Last Modified: 2026-03-15
        Requires:      PowerShell 5.1+, CIM/WMI access on target machines
        Permissions:   Local admin or equivalent WMI read permissions on remote targets
    
    .LINK
    https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.SystemSummary')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')
    }

    process {
        foreach ($machine in $ComputerName) {
            $cimSession = $null
            try {
                $isLocal = $localNames -contains $machine

                # Build common CIM params for this machine (splat for all 6 classes)
                $cimParams = @{ ErrorAction = 'Stop' }
                if (-not $isLocal) {
                    if ($hasCredential) {
                        $cimSession = New-CimSession -ComputerName $machine -Credential $Credential -ErrorAction Stop
                        $cimParams['CimSession'] = $cimSession
                    } else {
                        $cimParams['ComputerName'] = $machine
                    }
                }

                # Query all 6 CIM classes
                $system = Get-CimInstance -ClassName 'Win32_ComputerSystem' @cimParams
                $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' @cimParams
                $bios = Get-CimInstance -ClassName 'Win32_BIOS' @cimParams
                $processor = Get-CimInstance -ClassName 'Win32_Processor' @cimParams | Select-Object -First 1
                $disks = Get-CimInstance -ClassName 'Win32_LogicalDisk' @cimParams | Where-Object -FilterScript { $_.DriveType -eq 3 }
                $networkAdapters = Get-CimInstance -ClassName 'Win32_NetworkAdapterConfiguration' @cimParams | Where-Object -FilterScript { $null -ne $_.DefaultIPGateway }

                # Calculate uptime
                $uptime = (Get-Date) - $os.LastBootUpTime

                # Build disk summary strings
                $diskSummary = ($disks | ForEach-Object -Process {
                        '[{0}] {1} ({2}) {3:N2}/{4:N2} GB ({5:N1}% Free)' -f
                        $_.FileSystem, $_.DeviceID, $_.VolumeName,
                        ($_.FreeSpace / 1GB), ($_.Size / 1GB),
                        (($_.FreeSpace / $_.Size) * 100)
                    }) -join ' | '

                # Extract IPv4 addresses only
                $ipv4Addresses = ($networkAdapters.IPAddress | Where-Object -FilterScript { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) -join ', '
                $gatewayList = ($networkAdapters.DefaultIPGateway) -join ', '
                $dnsList = ($networkAdapters.DNSServerSearchOrder) -join ', '

                # Determine PS version string
                $psVersionString = if ($isLocal) {
                    $PSVersionTable.PSVersion.ToString()
                } else {
                    'N/A (remote)'
                }

                [PSCustomObject]@{
                    PSTypeName             = 'PSWinOps.SystemSummary'
                    ComputerName           = $machine
                    Domain                 = $system.Domain
                    OSName                 = $os.Caption
                    OSVersion              = $os.Version
                    OSArchitecture         = $os.OSArchitecture
                    InstallDate            = $os.InstallDate
                    LastBootTime           = $os.LastBootUpTime
                    UptimeDays             = [decimal][math]::Round($uptime.TotalDays, 2)
                    UptimeDisplay          = '{0} days, {1} hours, {2} minutes' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
                    Manufacturer           = $system.Manufacturer
                    Model                  = $system.Model
                    SerialNumber           = $bios.SerialNumber
                    BIOSVersion            = $bios.SMBIOSBIOSVersion
                    Processor              = $processor.Name.Trim()
                    TotalCores             = [int]$processor.NumberOfCores
                    TotalLogicalProcessors = [int]$processor.NumberOfLogicalProcessors
                    TotalRAMGB             = [decimal][math]::Round($system.TotalPhysicalMemory / 1GB, 2)
                    FreeRAMGB              = [decimal][math]::Round($os.FreePhysicalMemory / 1MB, 2)
                    RAMUsagePercent        = [decimal][math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
                    Disks                  = $diskSummary
                    IPAddresses            = $ipv4Addresses
                    DefaultGateway         = $gatewayList
                    DNSServers             = $dnsList
                    PSVersion              = $psVersionString
                    Timestamp              = Get-Date -Format 'o'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
            } finally {
                if ($null -ne $cimSession) {
                    Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
