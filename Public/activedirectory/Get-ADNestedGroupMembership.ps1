#Requires -Version 5.1
function Get-ADNestedGroupMembership {
    <#
    .SYNOPSIS
        Retrieves all nested Active Directory group memberships for a principal

    .DESCRIPTION
        Resolves all direct and nested group memberships for one or more AD principals
        using a single LDAP query with the LDAP_MATCHING_RULE_IN_CHAIN OID (1.2.840.113556.1.4.1941).
        This approach is significantly faster than recursive Get-ADPrincipalGroupMembership calls
        because the domain controller performs the recursion server-side in a single round-trip.
        Each returned object indicates whether the membership is direct or inherited (nested).

    .PARAMETER Identity
        The SamAccountName, DistinguishedName, or GUID of one or more AD principals
        (user, group, or computer) to query. Accepts pipeline input.

    .PARAMETER Server
        The target domain controller to query. If omitted, the default DC discovery is used.

    .PARAMETER Credential
        Alternate PSCredential to authenticate against Active Directory.

    .EXAMPLE
        Get-ADNestedGroupMembership -Identity 'jdoe'

        Retrieves all direct and nested group memberships for user jdoe using the default DC.

    .EXAMPLE
        Get-ADNestedGroupMembership -Identity 'jdoe' -Server 'DC01.contoso.com'

        Retrieves all group memberships for user jdoe targeting a specific domain controller.

    .EXAMPLE
        'jdoe', 'svc-app01' | Get-ADNestedGroupMembership

        Retrieves nested group memberships for multiple principals via pipeline input.

    .OUTPUTS
        PSWinOps.ADNestedGroupMembership
        Returns one object per group membership with Identity, GroupName, GroupDN,
        GroupCategory, GroupScope, Description, IsDirect, and Timestamp properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-03
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory RSAT module

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/4e638665-f466-4597-93c4-12f2ebfde571
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # Validate ActiveDirectory module availability
        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop
        }
        catch {
            $errorMessage = "[$($MyInvocation.MyCommand)] ActiveDirectory module not available: $_"
            Write-Error -Message $errorMessage
            throw
        }

        # Build common splatting hash for AD cmdlets
        $adParams = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adParams['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adParams['Credential'] = $Credential
        }
    }

    process {
        foreach ($identityValue in $Identity) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing identity: $identityValue"

            try {
                # Step 1: Resolve the principal to its DN and direct MemberOf
                $adObject = Get-ADObject -Filter "SamAccountName -eq '$identityValue'" `
                    -Properties 'ObjectClass', 'MemberOf', 'SamAccountName' `
                    @adParams -ErrorAction Stop

                if (-not $adObject) {
                    Write-Error -Message "[$($MyInvocation.MyCommand)] Identity not found in AD: $identityValue"
                    continue
                }

                $resolvedSam = $adObject.SamAccountName
                $distinguishedName = $adObject.DistinguishedName

                # Build a hashset of direct group DNs for O(1) lookup
                $directGroupDNs = [System.Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase
                )
                if ($adObject.MemberOf) {
                    foreach ($memberDN in $adObject.MemberOf) {
                        $null = $directGroupDNs.Add($memberDN)
                    }
                }

                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Found $($directGroupDNs.Count) direct group(s) for $identityValue"

                # Step 2: Single LDAP query for ALL nested groups via LDAP_MATCHING_RULE_IN_CHAIN
                $ldapFilter = "(member:1.2.840.113556.1.4.1941:=$distinguishedName)"
                $nestedGroups = Get-ADGroup -LDAPFilter $ldapFilter `
                    -Properties 'GroupCategory', 'GroupScope', 'Description' `
                    @adParams -ErrorAction Stop

                if (-not $nestedGroups) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No group memberships found for $identityValue"
                    continue
                }

                # Step 3: Build results with IsDirect flag, sorted by GroupName
                $sortedGroups = $nestedGroups | Sort-Object -Property 'Name'

                foreach ($group in $sortedGroups) {
                    $isDirect = $directGroupDNs.Contains($group.DistinguishedName)

                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.ADNestedGroupMembership'
                        Identity      = $resolvedSam
                        GroupName     = $group.Name
                        GroupDN       = $group.DistinguishedName
                        GroupCategory = [string]$group.GroupCategory
                        GroupScope    = [string]$group.GroupScope
                        Description   = $group.Description
                        IsDirect      = $isDirect
                        Timestamp     = Get-Date -Format 'o'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Error processing identity '$identityValue': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
