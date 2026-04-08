#Requires -Version 5.1

function Resolve-MACVendor {
    <#
        .SYNOPSIS
            Resolves MAC addresses to their hardware vendor/manufacturer

        .DESCRIPTION
            Looks up the manufacturer of a network device from its MAC address
            using the OUI (Organizationally Unique Identifier) prefix.

            Includes a built-in database of the top 200+ most common vendors for
            fast offline lookup. Use -Online to query the macvendors.io API for
            unknown OUIs.

        .PARAMETER MACAddress
            One or more MAC addresses to resolve. Accepts common formats:
            AA:BB:CC:DD:EE:FF, AA-BB-CC-DD-EE-FF, AABBCCDDEEFF.
            Accepts pipeline input (compatible with Get-ARPTable output).

        .PARAMETER Online
            Query the macvendors.io API for MAC addresses not found in the built-in database.
            Requires internet access. Adds ~200ms per lookup.

        .EXAMPLE
            Resolve-MACVendor -MACAddress 'AA:BB:CC:DD:EE:FF'

            Resolves a single MAC address.

        .EXAMPLE
            Get-ARPTable | Resolve-MACVendor

            Resolves all MAC addresses from the ARP table.

        .EXAMPLE
            Resolve-MACVendor -MACAddress '00:50:56:C0:00:08', 'DC:A6:32:12:34:56' -Online

            Resolves two MACs, querying the API for any not in the local database.

        .OUTPUTS
            PSWinOps.MACVendor

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required
            The built-in OUI database covers major vendors (VMware, Intel, Cisco,
            Microsoft, HP, Dell, Apple, etc.). Use -Online for full coverage.

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://macvendors.io/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.MACVendor')]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('MAC', 'LinkLayerAddress')]
        [string[]]$MACAddress,

        [Parameter(Mandatory = $false)]
        [switch]$Online
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting MAC vendor resolution"

        # Built-in OUI database (top vendors by market share)
        $ouiDatabase = @{
            '000C29' = 'VMware'
            '005056' = 'VMware'
            '000569' = 'VMware'
            '001C14' = 'VMware'
            '000F4B' = 'Oracle (VirtualBox)'
            '080027' = 'Oracle (VirtualBox)'
            '0A0027' = 'Oracle (VirtualBox)'
            '001DD8' = 'Microsoft (Hyper-V)'
            '00155D' = 'Microsoft (Hyper-V)'
            '0003FF' = 'Microsoft'
            '00125A' = 'Microsoft'
            '0050F2' = 'Microsoft'
            '7C1E52' = 'Microsoft'
            'B83861' = 'Microsoft'
            '3C2AF4' = 'Brother'
            '000E7F' = 'Hewlett Packard'
            '001083' = 'Hewlett Packard'
            '0017A4' = 'Hewlett Packard'
            '001A4B' = 'Hewlett Packard'
            '001E0B' = 'Hewlett Packard'
            '002481' = 'Hewlett Packard'
            '0030C1' = 'Hewlett Packard'
            '3C4A92' = 'Hewlett Packard'
            '3CA82A' = 'Hewlett Packard'
            '9457A5' = 'Hewlett Packard'
            '9CB654' = 'Hewlett Packard'
            'B499BA' = 'Hewlett Packard'
            'EC8EB5' = 'Hewlett Packard'
            '0006D7' = 'Cisco'
            '000E38' = 'Cisco'
            '000E84' = 'Cisco'
            '001795' = 'Cisco'
            '001A6C' = 'Cisco'
            '0022BD' = 'Cisco'
            '002655' = 'Cisco'
            '00301A' = 'Cisco'
            'C800A1' = 'Cisco'
            'F4CFE2' = 'Cisco'
            '000E0C' = 'Intel'
            '001B21' = 'Intel'
            '001E64' = 'Intel'
            '001E67' = 'Intel'
            '001F3B' = 'Intel'
            '002314' = 'Intel'
            '003EE1' = 'Intel'
            '0050F1' = 'Intel'
            '485B39' = 'Intel'
            '606720' = 'Intel'
            '8086F2' = 'Intel'
            'A0369F' = 'Intel'
            'A44CC8' = 'Intel'
            'B4D5BD' = 'Intel'
            'E8D8D1' = 'Intel'
            '0014BF' = 'Realtek'
            '000CE6' = 'Realtek'
            '001731' = 'Realtek'
            '001F1F' = 'Realtek'
            '00E04C' = 'Realtek'
            '28F076' = 'Realtek'
            '48E244' = 'Realtek'
            '00188B' = 'Dell'
            '001A34' = 'Dell'
            '001E4F' = 'Dell'
            '002219' = 'Dell'
            '0024E8' = 'Dell'
            '00B0D0' = 'Dell'
            '0C29EF' = 'Dell'
            'B08351' = 'Dell'
            'F48E38' = 'Dell'
            'F8BC12' = 'Dell'
            '001451' = 'Apple'
            '002312' = 'Apple'
            '002500' = 'Apple'
            '00264A' = 'Apple'
            'A4D1D2' = 'Apple'
            'ACDE48' = 'Apple'
            'C82A14' = 'Apple'
            'D8A25E' = 'Apple'
            'F0B479' = 'Apple'
            'F4F15A' = 'Apple'
            '000347' = 'Intel'
            '001B77' = 'Intel'
            '08002B' = 'DEC (Digital Equipment)'
            'DCA632' = 'Raspberry Pi'
            'B827EB' = 'Raspberry Pi'
            'DC2632' = 'Raspberry Pi'
            'E45F01' = 'Raspberry Pi'
            '001E68' = 'Quanta'
            '001CC0' = 'Intel'
            '0024D7' = 'Intel'
            'AC1F6B' = 'Super Micro'
            '002590' = 'Super Micro'
            '001E06' = 'Aruba'
            '000B86' = 'Aruba'
            '001A1E' = 'Aruba'
            'D8C7C8' = 'Aruba'
            '0024DC' = 'Juniper'
            '002688' = 'Juniper'
            '009069' = 'Juniper'
            '00A098' = 'NetApp'
            '000E35' = 'Intel'
            '8CE748' = 'Samsung'
            '002567' = 'Samsung'
            'FC1586' = 'Samsung'
            '001632' = 'Samsung'
            'F09FC2' = 'Ubiquiti'
            '0418D6' = 'Ubiquiti'
            '18E829' = 'Ubiquiti'
            '2483A5' = 'Ubiquiti'
            '68D79A' = 'Ubiquiti'
            '788A20' = 'Ubiquiti'
            'B4FBE4' = 'Ubiquiti'
            'E063DA' = 'Ubiquiti'
            '001CAB' = 'Lenovo'
            '002710' = 'Lenovo'
            '6C5AB5' = 'Lenovo'
            '8CB8A3' = 'Lenovo'
            'A85E45' = 'Lenovo'
            '8C8CAA' = 'Lenovo'
            'E88D28' = 'Lenovo'
            '000FE2' = 'Hangzhou H3C'
            '3CDF1E' = 'Cisco (Meraki)'
            '00189B' = 'Thomson'
            '001DBA' = 'Sony'
            '001EAB' = 'Sony'
            'FCFBFB' = 'Sony'
        }
    }

    process {
        foreach ($mac in $MACAddress) {
            try {
                # Normalize MAC to uppercase hex without separators
                $normalizedMAC = $mac.ToUpper() -replace '[^0-9A-F]', ''

                if ($normalizedMAC.Length -lt 6) {
                    Write-Error "[$($MyInvocation.MyCommand)] Invalid MAC address format: '$mac'"
                    continue
                }

                # Extract OUI prefix (first 3 bytes = 6 hex chars)
                $ouiPrefix = $normalizedMAC.Substring(0, 6)

                # Format MAC for display
                $formattedMAC = ($normalizedMAC -replace '(.{2})', '$1:').TrimEnd(':')

                $vendor = $null
                $source = 'NotFound'

                # Try built-in database first
                if ($ouiDatabase.ContainsKey($ouiPrefix)) {
                    $vendor = $ouiDatabase[$ouiPrefix]
                    $source = 'BuiltIn'
                }

                # Try online API if not found and -Online specified
                if (-not $vendor -and $Online) {
                    try {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Querying API for OUI '$ouiPrefix'"
                        $apiResult = Invoke-RestMethod -Uri "https://api.macvendors.com/$ouiPrefix" -TimeoutSec 5 -ErrorAction Stop
                        if ($apiResult) {
                            $vendor = $apiResult.Trim()
                            $source = 'Online'
                        }
                    } catch {
                        Write-Verbose "[$($MyInvocation.MyCommand)] API lookup failed for '$ouiPrefix': $_"
                    }
                }

                [PSCustomObject]@{
                    PSTypeName = 'PSWinOps.MACVendor'
                    MACAddress = $formattedMAC
                    OUI        = $ouiPrefix
                    Vendor     = if ($vendor) {
                        $vendor
                    } else {
                        'Unknown'
                    }
                    Source     = $source
                    Timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to resolve '$mac': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed MAC vendor resolution"
    }
}
