#Requires -Version 5.1
function Get-ADComputerInventory {
    <#
    .SYNOPSIS
        Retrieves Active Directory computer accounts with key audit properties

    .DESCRIPTION
        Lists all Active Directory computer accounts with inventory and audit properties.
        Returns a typed PSWinOps.ADComputerInventory object per computer with logon,
        password, OS, and lifecycle metadata for review and compliance reporting.

    .PARAMETER SearchBase
        The distinguished name of the OU to search. Defaults to the entire domain.

    .PARAMETER Server
        The domain controller to target for the query.

    .PARAMETER Credential
        The PSCredential object to authenticate against Active Directory.

    .PARAMETER IncludeDisabled
        Include disabled computer accounts in the results. By default only enabled accounts are returned.

    .EXAMPLE
        Get-ADComputerInventory

        Returns all enabled computer accounts from the current domain.

    .EXAMPLE
        Get-ADComputerInventory -SearchBase 'OU=Servers,DC=corp,DC=local' -Server 'DC01'

        Returns enabled computer accounts from the Servers OU querying DC01.

    .EXAMPLE
        Get-ADComputerInventory -IncludeDisabled -Credential (Get-Credential)

        Returns all computer accounts including disabled ones using explicit credentials.

    .OUTPUTS
        PSWinOps.ADComputerInventory
        Returns objects with Name, SamAccountName, Enabled, LastLogonDate, LockedOut,
        PasswordExpired, PasswordLastSet, WhenChanged, WhenCreated, OperatingSystem,
        OrganizationalUnit, and Timestamp properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adcomputer
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

    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting AD computer inventory"

    try {
        Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
    }
    catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'GetADComputerInventoryModuleNotFound',
            [System.Management.Automation.ErrorCategory]::NotInstalled,
            $null
        )
        $PSCmdlet.WriteError($errorRecord)
        return
    }

    $adProperties = @(
        'Name'
        'SamAccountName'
        'Enabled'
        'LastLogonTimestamp'
        'LockedOut'
        'PasswordExpired'
        'PasswordLastSet'
        'whenChanged'
        'whenCreated'
        'OperatingSystem'
    )

    $adFilter = if ($IncludeDisabled) { '*' } else { 'Enabled -eq $true' }

    $splatParams = @{
        Filter      = $adFilter
        Properties  = $adProperties
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('SearchBase')) {
        $splatParams['SearchBase'] = $SearchBase
    }
    if ($PSBoundParameters.ContainsKey('Server')) {
        $splatParams['Server'] = $Server
    }
    if ($PSBoundParameters.ContainsKey('Credential')) {
        $splatParams['Credential'] = $Credential
    }

    try {
        $adComputerList = Get-ADComputer @splatParams
    }
    catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'GetADComputerInventoryFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )
        $PSCmdlet.WriteError($errorRecord)
        return
    }

    if (-not $adComputerList) {
        Write-Warning -Message "[$($MyInvocation.MyCommand)] No computer accounts matched the specified criteria"
        return
    }

    $queryTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $resultList = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($computer in $adComputerList) {
        $lastLogon = $null
        if ($computer.LastLogonTimestamp -and $computer.LastLogonTimestamp -gt 0) {
            $lastLogon = [DateTime]::FromFileTime($computer.LastLogonTimestamp)
        }

        $ouPath = $null
        if ($computer.DistinguishedName) {
            $dnParts = $computer.DistinguishedName -split '(?<!\\),', 2
            if ($dnParts.Count -gt 1) {
                $ouPath = $dnParts[1]
            }
        }

        $inventoryObject = [PSCustomObject]@{
            PSTypeName         = 'PSWinOps.ADComputerInventory'
            Name               = $computer.Name
            SamAccountName     = $computer.SamAccountName
            Enabled            = $computer.Enabled
            LastLogonDate      = $lastLogon
            LockedOut          = $computer.LockedOut
            PasswordExpired    = $computer.PasswordExpired
            PasswordLastSet    = $computer.PasswordLastSet
            WhenChanged        = $computer.whenChanged
            WhenCreated        = $computer.whenCreated
            OperatingSystem    = $computer.OperatingSystem
            OrganizationalUnit = $ouPath
            Timestamp          = $queryTimestamp
        }

        $resultList.Add($inventoryObject)
    }

    $resultList | Sort-Object -Property 'Name'

    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed - $($resultList.Count) computer(s) returned"
}
