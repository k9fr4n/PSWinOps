#Requires -Version 5.1

function Get-ADGroupMembership {
    <#
    .SYNOPSIS
        Retrieves members of an Active Directory group

    .DESCRIPTION
        Queries Active Directory for group membership details with optional recursive
        enumeration. When the Recursive switch is used, both direct and nested members
        are returned with an IsDirect flag indicating membership type.

    .PARAMETER Identity
        One or more group identities to query. Accepts SamAccountName or DistinguishedName.

    .PARAMETER Recursive
        When specified, retrieves all nested members transitively and marks each as direct or nested.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADGroupMembership -Identity 'Domain Admins'

        Retrieves direct members of the Domain Admins group.

    .EXAMPLE
        Get-ADGroupMembership -Identity 'Domain Admins' -Recursive -Server 'dc01.contoso.com'

        Retrieves all nested members from a specific domain controller with direct/nested flags.

    .EXAMPLE
        'Domain Admins', 'Enterprise Admins' | Get-ADGroupMembership

        Retrieves direct members of multiple groups via pipeline input.

    .OUTPUTS
        PSWinOps.ADGroupMember
        Returns custom objects with group name, member details, object class,
        and IsDirect flag sorted by ObjectClass then MemberName.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-03
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroupmember
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ADGroupMember')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter()]
        [switch]$Recursive,

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
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop
        }
        catch {
            throw "[$($MyInvocation.MyCommand)] Failed to import ActiveDirectory module: $_"
        }

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
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying group: $identityValue"

                $group = Get-ADGroup -Identity $identityValue @adParams -ErrorAction Stop
                $resolvedGroupName = $group.Name

                $memberResults = [System.Collections.Generic.List[object]]::new()

                if ($Recursive) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Retrieving recursive membership for: $resolvedGroupName"

                    $directMembers = Get-ADGroupMember -Identity $identityValue @adParams -ErrorAction Stop
                    $allMembers = Get-ADGroupMember -Identity $identityValue -Recursive @adParams -ErrorAction Stop

                    $directDNSet = [System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase
                    )
                    foreach ($directMember in $directMembers) {
                        [void]$directDNSet.Add($directMember.DistinguishedName)
                    }

                    foreach ($member in $allMembers) {
                        $isDirect = $directDNSet.Contains($member.DistinguishedName)
                        $memberResults.Add([PSCustomObject]@{
                            PSTypeName        = 'PSWinOps.ADGroupMember'
                            GroupName         = $resolvedGroupName
                            MemberName        = $member.Name
                            SamAccountName    = $member.SamAccountName
                            ObjectClass       = $member.ObjectClass
                            DistinguishedName = $member.DistinguishedName
                            IsDirect          = $isDirect
                            Timestamp         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        })
                    }
                }
                else {
                    $directMembers = Get-ADGroupMember -Identity $identityValue @adParams -ErrorAction Stop

                    foreach ($member in $directMembers) {
                        $memberResults.Add([PSCustomObject]@{
                            PSTypeName        = 'PSWinOps.ADGroupMember'
                            GroupName         = $resolvedGroupName
                            MemberName        = $member.Name
                            SamAccountName    = $member.SamAccountName
                            ObjectClass       = $member.ObjectClass
                            DistinguishedName = $member.DistinguishedName
                            IsDirect          = $true
                            Timestamp         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        })
                    }
                }

                $memberResults | Sort-Object -Property 'ObjectClass', 'MemberName'
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query group '$identityValue': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
