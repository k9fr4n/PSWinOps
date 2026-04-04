#Requires -Version 5.1

function Get-ADSiteTopology {
    <#
    .SYNOPSIS
        Retrieves Active Directory site topology including sites, subnets, and site links

    .DESCRIPTION
        Returns one object per AD site with associated subnets, site links, replication
        cost/interval, and domain controllers hosted in each site. Provides a complete
        picture of the AD physical topology for capacity planning, replication analysis,
        and subnet auditing.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to. When omitted,
        the current domain is used.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory queries.

    .EXAMPLE
        Get-ADSiteTopology

        Returns topology information for all sites in the current forest.

    .EXAMPLE
        Get-ADSiteTopology -Server 'dc01.contoso.com'

        Returns site topology from a specific domain controller.

    .EXAMPLE
        Get-ADSiteTopology -Credential (Get-Credential) | Where-Object SubnetCount -eq 0

        Finds sites with no subnets assigned, which may indicate configuration issues.

    .OUTPUTS
        PSWinOps.ADSiteTopology
        Returns one object per site with site name, description, subnets, site links,
        replication details, and domain controller list.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adreplicationsite
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module is not available: $_"
            return
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adSplat['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adSplat['Credential'] = $Credential
        }
    }

    process {
        try {
            # --- Sites ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying replication sites"
            $sites = Get-ADReplicationSite -Filter * -Properties 'Description' -ErrorAction Stop @adSplat

            # --- Subnets (pre-fetch all, map to site) ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying replication subnets"
            $allSubnets = Get-ADReplicationSubnet -Filter * -Properties 'Site', 'Location', 'Description' -ErrorAction Stop @adSplat

            $subnetBySite = @{}
            foreach ($subnet in $allSubnets) {
                $siteDN = if ($subnet.Site) { $subnet.Site.ToString() } else { '' }
                if (-not $subnetBySite.ContainsKey($siteDN)) {
                    $subnetBySite[$siteDN] = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
                $subnetBySite[$siteDN].Add([PSCustomObject]@{
                    Name        = $subnet.Name
                    Location    = $subnet.Location
                    Description = $subnet.Description
                })
            }

            # --- Site Links (pre-fetch all, map to sites) ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying replication site links"
            $allSiteLinks = Get-ADReplicationSiteLink -Filter * -Properties 'Cost', 'ReplicationFrequencyInMinutes', 'SitesIncluded', 'Description' -ErrorAction Stop @adSplat

            $siteLinkBySite = @{}
            foreach ($link in $allSiteLinks) {
                foreach ($siteDN in $link.SitesIncluded) {
                    $siteDNStr = $siteDN.ToString()
                    if (-not $siteLinkBySite.ContainsKey($siteDNStr)) {
                        $siteLinkBySite[$siteDNStr] = [System.Collections.Generic.List[PSCustomObject]]::new()
                    }
                    $siteLinkBySite[$siteDNStr].Add([PSCustomObject]@{
                        Name                 = $link.Name
                        Cost                 = $link.Cost
                        ReplicationInterval  = $link.ReplicationFrequencyInMinutes
                        Description          = $link.Description
                    })
                }
            }

            # --- Domain Controllers (pre-fetch all, map to site) ---
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying domain controllers"
            $allDCs = Get-ADDomainController -Filter * -ErrorAction Stop @adSplat

            $dcBySite = @{}
            foreach ($dc in $allDCs) {
                $siteName = $dc.Site
                if (-not $dcBySite.ContainsKey($siteName)) {
                    $dcBySite[$siteName] = [System.Collections.Generic.List[string]]::new()
                }
                $dcBySite[$siteName].Add($dc.HostName)
            }

            # --- Build output per site ---
            $timestamp = Get-Date -Format 'o'

            foreach ($site in $sites | Sort-Object -Property 'Name') {
                $siteDN = $site.DistinguishedName
                $siteName = $site.Name

                $siteSubnets = if ($subnetBySite.ContainsKey($siteDN)) {
                    $subnetBySite[$siteDN]
                }
                else { @() }

                $siteLinks = if ($siteLinkBySite.ContainsKey($siteDN)) {
                    $siteLinkBySite[$siteDN]
                }
                else { @() }

                $siteDCs = if ($dcBySite.ContainsKey($siteName)) {
                    $dcBySite[$siteName]
                }
                else { @() }

                $subnetNames = ($siteSubnets | Select-Object -ExpandProperty 'Name' | Sort-Object) -join ', '
                $linkNames = ($siteLinks | Select-Object -ExpandProperty 'Name' -Unique | Sort-Object) -join ', '
                $dcNames = ($siteDCs | Sort-Object) -join ', '

                [PSCustomObject]@{
                    PSTypeName          = 'PSWinOps.ADSiteTopology'
                    SiteName            = $siteName
                    Description         = $site.Description
                    SubnetCount         = @($siteSubnets).Count
                    Subnets             = $subnetNames
                    SubnetDetails       = $siteSubnets
                    SiteLinkCount       = @($siteLinks).Count
                    SiteLinks           = $linkNames
                    SiteLinkDetails     = $siteLinks
                    DomainControllers   = $dcNames
                    DCCount             = @($siteDCs).Count
                    DistinguishedName   = $siteDN
                    Timestamp           = $timestamp
                }
            }
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to retrieve site topology: $_"
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
