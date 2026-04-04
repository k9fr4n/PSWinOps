#Requires -Version 5.1
function Get-ADUserGroupInventory {
    <#
    .SYNOPSIS
        Retrieves all group memberships including nested groups for AD users

    .DESCRIPTION
        For one or more Active Directory users, retrieves all group memberships
        including nested (recursive) groups using LDAP recursive member resolution.
        Returns one object per user-group combination for audit and review purposes.
        Users can be specified by identity or discovered from an organizational unit.

    .PARAMETER Identity
        One or more user identifiers (SamAccountName, DN, SID, or GUID).
        Accepts pipeline input. When omitted, queries all users in the domain
        or within the scope defined by SearchBase.

    .PARAMETER SearchBase
        The distinguished name of an OU to scope user discovery.
        Only applies when Identity is not provided.

    .PARAMETER Server
        The Active Directory domain controller to target for all queries.

    .PARAMETER Credential
        The PSCredential object used to authenticate against Active Directory.

    .EXAMPLE
        Get-ADUserGroupInventory -Identity 'jdoe'

        Retrieves all direct and nested group memberships for user jdoe.

    .EXAMPLE
        Get-ADUserGroupInventory -Identity 'jdoe', 'asmith' -Server 'DC01.contoso.com'

        Retrieves group memberships for two users targeting a specific domain controller.

    .EXAMPLE
        'jdoe', 'asmith' | Get-ADUserGroupInventory -Credential (Get-Credential)

        Retrieves group memberships via pipeline input with alternate credentials.

    .OUTPUTS
        PSWinOps.ADUserGroupInventory
        Returns objects with UserName, DisplayName, GroupName, GroupDN,
        GroupScope, GroupCategory, and Timestamp properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('SamAccountName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

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
            Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module not available: $_"
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adSplat['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adSplat['Credential'] = $Credential
        }

        $userList = [System.Collections.Generic.List[object]]::new()
        $identityProvided = $false
        $timestamp = Get-Date -Format 'o'
    }

    process {
        if (-not $moduleAvailable) { return }

        if ($PSBoundParameters.ContainsKey('Identity')) {
            $identityProvided = $true
            foreach ($id in $Identity) {
                $getUserSplat = @{
                    Identity    = $id
                    Properties  = @('DisplayName')
                    ErrorAction = 'Stop'
                }
                try {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying user: $id"
                    $adUser = Get-ADUser @getUserSplat @adSplat
                    $userList.Add($adUser)
                }
                catch {
                    Write-Warning -Message "[$($MyInvocation.MyCommand)] Failed to retrieve user ${id}: $_"
                }
            }
        }
    }

    end {
        if (-not $moduleAvailable) { return }

        if (-not $identityProvided) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] No Identity specified, querying all users"
            $getAllUserSplat = @{
                Filter      = '*'
                Properties  = @('DisplayName')
                ErrorAction = 'Stop'
            }
            if ($PSBoundParameters.ContainsKey('SearchBase')) {
                $getAllUserSplat['SearchBase'] = $SearchBase
            }
            try {
                $discoveredUsers = Get-ADUser @getAllUserSplat @adSplat
                foreach ($discoveredUser in $discoveredUsers) {
                    $userList.Add($discoveredUser)
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query users: $_"
                return
            }
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing $($userList.Count) user(s)"

        $resultList = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($currentUser in $userList) {
            $ldapFilter = "(member:1.2.840.113556.1.4.1941:=$($currentUser.DistinguishedName))"
            $getGroupSplat = @{
                LDAPFilter  = $ldapFilter
                Properties  = @('GroupScope', 'GroupCategory')
                ErrorAction = 'Stop'
            }
            try {
                $groupList = Get-ADGroup @getGroupSplat @adSplat
                if (-not $groupList) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No groups found for user: $($currentUser.SamAccountName)"
                    continue
                }
                foreach ($grp in $groupList) {
                    $inventoryEntry = [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.ADUserGroupInventory'
                        UserName      = $currentUser.SamAccountName
                        DisplayName   = $currentUser.DisplayName
                        GroupName     = $grp.Name
                        GroupDN       = $grp.DistinguishedName
                        GroupScope    = $grp.GroupScope
                        GroupCategory = $grp.GroupCategory
                        Timestamp     = $timestamp
                    }
                    $resultList.Add($inventoryEntry)
                }
            }
            catch {
                Write-Warning -Message "[$($MyInvocation.MyCommand)] Failed to resolve groups for $($currentUser.SamAccountName): $_"
            }
        }

        $resultList | Sort-Object -Property 'UserName', 'GroupName'

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed - $($resultList.Count) record(s) returned"
    }
}
