#Requires -Version 5.1
function Get-DnsServerHealth {
    <#
        .SYNOPSIS
            Checks DNS Server role health on Windows servers

        .DESCRIPTION
            Retrieves comprehensive DNS Server health information including service status,
            zone inventory, forwarder configuration, root hints, and self-resolution capability.
            Returns a single typed object per server with an overall health assessment.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-DnsServerHealth

            Checks DNS Server health on the local machine.

        .EXAMPLE
            Get-DnsServerHealth -ComputerName 'DNS01'

            Checks DNS Server health on a single remote server.

        .EXAMPLE
            'DNS01', 'DNS02' | Get-DnsServerHealth -Credential (Get-Credential)

            Checks DNS Server health on multiple remote servers via pipeline.

        .OUTPUTS
            PSWinOps.DnsServerHealth
            Returns one object per server with DNS service status, zone counts,
            forwarder and root hints counts, self-resolution result, and overall health.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: DNS Server role

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/dnsserver/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DnsServerHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')

        $scriptBlock = {
            $data = @{
                ServiceStatus   = 'NotFound'
                ModuleAvailable = $false
                TotalZones      = 0
                PrimaryZones    = 0
                SecondaryZones  = 0
                PausedZones     = 0
                ForwarderCount  = 0
                RootHintsCount  = 0
                SelfResolution  = $false
            }

            # Check DNS service status
            $dnsSvc = Get-Service -Name 'DNS' -ErrorAction SilentlyContinue
            if ($dnsSvc) {
                $data.ServiceStatus = $dnsSvc.Status.ToString()
            }

            # Check DnsServer module availability
            $dnsModule = Get-Module -Name 'DnsServer' -ListAvailable -ErrorAction SilentlyContinue
            if ($dnsModule) {
                $data.ModuleAvailable = $true
            }

            if ($data.ModuleAvailable -and $data.ServiceStatus -eq 'Running') {
                # Zone inventory
                $zones = Get-DnsServerZone -ErrorAction SilentlyContinue
                if ($zones) {
                    $data.TotalZones    = @($zones).Count
                    $data.PrimaryZones  = @($zones | Where-Object -Property ZoneType -EQ -Value 'Primary').Count
                    $data.SecondaryZones = @($zones | Where-Object -Property ZoneType -EQ -Value 'Secondary').Count
                    $data.PausedZones   = @($zones | Where-Object -Property IsPaused -EQ -Value $true).Count
                }

                # Forwarder configuration
                $forwarders = Get-DnsServerForwarder -ErrorAction SilentlyContinue
                if ($forwarders -and $forwarders.IPAddress) {
                    $data.ForwarderCount = @($forwarders.IPAddress).Count
                }

                # Root hints
                $rootHints = Get-DnsServerRootHint -ErrorAction SilentlyContinue
                if ($rootHints) {
                    $data.RootHintsCount = @($rootHints).Count
                }

                # Self-resolution test
                $resolveResult = Resolve-DnsName -Name $env:COMPUTERNAME -Server 'localhost' -DnsOnly -ErrorAction SilentlyContinue
                if ($resolveResult) {
                    $data.SelfResolution = $true
                }
            }

            $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $isLocal = $localNames -contains $machine

                if ($isLocal) {
                    $result = & $scriptBlock
                }
                else {
                    $invokeParams = @{
                        ComputerName = $machine
                        ScriptBlock  = $scriptBlock
                        ErrorAction  = 'Stop'
                    }
                    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $result = Invoke-Command @invokeParams
                }

                # Compute OverallHealth outside the scriptblock
                if (-not $result.ModuleAvailable) {
                    $healthStatus = 'RoleUnavailable'
                }
                elseif ($result.ServiceStatus -ne 'Running' -or -not $result.SelfResolution) {
                    $healthStatus = 'Critical'
                }
                elseif ($result.PausedZones -gt 0 -or $result.ForwarderCount -eq 0) {
                    $healthStatus = 'Degraded'
                }
                else {
                    $healthStatus = 'Healthy'
                }

                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.DnsServerHealth'
                    ComputerName   = $displayName
                    ServiceName    = 'DNS'
                    ServiceStatus  = $result.ServiceStatus
                    TotalZones     = [int]$result.TotalZones
                    PrimaryZones   = [int]$result.PrimaryZones
                    SecondaryZones = [int]$result.SecondaryZones
                    PausedZones    = [int]$result.PausedZones
                    ForwarderCount = [int]$result.ForwarderCount
                    RootHintsCount = [int]$result.RootHintsCount
                    SelfResolution = [bool]$result.SelfResolution
                    OverallHealth  = $healthStatus
                    Timestamp      = Get-Date -Format 'o'
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