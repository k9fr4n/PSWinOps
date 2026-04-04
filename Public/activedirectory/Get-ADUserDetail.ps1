#Requires -Version 5.1

function Get-ADUserDetail {
    <#
    .SYNOPSIS
        Retrieves detailed Active Directory user account information

    .DESCRIPTION
        Queries Active Directory for comprehensive user account details including
        account status, password information, group membership count, and organizational unit.
        Supports pipeline input for processing multiple user identities at once.

    .PARAMETER Identity
        One or more user identities to query. Accepts SamAccountName, DistinguishedName, or UserPrincipalName.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADUserDetail -Identity 'jdoe'

        Retrieves detailed information for the user with SamAccountName jdoe.

    .EXAMPLE
        Get-ADUserDetail -Identity 'jdoe' -Server 'dc01.contoso.com'

        Retrieves user details from a specific domain controller.

    .EXAMPLE
        'jdoe', 'asmith' | Get-ADUserDetail

        Retrieves details for multiple users via pipeline input.

    .OUTPUTS
        PSWinOps.ADUserDetail
        Returns a custom object with comprehensive user account properties including
        account status, password state, group membership count, and organizational unit.

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

        $adProperties = @(
            'DisplayName'
            'EmailAddress'
            'Department'
            'Title'
            'Company'
            'Office'
            'Manager'
            'Description'
            'Enabled'
            'LockedOut'
            'LockoutTime'
            'LastLogonDate'
            'LastBadPasswordAttempt'
            'BadLogonCount'
            'PasswordLastSet'
            'PasswordExpired'
            'PasswordNeverExpires'
            'CannotChangePassword'
            'AccountExpirationDate'
            'WhenCreated'
            'WhenChanged'
            'MemberOf'
            'DistinguishedName'
        )
    }

    process {
        foreach ($identityValue in $Identity) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying user: $identityValue"

                $user = Get-ADUser -Identity $identityValue -Properties $adProperties @adParams -ErrorAction Stop

                [PSCustomObject]@{
                    PSTypeName             = 'PSWinOps.ADUserDetail'
                    SamAccountName         = $user.SamAccountName
                    DisplayName            = $user.DisplayName
                    EmailAddress           = $user.EmailAddress
                    Department             = $user.Department
                    Title                  = $user.Title
                    Company                = $user.Company
                    Office                 = $user.Office
                    Manager                = if ($user.Manager) { ($user.Manager -split ',')[0] -replace '^CN=' } else { $null }
                    Description            = $user.Description
                    Enabled                = $user.Enabled
                    LockedOut              = $user.LockedOut
                    LockoutTime            = $user.LockoutTime
                    LastLogonDate          = $user.LastLogonDate
                    LastBadPasswordAttempt = $user.LastBadPasswordAttempt
                    BadLogonCount          = $user.BadLogonCount
                    PasswordLastSet        = $user.PasswordLastSet
                    PasswordExpired        = $user.PasswordExpired
                    PasswordNeverExpires   = $user.PasswordNeverExpires
                    CannotChangePassword   = $user.CannotChangePassword
                    AccountExpirationDate  = $user.AccountExpirationDate
                    WhenCreated            = $user.WhenCreated
                    WhenChanged            = $user.WhenChanged
                    MemberOfCount          = if ($user.MemberOf) { @($user.MemberOf).Count } else { 0 }
                    OrganizationalUnit     = ($user.DistinguishedName -replace '^CN=[^,]+,')
                    DistinguishedName      = $user.DistinguishedName
                    Timestamp              = Get-Date -Format 'o'
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query user '$identityValue': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
