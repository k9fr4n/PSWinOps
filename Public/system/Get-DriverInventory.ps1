#Requires -Version 5.1
function Get-DriverInventory {
    <#
        .SYNOPSIS
            Retrieves a structured inventory of signed drivers from local or remote computers

        .DESCRIPTION
            Queries Win32_PnPSignedDriver via CIM to return an inventory of installed device
            drivers, including device name, class, manufacturer, version, date, signature
            state, and INF file. Results can be filtered by device class or restricted to
            unsigned drivers only, and the function supports multiple machines with per-machine
            error isolation.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER DeviceClass
            Optional device class to filter on (case-insensitive), for example 'Net',
            'Display', or 'System'. When omitted, drivers of all classes are returned.

        .PARAMETER UnsignedOnly
            When specified, only drivers that are not digitally signed are returned.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-DriverInventory

            Retrieves the full driver inventory from the local computer.

        .EXAMPLE
            Get-DriverInventory -ComputerName 'SRV01' -DeviceClass 'Net'

            Retrieves only network-class drivers from SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-DriverInventory -UnsignedOnly

            Retrieves only unsigned drivers from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.DriverInventory
            Returns one object per driver with device name, class, manufacturer, version,
            date, signature state, and INF file name.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-08-11
            Requires: PowerShell 5.1+ / Windows only

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pnpsigneddriver
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DriverInventory')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceClass,

        [Parameter(Mandatory = $false)]
        [switch]$UnsignedOnly,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            @(Get-CimInstance -ClassName 'Win32_PnPSignedDriver' -ErrorAction Stop)
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying Win32_PnPSignedDriver on '$machine'"
                $drivers = @(Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential)

                if ($PSBoundParameters.ContainsKey('DeviceClass')) {
                    $drivers = @($drivers | Where-Object { $_.DeviceClass -eq $DeviceClass })
                }

                $displayName = $machine

                foreach ($driver in $drivers) {
                    $isSigned = [bool]$driver.IsSigned

                    if ($UnsignedOnly -and $isSigned) {
                        continue
                    }

                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.DriverInventory'
                        ComputerName  = $displayName
                        DeviceName    = $driver.DeviceName
                        DeviceClass   = $driver.DeviceClass
                        Manufacturer  = $driver.Manufacturer
                        DriverVersion = $driver.DriverVersion
                        DriverDate    = $driver.DriverDate
                        IsSigned      = $isSigned
                        InfName       = $driver.InfName
                        Timestamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
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
