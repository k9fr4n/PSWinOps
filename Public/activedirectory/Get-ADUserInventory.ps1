#Requires -Version 5.1
function Get-ADUserInventory {
    <#
    .SYNOPSIS
        Retrieves Active Directory user accounts for inventory and audit review

    .DESCRIPTION
        Lists Active Directory user accounts with key audit properties including
        login history, password status, lockout state, and organizational unit placement.
        By default only enabled accounts are returned unless the -IncludeDisabled switch is specified.

    .PARAMETER SearchBase
        The distinguished name of the OU or container to limit the search scope.

    .PARAMETER Server
        The Active Directory Domain Services instance (domain controller) to connect to.

    .PARAMETER Credential
        The PSCredential object used to authenticate to Active Directory.

    .PARAMETER IncludeDisabled
        When specified, includes disabled user accounts in the results.
        By default only enabled accounts are returned.

    .EXAMPLE
        Get-ADUserInventory

        Retrieves all enabled AD user accounts from the current domain using default credentials.

    .EXAMPLE
        Get-ADUserInventory -SearchBase 'OU=Users,DC=contoso,DC=com' -Server 'DC01.contoso.com'

        Retrieves enabled AD user accounts from a specific OU on a specific domain controller.

    .EXAMPLE
        Get-ADUserInventory -IncludeDisabled -Credential (Get-Credential)

        Retrieves all AD user accounts including disabled ones using alternate credentials.

    .OUTPUTS
        PSWinOps.ADUserInventory
        Returns objects with SamAccountName, UserPrincipalName, DisplayName, Enabled,
        LastLogonDate, LockedOut, PasswordLastSet, PasswordExpired, PasswordNeverExpires,
        CannotChangePassword, OrganizationalUnit, and Timestamp properties.

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
        [switch]$IncludeDisabled
    )

    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting AD user inventory"

    try {
        Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
    }
    catch {
        Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module is not available. Install RSAT: $_"
        return
    }

    $adProperties = @(
        'SamAccountName'
        'UserPrincipalName'
        'DisplayName'
        'Enabled'
        'LastLogonTimestamp'
        'LockedOut'
        'PasswordLastSet'
        'PasswordExpired'
        'PasswordNeverExpires'
        'CannotChangePassword'
        'DistinguishedName'
    )

    $adFilter = if ($IncludeDisabled) { '*' } else { 'Enabled -eq $true' }

    $splatGetADUser = @{
        Filter      = $adFilter
        Properties  = $adProperties
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('SearchBase')) {
        $splatGetADUser['SearchBase'] = $SearchBase
    }
    if ($PSBoundParameters.ContainsKey('Server')) {
        $splatGetADUser['Server'] = $Server
    }
    if ($PSBoundParameters.ContainsKey('Credential')) {
        $splatGetADUser['Credential'] = $Credential
    }

    try {
        $adUserList = Get-ADUser @splatGetADUser
    }
    catch {
        Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query Active Directory: $_"
        return
    }

    if (-not $adUserList) {
        Write-Warning -Message "[$($MyInvocation.MyCommand)] No user accounts matched the specified criteria"
        return
    }

    $inventoryTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $resultList = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($adUser in $adUserList) {
        $lastLogon = $null
        if ($adUser.LastLogonTimestamp -and $adUser.LastLogonTimestamp -gt 0) {
            $lastLogon = [DateTime]::FromFileTime($adUser.LastLogonTimestamp)
        }

        $parentOU = $null
        if ($adUser.DistinguishedName) {
            $dnParts = $adUser.DistinguishedName -split '(?<!\\),', 2
            if ($dnParts.Count -gt 1) {
                $parentOU = $dnParts[1]
            }
        }

        $inventoryItem = [PSCustomObject]@{
            PSTypeName           = 'PSWinOps.ADUserInventory'
            SamAccountName       = $adUser.SamAccountName
            UserPrincipalName    = $adUser.UserPrincipalName
            DisplayName          = $adUser.DisplayName
            Enabled              = $adUser.Enabled
            LastLogonDate        = $lastLogon
            LockedOut            = $adUser.LockedOut
            PasswordLastSet      = $adUser.PasswordLastSet
            PasswordExpired      = $adUser.PasswordExpired
            PasswordNeverExpires = $adUser.PasswordNeverExpires
            CannotChangePassword = $adUser.CannotChangePassword
            OrganizationalUnit   = $parentOU
            Timestamp            = $inventoryTimestamp
        }

        $resultList.Add($inventoryItem)
    }

    $resultList | Sort-Object -Property 'SamAccountName'

    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed - $($resultList.Count) user(s) returned"
}
