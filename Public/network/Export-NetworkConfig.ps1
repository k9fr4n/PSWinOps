#Requires -Version 5.1

function Export-NetworkConfig {
    <#
        .SYNOPSIS
            Exports a complete network configuration snapshot to JSON or displays it as a summary

        .DESCRIPTION
            Collects all network configuration data from one or more computers into a single
            structured object: adapters, IP addresses, routes, DNS, ARP cache, listening ports,
            and firewall profile status.

            The output can be piped to ConvertTo-Json for documentation, compared between
            machines, or used for audit/compliance purposes.

        .PARAMETER ComputerName
            One or more computer names to collect config from. Defaults to the local machine.
            Accepts pipeline input.

        .PARAMETER Credential
            Optional credential for remote computer connections.

        .PARAMETER Path
            Optional file path to export JSON directly. If not specified, returns objects.

        .PARAMETER ExcludeFirewall
            Exclude Windows Firewall profile status from the export.
            By default, firewall profiles are included.

        .PARAMETER ExcludeListeners
            Exclude listening ports from the export.
            By default, listening ports are included.

        .PARAMETER IncludeARP
            Include ARP cache in the export. Disabled by default because output can be large.

        .EXAMPLE
            Export-NetworkConfig

            Returns a complete network config object for the local machine.

        .EXAMPLE
            Export-NetworkConfig -Path 'C:\docs\netconfig.json'

            Exports local network config to a JSON file.

        .EXAMPLE
            Export-NetworkConfig -ComputerName 'SRV01' -Credential (Get-Credential) | ConvertTo-Json -Depth 5

            Exports remote server config as JSON.

        .EXAMPLE
            'SRV01', 'SRV02' | Export-NetworkConfig -IncludeARP -ExcludeFirewall

            Exports config including ARP cache but without firewall profiles from two servers.

        .OUTPUTS
            PSWinOps.NetworkConfig

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   Admin recommended for full details, required for remote

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.NetworkConfig')]
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
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$ExcludeFirewall,

        [Parameter(Mandatory = $false)]
        [switch]$ExcludeListeners,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeARP
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting network config export"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')

        $queryScriptBlock = {
            param([bool]$CollectFirewall, [bool]$CollectListeners, [bool]$CollectARP)

            $config = @{}

            # Hostname
            $config['Hostname'] = $env:COMPUTERNAME

            # Adapters
            $config['Adapters'] = @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
                @{
                    Name        = $_.Name
                    Description = $_.InterfaceDescription
                    Status      = [string]$_.Status
                    Speed       = $_.LinkSpeed
                    MacAddress  = $_.MacAddress
                    MTU         = $_.MtuSize
                    IfIndex     = $_.ifIndex
                }
            })

            # IP Addresses
            $config['IPAddresses'] = @(Get-NetIPAddress -ErrorAction SilentlyContinue |
                Where-Object { $_.AddressFamily -eq 2 -and $_.IPAddress -ne '127.0.0.1' } | ForEach-Object {
                @{
                    InterfaceAlias = $_.InterfaceAlias
                    IPAddress      = $_.IPAddress
                    PrefixLength   = $_.PrefixLength
                    AddressFamily  = 'IPv4'
                    Type           = [string]$_.PrefixOrigin
                }
            })

            # DNS
            $config['DnsServers'] = @(Get-DnsClientServerAddress -ErrorAction SilentlyContinue |
                Where-Object { $_.ServerAddresses } | ForEach-Object {
                @{
                    InterfaceAlias = $_.InterfaceAlias
                    Servers        = $_.ServerAddresses
                }
            })

            # DNS Suffix
            try {
                $dnsSuffix = (Get-DnsClient -ErrorAction SilentlyContinue |
                    Where-Object { $_.ConnectionSpecificSuffix } |
                    Select-Object -First 1).ConnectionSpecificSuffix
                $config['DnsSuffix'] = $dnsSuffix
            } catch {
                $config['DnsSuffix'] = $null
            }

            # Routes
            $config['Routes'] = @(Get-NetRoute -ErrorAction SilentlyContinue |
                Where-Object { $_.DestinationPrefix -ne 'ff00::/8' -and $_.DestinationPrefix -ne '::/0' } |
                Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object {
                @{
                    DestinationPrefix = $_.DestinationPrefix
                    NextHop           = $_.NextHop
                    RouteMetric       = $_.RouteMetric
                    InterfaceAlias    = $_.InterfaceAlias
                }
            })

            # Firewall profiles
            if ($CollectFirewall) {
                $config['FirewallProfiles'] = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
                    @{
                        Name    = $_.Name
                        Enabled = $_.Enabled
                        DefaultInboundAction  = [string]$_.DefaultInboundAction
                        DefaultOutboundAction = [string]$_.DefaultOutboundAction
                    }
                })
            }

            # Listening ports
            if ($CollectListeners) {
                $processCache = @{}
                Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
                    $processCache[$_.Id] = $_.ProcessName
                }
                $config['ListeningPorts'] = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
                    @{
                        Protocol    = 'TCP'
                        LocalPort   = $_.LocalPort
                        LocalAddress = $_.LocalAddress
                        ProcessName = if ($processCache.ContainsKey($_.OwningProcess)) { $processCache[$_.OwningProcess] } else { "PID:$($_.OwningProcess)" }
                    }
                })
            }

            # ARP cache
            if ($CollectARP) {
                $config['ARPCache'] = @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
                    @{
                        IPAddress     = $_.IPAddress
                        LinkLayerAddr = $_.LinkLayerAddress
                        State         = [string]$_.State
                    }
                })
            }

            return $config
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $isLocal = $localNames -contains $targetComputer
                $timestamp = Get-Date -Format 'o'

                Write-Verbose "[$($MyInvocation.MyCommand)] Collecting network config from '$targetComputer'"

                $queryArgs = @((-not $ExcludeFirewall.IsPresent), (-not $ExcludeListeners.IsPresent), $IncludeARP.IsPresent)

                if ($isLocal) {
                    $rawConfig = & $queryScriptBlock @queryArgs
                } else {
                    $invokeParams = @{
                        ComputerName = $targetComputer
                        ScriptBlock  = $queryScriptBlock
                        ArgumentList = $queryArgs
                        ErrorAction  = 'Stop'
                    }
                    if ($hasCredential) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $rawConfig = Invoke-Command @invokeParams
                }

                $configObj = [PSCustomObject]@{
                    PSTypeName        = 'PSWinOps.NetworkConfig'
                    ComputerName      = $targetComputer
                    Hostname          = $rawConfig.Hostname
                    Adapters          = $rawConfig.Adapters
                    IPAddresses       = $rawConfig.IPAddresses
                    DnsServers        = $rawConfig.DnsServers
                    DnsSuffix         = $rawConfig.DnsSuffix
                    Routes            = $rawConfig.Routes
                    FirewallProfiles  = $rawConfig.FirewallProfiles
                    ListeningPorts    = $rawConfig.ListeningPorts
                    ARPCache          = $rawConfig.ARPCache
                    Timestamp         = $timestamp
                }

                # Export to file if Path specified
                if ($Path) {
                    $jsonPath = if ($ComputerName.Count -gt 1 -or $PSCmdlet.MyInvocation.ExpectingInput) {
                        $dir = Split-Path $Path -Parent
                        $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
                        $ext = [System.IO.Path]::GetExtension($Path)
                        Join-Path $dir "${base}_${targetComputer}${ext}"
                    } else {
                        $Path
                    }
                    $configObj | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8 -ErrorAction Stop
                    Write-Verbose "[$($MyInvocation.MyCommand)] Exported config to '$jsonPath'"
                }

                $configObj
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed network config export"
    }
}
