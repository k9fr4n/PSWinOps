#Requires -Version 5.1

function Get-ADLockedAccount {
    <#
    .SYNOPSIS
        Finds all currently locked Active Directory user accounts

    .DESCRIPTION
        Searches Active Directory for user accounts that are currently locked out.
        Returns detailed lockout information including lockout time, bad logon count,
        and last bad password attempt. Results are sorted by most recent lockout first.

    .PARAMETER SearchBase
        The distinguished name of the OU to search within. If omitted, searches the entire domain.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADLockedAccount

        Finds all locked accounts in the domain.

    .EXAMPLE
        Get-ADLockedAccount -Server 'dc01.contoso.com'

        Finds all locked accounts from a specific domain controller.

    .EXAMPLE
        Get-ADLockedAccount -SearchBase 'OU=Users,DC=contoso,DC=com'

        Finds locked accounts within a specific OU.

    .OUTPUTS
        PSWinOps.ADLockedAccount
        Returns objects with account identity, lockout time, bad password attempt details,
        sorted by most recent lockout first.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-03
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/search-adaccount
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
    }

    process {
        try {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Searching for locked accounts"

            $lockedAccounts = Search-ADAccount -LockedOut -UsersOnly @searchBaseParam @adParams -ErrorAction Stop

            if (-not $lockedAccounts) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] No locked accounts found"
                return
            }

            $results = [System.Collections.Generic.List[object]]::new()

            foreach ($account in $lockedAccounts) {
                try {
                    $userDetail = Get-ADUser -Identity $account.SamAccountName `
                        -Properties 'LockedOut', 'LockoutTime', 'BadLogonCount', 'LastBadPasswordAttempt', 'Description', 'Enabled' `
                        @adParams -ErrorAction Stop

                    $results.Add([PSCustomObject]@{
                        PSTypeName             = 'PSWinOps.ADLockedAccount'
                        Name                   = $userDetail.Name
                        SamAccountName         = $userDetail.SamAccountName
                        Enabled                = $userDetail.Enabled
                        LockoutTime            = $userDetail.LockoutTime
                        BadLogonCount          = $userDetail.BadLogonCount
                        LastBadPasswordAttempt = $userDetail.LastBadPasswordAttempt
                        Description            = $userDetail.Description
                        DistinguishedName      = $userDetail.DistinguishedName
                        Timestamp              = Get-Date -Format 'o'
                    })
                }
                catch {
                    Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to get details for '$($account.SamAccountName)': $_"
                    continue
                }
            }

            $results | Sort-Object -Property 'LockoutTime' -Descending
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Search failed: $_"
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
