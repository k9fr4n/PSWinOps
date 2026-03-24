#Requires -Version 5.1

function Get-SubnetInfo {
    <#
        .SYNOPSIS
            Calculates subnet information from an IP address and subnet mask or CIDR notation

        .DESCRIPTION
            Computes detailed subnet properties including network address, broadcast address,
            first/last usable host, total host count, and wildcard mask.

            Accepts input in CIDR notation (e.g., 192.168.1.0/24) or as separate IP and
            mask parameters.

            This is a pure calculation function with no network access required.

        .PARAMETER IPAddress
            IP address in standard dotted notation (e.g., 192.168.1.100) or
            CIDR notation (e.g., 192.168.1.0/24). Accepts pipeline input.

        .PARAMETER PrefixLength
            Subnet prefix length (CIDR notation). Valid range: 0-32.
            Not required if IPAddress includes CIDR notation.

        .PARAMETER SubnetMask
            Subnet mask in dotted notation (e.g., 255.255.255.0).
            Alternative to PrefixLength.

        .EXAMPLE
            Get-SubnetInfo -IPAddress '192.168.1.0/24'

            Calculates subnet info for a /24 network using CIDR notation.

        .EXAMPLE
            Get-SubnetInfo -IPAddress '10.0.0.50' -PrefixLength 16

            Calculates subnet info for a /16 network.

        .EXAMPLE
            Get-SubnetInfo -IPAddress '172.16.0.0' -SubnetMask '255.255.240.0'

            Uses traditional subnet mask notation.

        .EXAMPLE
            '192.168.1.0/24', '10.0.0.0/8', '172.16.0.0/12' | Get-SubnetInfo

            Calculates info for multiple subnets via pipeline.

        .OUTPUTS
            PSWinOps.SubnetInfo

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required (pure calculation, no network access)

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding(DefaultParameterSetName = 'CIDR')]
    [OutputType('PSWinOps.SubnetInfo')]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$IPAddress,

        [Parameter(Mandatory = $false, ParameterSetName = 'CIDR')]
        [ValidateRange(0, 32)]
        [int]$PrefixLength,

        [Parameter(Mandatory = $false, ParameterSetName = 'Mask')]
        [ValidateScript({
            try {
                $null = [System.Net.IPAddress]::Parse($_)
                $true
            } catch {
                throw "Invalid subnet mask format: '$_'"
            }
        })]
        [string]$SubnetMask
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting subnet calculation"

        function ConvertTo-UInt32 {
            param([System.Net.IPAddress]$IP)
            $bytes = $IP.GetAddressBytes()
            [uint32](([uint32]$bytes[0] -shl 24) -bor ([uint32]$bytes[1] -shl 16) -bor ([uint32]$bytes[2] -shl 8) -bor [uint32]$bytes[3])
        }

        function ConvertFrom-UInt32 {
            param([uint32]$Value)
            [System.Net.IPAddress]::new([byte[]]@(
                [byte](($Value -shr 24) -band 0xFF),
                [byte](($Value -shr 16) -band 0xFF),
                [byte](($Value -shr 8) -band 0xFF),
                [byte]($Value -band 0xFF)
            ))
        }

        function ConvertTo-PrefixLength {
            param([System.Net.IPAddress]$Mask)
            $maskInt = ConvertTo-UInt32 -IP $Mask
            $bits = 0
            $current = $maskInt
            while ($current -band 0x80000000) {
                $bits++
                $current = ($current -shl 1) -band 0xFFFFFFFF
            }
            return $bits
        }
    }

    process {
        foreach ($ip in $IPAddress) {
            try {
                # Parse CIDR notation if present
                $parsedIP = $null
                $parsedPrefix = 0

                if ($ip -match '^(.+)/([0-9]+)$') {
                    $parsedIP = [System.Net.IPAddress]::Parse($Matches[1])
                    $parsedPrefix = [int]$Matches[2]
                    if ($parsedPrefix -lt 0 -or $parsedPrefix -gt 32) {
                        Write-Error "[$($MyInvocation.MyCommand)] Invalid prefix length: $parsedPrefix"
                        continue
                    }
                } elseif ($PSBoundParameters.ContainsKey('PrefixLength')) {
                    $parsedIP = [System.Net.IPAddress]::Parse($ip)
                    $parsedPrefix = $PrefixLength
                } elseif ($PSBoundParameters.ContainsKey('SubnetMask')) {
                    $parsedIP = [System.Net.IPAddress]::Parse($ip)
                    $maskIP = [System.Net.IPAddress]::Parse($SubnetMask)
                    $parsedPrefix = ConvertTo-PrefixLength -Mask $maskIP
                } else {
                    Write-Error "[$($MyInvocation.MyCommand)] Specify prefix length via CIDR notation (/24), -PrefixLength, or -SubnetMask for '$ip'"
                    continue
                }

                # Core calculations
                $ipInt = ConvertTo-UInt32 -IP $parsedIP

                # Build mask from prefix
                if ($parsedPrefix -eq 0) {
                    [uint32]$maskInt = 0
                } else {
                    [uint32]$maskInt = [uint32]::MaxValue -shl (32 - $parsedPrefix)
                }

                [uint32]$wildcardInt = $maskInt -bxor [uint32]::MaxValue
                [uint32]$networkInt = $ipInt -band $maskInt
                [uint32]$broadcastInt = $networkInt -bor $wildcardInt

                # Usable hosts
                if ($parsedPrefix -ge 31) {
                    # /31 = point-to-point (RFC 3021), /32 = single host
                    $firstHostInt = $networkInt
                    $lastHostInt = $broadcastInt
                    $totalHosts = if ($parsedPrefix -eq 32) { 1 } else { 2 }
                    $usableHosts = $totalHosts
                } else {
                    $firstHostInt = $networkInt + 1
                    $lastHostInt = $broadcastInt - 1
                    $totalHosts = [math]::Pow(2, (32 - $parsedPrefix))
                    $usableHosts = $totalHosts - 2
                }

                [PSCustomObject]@{
                    PSTypeName       = 'PSWinOps.SubnetInfo'
                    IPAddress        = $parsedIP.ToString()
                    PrefixLength     = $parsedPrefix
                    SubnetMask       = (ConvertFrom-UInt32 -Value $maskInt).ToString()
                    WildcardMask     = (ConvertFrom-UInt32 -Value $wildcardInt).ToString()
                    NetworkAddress   = (ConvertFrom-UInt32 -Value $networkInt).ToString()
                    BroadcastAddress = (ConvertFrom-UInt32 -Value $broadcastInt).ToString()
                    FirstUsableHost  = (ConvertFrom-UInt32 -Value $firstHostInt).ToString()
                    LastUsableHost   = (ConvertFrom-UInt32 -Value $lastHostInt).ToString()
                    TotalHosts       = [long]$totalHosts
                    UsableHosts      = [long]$usableHosts
                    CIDR             = "{0}/{1}" -f (ConvertFrom-UInt32 -Value $networkInt).ToString(), $parsedPrefix
                    Timestamp        = Get-Date -Format 'o'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to calculate subnet info for '$ip': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed subnet calculation"
    }
}
