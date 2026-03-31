function Get-PublicIPAddress {
    <#
        .SYNOPSIS
            Retrieves the public IP address of the local or remote computer

        .DESCRIPTION
            Queries external HTTP APIs to determine the public-facing IPv4 and IPv6
            addresses. Uses ipify.org as primary provider with ifconfig.me as fallback.

            For remote computers, the query is executed via Invoke-Command so the
            result reflects each machine's own public IP.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input.

        .PARAMETER Credential
            Optional credential for remote computer connections.

        .PARAMETER TimeoutSec
            HTTP request timeout in seconds. Defaults to 10. Valid range: 1–60.

        .PARAMETER IPv6
            Also attempt to resolve the public IPv6 address. Disabled by default
            because many networks do not have IPv6 connectivity.

        .EXAMPLE
            Get-PublicIPAddress

            Returns the public IP of the local machine.

        .EXAMPLE
            Get-PublicIPAddress -ComputerName 'SRV01' -Credential (Get-Credential)

            Returns the public IP of remote server SRV01.

        .EXAMPLE
            'SRV01', 'SRV02', 'SRV03' | Get-PublicIPAddress -IPv6

            Returns IPv4 and IPv6 public addresses for three servers via pipeline.

        .OUTPUTS
            PSWinOps.PublicIPAddress
            Returns an object per computer with IPv4Address, IPv6Address, Provider, and Timestamp.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-21
            Requires: PowerShell 5.1+ / Windows only
            API: https://api.ipify.org (primary), https://ifconfig.me (fallback)

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.PublicIPAddress')]
    param (
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$TimeoutSec = 10,

        [Parameter(Mandatory = $false)]
        [switch]$IPv6
    )

    begin {
        # ScriptBlock executed locally or remotely to query public IP
        $queryBlock = {
            param ([int]$Timeout, [bool]$IncludeIPv6)

            $ipv4Address = $null
            $ipv6Address = $null
            $provider = $null

            # --- IPv4 ---
            # Primary: ipify
            try {
                $response = Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec $Timeout -ErrorAction Stop
                $ipv4Address = $response.ip
                $provider = 'ipify.org'
            } catch {
                # Fallback: ifconfig.me
                try {
                    $ipv4Address = (Invoke-WebRequest -Uri 'https://ifconfig.me/ip' -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop).Content.Trim()
                    $provider = 'ifconfig.me'
                } catch {
                    $provider = 'Unavailable'
                }
            }

            # --- IPv6 (optional) ---
            if ($IncludeIPv6) {
                try {
                    $response6 = Invoke-RestMethod -Uri 'https://api64.ipify.org?format=json' -TimeoutSec $Timeout -ErrorAction Stop
                    $ipv6Address = $response6.ip
                    # If api64 returned an IPv4, it means no IPv6 connectivity
                    if ($ipv6Address -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                        $ipv6Address = $null
                    }
                } catch {
                    $ipv6Address = $null
                }
            }

            [PSCustomObject]@{
                IPv4Address = $ipv4Address
                IPv6Address = $ipv6Address
                Provider    = $provider
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $rawResult = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $queryBlock -ArgumentList @($TimeoutSec, $IPv6.IsPresent) -Credential $Credential

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.PublicIPAddress'
                    ComputerName = $targetComputer
                    IPv4Address  = $rawResult.IPv4Address
                    IPv6Address  = $rawResult.IPv6Address
                    Provider     = $rawResult.Provider
                    Timestamp    = Get-Date -Format 'o'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }
}
