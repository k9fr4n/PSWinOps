#Requires -Version 5.1

function Test-DNSResolution {
    <#
    .SYNOPSIS
        Tests DNS name resolution across one or more DNS servers.
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
        Test-DNSResolution -Name 'srv-app01.corp.local'

        Resolves the name using the system default DNS server.
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
        Version:       1.0.0
        Last Modified: 2026-03-21
        Requires:      PowerShell 5.1+ / Windows only
        Requires:      DnsClient module (built-in on Windows 8+/Server 2012+)
        Permissions:   No admin required
    .LINK
    https://docs.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DnsResolution')]
    param (
        [Parameter(Mandatory = $true,
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
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting DNS resolution tests"
        # Collect all results to compute Consistent flag at the end
        $allResults = [System.Collections.Generic.List[PSObject]]::new()
        $serversToQuery = if ($DnsServer) { $DnsServer } else { @($null) }
    }

    process {
        foreach ($dnsName in $Name) {
            foreach ($server in $serversToQuery) {
                try {
                    $resolveParams = @{
                        Name        = $dnsName
                        Type        = $Type
                        DnsOnly     = $true
                        ErrorAction = 'Stop'
                    }
                    if ($server) {
                        $resolveParams['Server'] = $server
                    }

                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $dnsResult = Resolve-DnsName @resolveParams
                    $stopwatch.Stop()

                    # Extract IP addresses from the result
                    $ipAddresses = @($dnsResult | Where-Object {
                        $_.QueryType -eq $Type -or
                        ($Type -eq 'A' -and $_.Type -eq 1) -or
                        ($Type -eq 'AAAA' -and $_.Type -eq 28)
                    } | ForEach-Object {
                        if ($_.IPAddress) { $_.IPAddress }
                        elseif ($_.NameHost) { $_.NameHost }
                        elseif ($_.NameExchange) { $_.NameExchange }
                        elseif ($_.Strings) { $_.Strings -join '; ' }
                        else { $_.ToString() }
                    })

                    $resultObj = [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.DnsResolution'
                        Name         = $dnsName
                        DnsServer    = if ($server) { $server } else { '(Default)' }
                        QueryType    = $Type
                        Result       = ($ipAddresses -join ', ')
                        QueryTimeMs  = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)
                        Success      = $true
                        Consistent   = $null  # Computed in end {}
                        ErrorMessage = $null
                        Timestamp    = Get-Date -Format 'o'
                    }
                    $allResults.Add($resultObj)
                } catch {
                    $resultObj = [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.DnsResolution'
                        Name         = $dnsName
                        DnsServer    = if ($server) { $server } else { '(Default)' }
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
        # Compute consistency per DNS name: all successful results must match
        $grouped = $allResults | Group-Object -Property Name
        foreach ($group in $grouped) {
            $successResults = @($group.Group | Where-Object { $_.Success })
            if ($successResults.Count -le 1) {
                # Single server or all failed: consistent by definition
                foreach ($r in $group.Group) { $r.Consistent = $true }
            } else {
                $uniqueResults = @($successResults.Result | Sort-Object -Unique)
                $isConsistent = $uniqueResults.Count -eq 1
                foreach ($r in $group.Group) { $r.Consistent = $isConsistent }
            }
        }

        # Output all collected results
        foreach ($result in $allResults) {
            $result
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Completed DNS resolution tests"
    }
}
