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
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
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

        $scriptBlock = {
            $system = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop
            $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
            $bios = Get-CimInstance -ClassName 'Win32_BIOS' -ErrorAction Stop
            $processor = Get-CimInstance -ClassName 'Win32_Processor' -ErrorAction Stop | Select-Object -First 1
            $disks = Get-CimInstance -ClassName 'Win32_LogicalDisk' -ErrorAction Stop | Where-Object -FilterScript { $_.DriveType -eq 3 }
            $networkAdapters = Get-CimInstance -ClassName 'Win32_NetworkAdapterConfiguration' -ErrorAction Stop | Where-Object -FilterScript { $null -ne $_.DefaultIPGateway }

            @{
                System          = $system
                OS              = $os
                BIOS            = $bios
                Processor       = $processor
                Disks           = $disks
                NetworkAdapters = $networkAdapters
                PSVersion       = $PSVersionTable.PSVersion.ToString()
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying system summary on '$machine'"
                $rawData = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                $system = $rawData.System
                $os = $rawData.OS
                $bios = $rawData.BIOS
                $processor = $rawData.Processor
                $disks = $rawData.Disks
                $networkAdapters = $rawData.NetworkAdapters
                $psVersionString = $rawData.PSVersion

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
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
