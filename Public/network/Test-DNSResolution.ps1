#Requires -Version 5.1

function Test-DNSResolution {
    <#
        .SYNOPSIS
            Tests DNS name resolution across one or more DNS servers

        .DESCRIPTION
            Resolves a hostname against multiple DNS servers and compares the results.
            Useful for diagnosing DNS propagation issues, split-horizon DNS, or
            identifying inconsistent resolution between internal and external DNS.

            Uses Resolve-DnsName cmdlet under the hood.

        .PARAMETER Name
            One or more DNS names to resolve. Accepts pipeline input.

        .PARAMETER DnsServer
            One or more DNS server IP addresses or hostnames to query.
            If not specified, uses the system default DNS resolver.

        .PARAMETER Type
            DNS record type to query. Default: A.
            Valid values: A, AAAA, CNAME, MX, NS, PTR, SOA, SRV, TXT.

        .EXAMPLE
            Test-DNSResolution 'srv-app01.corp.local'

            Resolves the name using the system default DNS server (positional).

        .EXAMPLE
            Test-DNSResolution -Name 'google.com' -DnsServer '8.8.8.8', '1.1.1.1'

            Compares resolution of google.com across Google DNS and Cloudflare.

        .EXAMPLE
            Test-DNSResolution -Name 'srv01.corp.local' -DnsServer '10.0.0.1', '10.0.0.2', '8.8.8.8'

            Checks if internal name resolves consistently across internal and external DNS.

        .EXAMPLE
            'srv01', 'srv02', 'srv03' | Test-DNSResolution -DnsServer '10.0.0.1'

            Resolves multiple names via pipeline against a specific DNS server.

        .OUTPUTS
            PSWinOps.DnsResolution

        .NOTES
            Author:        Franck SALLET
            Version:       1.1.0
            Last Modified: 2026-03-22
            Requires:      PowerShell 5.1+ / Windows only
            Requires:      DnsClient module (built-in on Windows 8+/Server 2012+)
            Permissions:   No admin required

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DnsResolution')]
    param (
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DnsServer,

        [Parameter(Mandatory = $false)]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SOA', 'SRV', 'TXT')]
        [string]$Type = 'A'
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting DNS resolution tests (Type=$Type)"

        # Collect all results to compute Consistent flag at the end
        $allResults = [System.Collections.Generic.List[PSObject]]::new()

        # Determine whether we query specific servers or system default
        $useDefaultDns = -not $PSBoundParameters.ContainsKey('DnsServer')
    }

    process {
        foreach ($dnsName in $Name) {

            # Build the list of servers to iterate over
            # Avoid @($null) sentinel — use explicit branching to prevent
            # foreach-over-null silently skipping on some PS versions
            if ($useDefaultDns) {
                $serverList = @([string]::Empty)
            } else {
                $serverList = $DnsServer
            }

            for ($i = 0; $i -lt $serverList.Count; $i++) {
                $server = $serverList[$i]
                $isDefault = [string]::IsNullOrEmpty($server)
                $serverLabel = if ($isDefault) {
                    '(Default)'
                } else {
                    $server
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Resolving '$dnsName' (Type=$Type) via $serverLabel"

                try {
                    $resolveParams = @{
                        Name        = $dnsName
                        Type        = $Type
                        DnsOnly     = $true
                        ErrorAction = 'Stop'
                    }
                    if (-not $isDefault) {
                        $resolveParams['Server'] = $server
                    }

                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $dnsResult = Resolve-DnsName @resolveParams
                    $stopwatch.Stop()

                    $elapsedMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)

                    # Extract values matching the requested record type
                    $records = @($dnsResult | Where-Object {
                            $_.QueryType -eq $Type -or
                            ($Type -eq 'A' -and $_.Type -eq 1) -or
                            ($Type -eq 'AAAA' -and $_.Type -eq 28)
                        } | ForEach-Object {
                            if ($_.IPAddress) {
                                $_.IPAddress
                            } elseif ($_.NameHost) {
                                $_.NameHost
                            } elseif ($_.NameExchange) {
                                $_.NameExchange
                            } elseif ($_.NameAdministrator) {
                                $_.NameAdministrator
                            } elseif ($_.NameTarget) {
                                $_.NameTarget
                            } elseif ($_.Strings) {
                                $_.Strings -join '; '
                            } else {
                                $_.ToString()
                            }
                        })

                    $hasRecords = $records.Count -gt 0

                    $resultObj = [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.DnsResolution'
                        Name         = $dnsName
                        DnsServer    = $serverLabel
                        QueryType    = $Type
                        Result       = if ($hasRecords) {
                            $records -join ', '
                        } else {
                            $null
                        }
                        QueryTimeMs  = $elapsedMs
                        Success      = $hasRecords
                        Consistent   = $null  # Computed in end {}
                        ErrorMessage = if (-not $hasRecords) {
                            "No $Type records found in DNS response"
                        } else {
                            $null
                        }
                        Timestamp    = Get-Date -Format 'o'
                    }

                    Write-Verbose "[$($MyInvocation.MyCommand)] '$dnsName' via $serverLabel — Success=$hasRecords, Records=$($records.Count), ${elapsedMs}ms"
                    $allResults.Add($resultObj)

                } catch {
                    Write-Verbose "[$($MyInvocation.MyCommand)] '$dnsName' via $serverLabel — FAILED: $_"

                    $resultObj = [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.DnsResolution'
                        Name         = $dnsName
                        DnsServer    = $serverLabel
                        QueryType    = $Type
                        Result       = $null
                        QueryTimeMs  = $null
                        Success      = $false
                        Consistent   = $null
                        ErrorMessage = $_.Exception.Message
                        Timestamp    = Get-Date -Format 'o'
                    }
                    $allResults.Add($resultObj)
                }
            }
        }
    }

    end {
        # Compute consistency per DNS name (only meaningful with multiple servers)
        $multiServer = -not $useDefaultDns -and $DnsServer.Count -gt 1

        $grouped = $allResults | Group-Object -Property Name
        foreach ($group in $grouped) {
            if (-not $multiServer) {
                # Single server or default: consistency is not applicable
                foreach ($r in $group.Group) {
                    $r.Consistent = $null
                }
            } else {
                $successResults = @($group.Group | Where-Object { $_.Success })
                if ($successResults.Count -le 1) {
                    # Zero or one succeeded: cannot determine consistency
                    foreach ($r in $group.Group) {
                        $r.Consistent = $null
                    }
                } else {
                    $uniqueResults = @($successResults.Result | Sort-Object -Unique)
                    $isConsistent = $uniqueResults.Count -eq 1
                    foreach ($r in $group.Group) {
                        $r.Consistent = $isConsistent
                    }
                }
            }
        }

        # Output all collected results
        foreach ($result in $allResults) {
            $result
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Completed — $($allResults.Count) result(s)"
    }
}
