#Requires -Version 5.1
function Get-ADGroupInventory {
    <#
    .SYNOPSIS
        Inventories Active Directory groups with member count and metadata

    .DESCRIPTION
        Retrieves all Active Directory groups and returns audit-ready objects including
        member count, scope, category, and organizational unit path extracted from the
        distinguished name. By default only groups with at least one member are returned.

    .PARAMETER SearchBase
        The distinguished name of the OU to search. Defaults to the entire domain root.

    .PARAMETER Server
        The Active Directory Domain Services instance (domain controller) to connect to.

    .PARAMETER Credential
        The PSCredential object used to authenticate the AD query.

    .PARAMETER IncludeEmpty
        When specified, includes groups with zero members in the output.
        By default only groups with at least one member are returned.

    .EXAMPLE
        Get-ADGroupInventory

        Returns all non-empty AD groups in the current domain sorted by name.

    .EXAMPLE
        Get-ADGroupInventory -SearchBase 'OU=Groups,DC=corp,DC=local' -Server 'DC01'

        Returns non-empty groups from a specific OU targeting a specific domain controller.

    .EXAMPLE
        Get-ADGroupInventory -IncludeEmpty -Credential (Get-Credential)

        Returns all groups including empty ones using alternate credentials.

    .OUTPUTS
        PSWinOps.ADGroupInventory
        Returns objects with Name, SamAccountName, GroupScope, GroupCategory,
        MemberCount, Description, OrganizationalUnit, and Timestamp properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroup
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [switch]$IncludeEmpty
    )

    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting AD group inventory"

    try {
        Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
    }
    catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'GetADGroupInventoryModuleNotFound',
            [System.Management.Automation.ErrorCategory]::NotInstalled,
            $null
        )
        $PSCmdlet.WriteError($errorRecord)
        return
    }

    $adGroupParams = @{
        Filter      = '*'
        Properties  = @(
            'Name'
            'SamAccountName'
            'GroupScope'
            'GroupCategory'
            'DistinguishedName'
            'Member'
            'Description'
        )
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('SearchBase')) {
        $adGroupParams['SearchBase'] = $SearchBase
    }
    if ($PSBoundParameters.ContainsKey('Server')) {
        $adGroupParams['Server'] = $Server
    }
    if ($PSBoundParameters.ContainsKey('Credential')) {
        $adGroupParams['Credential'] = $Credential
    }

    try {
        $adGroups = Get-ADGroup @adGroupParams
    }
    catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'GetADGroupInventoryFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )
        $PSCmdlet.WriteError($errorRecord)
        return
    }

    if (-not $adGroups) {
        Write-Warning -Message "[$($MyInvocation.MyCommand)] No groups matched the specified criteria"
        return
    }

    $queryTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $resultList = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($group in $adGroups) {
        [int]$memberCount = 0
        if ($group.Member) {
            $memberCount = $group.Member.Count
        }

        if (-not $IncludeEmpty -and $memberCount -eq 0) {
            continue
        }

        $ouPath = $null
        if ($group.DistinguishedName) {
            $dnParts = $group.DistinguishedName -split '(?<!\\),', 2
            if ($dnParts.Count -gt 1) {
                $ouPath = $dnParts[1]
            }
        }

        $entry = [PSCustomObject]@{
            PSTypeName         = 'PSWinOps.ADGroupInventory'
            Name               = $group.Name
            SamAccountName     = $group.SamAccountName
            GroupScope         = [string]$group.GroupScope
            GroupCategory      = [string]$group.GroupCategory
            MemberCount        = $memberCount
            Description        = $group.Description
            OrganizationalUnit = $ouPath
            Timestamp          = $queryTimestamp
        }

        $resultList.Add($entry)
    }

    $resultList | Sort-Object -Property 'Name'

    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed - $($resultList.Count) group(s) returned"
}
