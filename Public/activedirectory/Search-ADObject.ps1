#Requires -Version 5.1

function Search-ADObject {
    <#
    .SYNOPSIS
        Searches Active Directory objects using a raw LDAP filter

    .DESCRIPTION
        Performs a flexible Active Directory search using a raw LDAP filter string.
        Supports configurable search base, scope, additional properties, and result
        set size limiting for controlled queries against large directories.

    .PARAMETER LDAPFilter
        The raw LDAP filter string to use for the search query.

    .PARAMETER SearchBase
        The distinguished name of the search root OU or container.

    .PARAMETER SearchScope
        The scope of the search. Valid values are Base, OneLevel, and Subtree. Defaults to Subtree.

    .PARAMETER Properties
        Additional AD properties to retrieve beyond the default Name, ObjectClass, and DistinguishedName.

    .PARAMETER ResultSetSize
        Maximum number of results to return. Valid range is 1 to 100000.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Search-ADObject -LDAPFilter '(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=2))'

        Finds all disabled user accounts in the domain.

    .EXAMPLE
        Search-ADObject -LDAPFilter '(&(objectClass=computer)(operatingSystem=*Server 2022*))' -Properties 'OperatingSystem', 'LastLogonDate' -Server 'dc01.contoso.com'

        Finds computers running Server 2022 with additional properties from a specific DC.

    .EXAMPLE
        Search-ADObject -LDAPFilter '(objectClass=group)' -SearchBase 'OU=Security Groups,DC=contoso,DC=com' -ResultSetSize 50

        Searches for groups within a specific OU with a result limit of 50.

    .OUTPUTS
        PSWinOps.ADSearchResult
        Returns custom objects with Name, ObjectClass, DistinguishedName, any requested
        additional properties, and a Timestamp field.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-03
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adobject
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LDAPFilter,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter()]
        [ValidateSet('Base', 'OneLevel', 'Subtree')]
        [string]$SearchScope = 'Subtree',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Properties,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$ResultSetSize,

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
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Searching with filter: $LDAPFilter"

        $baseProperties = @('Name', 'ObjectClass', 'DistinguishedName')
        $userProperties = if ($PSBoundParameters.ContainsKey('Properties')) { $Properties } else { @() }
        $propertiesToFetch = ($baseProperties + $userProperties) | Select-Object -Unique

        $searchParams = @{
            LDAPFilter  = $LDAPFilter
            SearchScope = $SearchScope
            Properties  = $propertiesToFetch
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('SearchBase')) {
            $searchParams['SearchBase'] = $SearchBase
        }
        if ($PSBoundParameters.ContainsKey('ResultSetSize')) {
            $searchParams['ResultSetSize'] = $ResultSetSize
        }

        try {
            $searchResults = Get-ADObject @searchParams @adParams

            foreach ($searchResult in $searchResults) {
                $outputProps = [ordered]@{
                    PSTypeName        = 'PSWinOps.ADSearchResult'
                    Name              = $searchResult.Name
                    ObjectClass       = $searchResult.ObjectClass
                    DistinguishedName = $searchResult.DistinguishedName
                }

                foreach ($propName in $userProperties) {
                    if ($propName -notin @('Name', 'ObjectClass', 'DistinguishedName')) {
                        $outputProps[$propName] = $searchResult.$propName
                    }
                }

                $outputProps['Timestamp'] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

                [PSCustomObject]$outputProps
            }
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Search failed: $_"
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
