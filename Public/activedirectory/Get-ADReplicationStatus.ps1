#Requires -Version 5.1
function Get-ADReplicationStatus {
    <#
    .SYNOPSIS
        Retrieves Active Directory replication status for one or more domain controllers

    .DESCRIPTION
        Queries replication partner metadata and failure information for Active Directory
        domain controllers. When no Server is specified, automatically discovers all DCs
        in the current domain via Get-ADDomainController. Returns one object per DC/partner/
        partition combination with health status derived from replication result codes and
        consecutive failure counts.

    .PARAMETER Server
        One or more domain controller names or FQDNs to query. When omitted, all domain
        controllers in the current domain are discovered automatically.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        The PSCredential object used to authenticate against Active Directory.

    .EXAMPLE
        Get-ADReplicationStatus

        Discovers all domain controllers and returns replication status for each.

    .EXAMPLE
        Get-ADReplicationStatus -Server 'DC01.contoso.com'

        Returns replication status for a specific domain controller.

    .EXAMPLE
        'DC01', 'DC02' | Get-ADReplicationStatus -Credential (Get-Credential)

        Returns replication status for multiple DCs via pipeline with alternate credentials.

    .OUTPUTS
        PSWinOps.ADReplicationStatus
        Returns objects with Server, Partner, Partition, LastAttempt, LastSuccess,
        LastResult, ConsecutiveFailures, Status, and Timestamp properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)
        Requires: Domain Admin or equivalent for cross-DC queries

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adreplicationpartnermetadata
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ComputerName', 'HostName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $moduleAvailable = $false
        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
            $moduleAvailable = $true
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module is not available: $_"
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adSplat['Credential'] = $Credential
        }

        $timestamp = Get-Date -Format 'o'
        $dcList = [System.Collections.Generic.List[string]]::new()
        $serverProvided = $false
    }

    process {
        if (-not $moduleAvailable) { return }

        if ($PSBoundParameters.ContainsKey('Server')) {
            $serverProvided = $true
            foreach ($dc in $Server) {
                $dcList.Add($dc)
            }
        }
    }

    end {
        if (-not $moduleAvailable) { return }

        if (-not $serverProvided) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] No Server specified, discovering domain controllers"
            try {
                $discoveredDCs = Get-ADDomainController -Filter * -ErrorAction Stop @adSplat
                foreach ($dc in $discoveredDCs) {
                    $dcList.Add($dc.HostName)
                }
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Discovered $($dcList.Count) domain controller(s)"
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to discover domain controllers: $_"
                return
            }
        }

        if ($dcList.Count -eq 0) {
            Write-Warning -Message "[$($MyInvocation.MyCommand)] No domain controllers to query"
            return
        }

        foreach ($targetDC in $dcList) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying replication metadata on $targetDC"

                $replPartners = Get-ADReplicationPartnerMetadata -Target $targetDC -ErrorAction Stop @adSplat

                if (-not $replPartners) {
                    Write-Warning -Message "[$($MyInvocation.MyCommand)] No replication partners found for $targetDC"
                    continue
                }

                $failureMap = @{}
                try {
                    $failures = Get-ADReplicationFailure -Target $targetDC -ErrorAction Stop @adSplat
                    foreach ($failure in $failures) {
                        $failureMap[$failure.Partner] = $failure
                    }
                }
                catch {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Could not retrieve failure data for ${targetDC}: $_"
                }

                foreach ($partner in $replPartners) {
                    $partnerName = if ($partner.Partner) {
                        ($partner.Partner -split ',')[0] -replace '^CN='
                    }
                    else {
                        'Unknown'
                    }

                    $partitionShort = if ($partner.Partition) {
                        ($partner.Partition -split ',')[0] -replace '^DC=|^CN='
                    }
                    else {
                        'Unknown'
                    }

                    $consecutiveFailures = $partner.ConsecutiveReplicationFailures
                    $lastResult = $partner.LastReplicationResult

                    $status = if ($lastResult -eq 0 -and $consecutiveFailures -eq 0) {
                        'Healthy'
                    }
                    elseif ($consecutiveFailures -gt 0 -and $consecutiveFailures -le 5) {
                        'Warning'
                    }
                    else {
                        'Critical'
                    }

                    [PSCustomObject]@{
                        PSTypeName          = 'PSWinOps.ADReplicationStatus'
                        Server              = $targetDC
                        Partner             = $partnerName
                        Partition           = $partitionShort
                        PartitionDN         = $partner.Partition
                        LastAttempt         = $partner.LastReplicationAttempt
                        LastSuccess         = $partner.LastReplicationSuccess
                        LastResult          = $lastResult
                        ConsecutiveFailures = $consecutiveFailures
                        Status              = $status
                        Timestamp           = $timestamp
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query replication on ${targetDC}: $_"
            }
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
