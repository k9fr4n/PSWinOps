#Requires -Version 5.1
#Requires -Modules ActiveDirectory

function Get-ADPasswordStatus {
    <#
    .SYNOPSIS
        Audits password status of Active Directory user accounts

    .DESCRIPTION
        Scans Active Directory for user accounts with specific password conditions such as
        expired passwords, passwords set to never expire, or accounts that must change
        password at next logon. Results are sorted by password age in descending order.

    .PARAMETER Status
        One or more password status filters to apply. Valid values are Expired, NeverExpires,
        MustChange, and All. Defaults to All. Multiple values can be combined.

    .PARAMETER SearchBase
        The distinguished name of the OU to search within. If omitted, searches the entire domain.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADPasswordStatus

        Returns all enabled users with any password status concern.

    .EXAMPLE
        Get-ADPasswordStatus -Status 'NeverExpires' -Server 'dc01.contoso.com'

        Finds accounts with passwords set to never expire from a specific DC.

    .EXAMPLE
        Get-ADPasswordStatus -Status 'Expired', 'MustChange' -SearchBase 'OU=Users,DC=contoso,DC=com'

        Finds accounts with expired passwords or must-change flags in a specific OU.

    .OUTPUTS
        PSWinOps.ADPasswordStatus
        Returns objects with account identity, password state flags, password age,
        and last set date sorted by oldest password first.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-03
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Expired', 'NeverExpires', 'MustChange', 'All')]
        [string[]]$Status = 'All',

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

        $searchBaseParam = @{}
        if ($PSBoundParameters.ContainsKey('SearchBase')) {
            $searchBaseParam['SearchBase'] = $SearchBase
        }

        $adProperties = @(
            'PasswordLastSet'
            'PasswordExpired'
            'PasswordNeverExpires'
            'PasswordNotRequired'
            'CannotChangePassword'
            'Enabled'
            'Description'
            'DistinguishedName'
        )
    }

    process {
        try {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying enabled users with password properties"

            $users = Get-ADUser -Filter "Enabled -eq `$true" -Properties $adProperties @searchBaseParam @adParams -ErrorAction Stop

            $results = [System.Collections.Generic.List[object]]::new()

            foreach ($user in $users) {
                $isExpired = $user.PasswordExpired
                $neverExpires = $user.PasswordNeverExpires
                $mustChange = ($null -eq $user.PasswordLastSet)

                # Apply status filter
                $include = $false
                if ('All' -in $Status) {
                    $include = ($isExpired -or $neverExpires -or $mustChange)
                }
                else {
                    if ('Expired' -in $Status -and $isExpired) { $include = $true }
                    if ('NeverExpires' -in $Status -and $neverExpires) { $include = $true }
                    if ('MustChange' -in $Status -and $mustChange) { $include = $true }
                }

                if ($include) {
                    $passwordAge = if ($user.PasswordLastSet) {
                        [math]::Round(((Get-Date) - $user.PasswordLastSet).TotalDays)
                    }
                    else { $null }

                    $results.Add([PSCustomObject]@{
                        PSTypeName           = 'PSWinOps.ADPasswordStatus'
                        Name                 = $user.Name
                        SamAccountName       = $user.SamAccountName
                        Enabled              = $user.Enabled
                        PasswordExpired      = $isExpired
                        PasswordNeverExpires = $neverExpires
                        MustChangePassword   = $mustChange
                        PasswordNotRequired  = $user.PasswordNotRequired
                        PasswordLastSet      = $user.PasswordLastSet
                        PasswordAgeDays      = $passwordAge
                        Description          = $user.Description
                        DistinguishedName    = $user.DistinguishedName
                        Timestamp            = Get-Date -Format 'o'
                    })
                }
            }

            # Sort by password age descending (oldest first, nulls first)
            $results | Sort-Object -Property @{Expression = 'PasswordAgeDays'; Descending = $true; NullsFirst = $true }
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Search failed: $_"
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed — found $($results.Count) account(s)"
    }
}
