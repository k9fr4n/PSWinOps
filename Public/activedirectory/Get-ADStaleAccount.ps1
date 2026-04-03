#Requires -Version 5.1

function Get-ADStaleAccount {
    <#
    .SYNOPSIS
        Finds Active Directory accounts that have been inactive for a specified number of days

    .DESCRIPTION
        Scans Active Directory for user and/or computer accounts that have not logged in
        within the specified number of days. Accounts that have never logged in are included
        by default. Results are sorted by days since last logon in descending order.

    .PARAMETER DaysInactive
        The number of days of inactivity to use as the threshold. Accounts with a last
        logon date older than this value will be returned. Valid range is 1 to 3650.

    .PARAMETER AccountType
        The type of accounts to search for. Valid values are User, Computer, or Both.
        Defaults to Both.

    .PARAMETER SearchBase
        The distinguished name of the OU to search within. If omitted, searches the entire domain.

    .PARAMETER IncludeDisabled
        When specified, includes disabled accounts in the results. By default only enabled
        accounts are returned.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADStaleAccount -DaysInactive 90

        Finds all enabled user and computer accounts inactive for more than 90 days.

    .EXAMPLE
        Get-ADStaleAccount -DaysInactive 180 -AccountType User -Server 'dc01.contoso.com'

        Finds stale user accounts only from a specific domain controller.

    .EXAMPLE
        Get-ADStaleAccount -DaysInactive 60 -IncludeDisabled -SearchBase 'OU=Workstations,DC=contoso,DC=com'

        Finds stale accounts including disabled ones within a specific OU.

    .OUTPUTS
        PSWinOps.ADStaleAccount
        Returns objects with account identity, type, last logon information, and days
        since last logon sorted by most stale first.

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
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 3650)]
        [int]$DaysInactive,

        [Parameter()]
        [ValidateSet('User', 'Computer', 'Both')]
        [string]$AccountType = 'Both',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter()]
        [switch]$IncludeDisabled,

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

        $cutoffDate = (Get-Date).AddDays(-$DaysInactive)
        $adProperties = @('LastLogonDate', 'WhenCreated', 'Enabled', 'Description', 'DistinguishedName')

        $allResults = [System.Collections.Generic.List[object]]::new()
    }

    process {
        try {
            # Query stale user accounts
            if ($AccountType -in @('User', 'Both')) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Searching stale user accounts (inactive > $DaysInactive days)"

                $userFilter = if ($IncludeDisabled) {
                    "LastLogonDate -lt '$cutoffDate' -or -not LastLogonDate -like '*'"
                }
                else {
                    "(LastLogonDate -lt '$cutoffDate' -or -not LastLogonDate -like '*') -and Enabled -eq `$true"
                }

                $staleUsers = Get-ADUser -Filter $userFilter -Properties $adProperties @searchBaseParam @adParams -ErrorAction Stop

                foreach ($user in $staleUsers) {
                    $daysSinceLogon = if ($user.LastLogonDate) {
                        [math]::Round(((Get-Date) - $user.LastLogonDate).TotalDays)
                    }
                    else { $null }

                    $allResults.Add([PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.ADStaleAccount'
                        Name              = $user.Name
                        SamAccountName    = $user.SamAccountName
                        AccountType       = 'User'
                        Enabled           = $user.Enabled
                        LastLogonDate     = $user.LastLogonDate
                        DaysSinceLogon    = $daysSinceLogon
                        WhenCreated       = $user.WhenCreated
                        Description       = $user.Description
                        DistinguishedName = $user.DistinguishedName
                        Timestamp         = Get-Date -Format 'o'
                    })
                }
            }

            # Query stale computer accounts
            if ($AccountType -in @('Computer', 'Both')) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Searching stale computer accounts (inactive > $DaysInactive days)"

                $computerFilter = if ($IncludeDisabled) {
                    "LastLogonDate -lt '$cutoffDate' -or -not LastLogonDate -like '*'"
                }
                else {
                    "(LastLogonDate -lt '$cutoffDate' -or -not LastLogonDate -like '*') -and Enabled -eq `$true"
                }

                $staleComputers = Get-ADComputer -Filter $computerFilter -Properties $adProperties @searchBaseParam @adParams -ErrorAction Stop

                foreach ($computer in $staleComputers) {
                    $daysSinceLogon = if ($computer.LastLogonDate) {
                        [math]::Round(((Get-Date) - $computer.LastLogonDate).TotalDays)
                    }
                    else { $null }

                    $allResults.Add([PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.ADStaleAccount'
                        Name              = $computer.Name
                        SamAccountName    = $computer.SamAccountName
                        AccountType       = 'Computer'
                        Enabled           = $computer.Enabled
                        LastLogonDate     = $computer.LastLogonDate
                        DaysSinceLogon    = $daysSinceLogon
                        WhenCreated       = $computer.WhenCreated
                        Description       = $computer.Description
                        DistinguishedName = $computer.DistinguishedName
                        Timestamp         = Get-Date -Format 'o'
                    })
                }
            }

            # Output sorted by DaysSinceLogon descending (nulls first = never logged in)
            $allResults | Sort-Object -Property @{Expression = 'DaysSinceLogon'; Descending = $true; NullsFirst = $true }
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Search failed: $_"
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed — found $($allResults.Count) stale account(s)"
    }
}
