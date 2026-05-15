#Requires -Version 5.1

function Get-ADStaleComputer {
    <#
    .SYNOPSIS
        Finds Active Directory computer accounts that have been inactive for a specified number of days

    .DESCRIPTION
        Scans Active Directory for computer accounts that have not authenticated within
        the specified number of days. Computers that have never logged in are included
        by default. Returns operating system details alongside staleness information
        to help identify obsolete machines. Results are sorted by days since last logon
        in descending order.

    .PARAMETER DaysInactive
        The number of days of inactivity to use as the threshold. Computer accounts with a
        last logon date older than this value will be returned. Defaults to 90 days.
        Valid range is 1 to 3650.

    .PARAMETER SearchBase
        The distinguished name of the OU to search within. If omitted, searches the entire domain.

    .PARAMETER IncludeDisabled
        When specified, includes disabled computer accounts in the results. By default only
        enabled accounts are returned.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADStaleComputer

        Finds all enabled computer accounts inactive for more than 90 days (default).

    .EXAMPLE
        Get-ADStaleComputer -DaysInactive 180 -Server 'dc01.contoso.com'

        Finds stale computers from a specific domain controller using a 180-day threshold.

    .EXAMPLE
        Get-ADStaleComputer -DaysInactive 60 -IncludeDisabled -SearchBase 'OU=Workstations,DC=contoso,DC=com'

        Finds stale computers including disabled ones within a specific OU.

    .OUTPUTS
        PSWinOps.ADStaleComputer
        Returns objects with computer identity, operating system information, last logon
        date, and days since last logon sorted by most stale first.

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
        [ValidateRange(1, 3650)]
        [int]$DaysInactive = 90,

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
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting — threshold: $DaysInactive days"

        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
        }
        catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'GetADStaleComputerModuleNotFound',
                [System.Management.Automation.ErrorCategory]::NotInstalled,
                $null
            )
            $PSCmdlet.WriteError($errorRecord)
            return
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adSplat['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adSplat['Credential'] = $Credential
        }

        $cutoffDate = (Get-Date).AddDays(-$DaysInactive)

        $adProperties = @(
            'LastLogonDate'
            'PasswordLastSet'
            'WhenCreated'
            'Enabled'
            'Description'
            'OperatingSystem'
            'OperatingSystemVersion'
            'IPv4Address'
            'DistinguishedName'
        )
    }

    process {
        $searchSplat = @{
            Filter      = if ($IncludeDisabled) { '*' } else { "Enabled -eq `$true" }
            Properties  = $adProperties
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('SearchBase')) {
            $searchSplat['SearchBase'] = $SearchBase
        }

        try {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying computer accounts"
            $computers = Get-ADComputer @searchSplat @adSplat
        }
        catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'GetADStaleComputerFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
            $PSCmdlet.WriteError($errorRecord)
            return
        }

        if (-not $computers) {
            Write-Warning -Message "[$($MyInvocation.MyCommand)] No computer accounts found"
            return
        }

        $now = Get-Date
        $queryTimestamp = $now.ToString('yyyy-MM-dd HH:mm:ss')
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($computer in $computers) {
            $isStale = ($null -eq $computer.LastLogonDate) -or ($computer.LastLogonDate -lt $cutoffDate)
            if (-not $isStale) { continue }

            $daysSinceLogon = if ($computer.LastLogonDate) {
                [math]::Round(($now - $computer.LastLogonDate).TotalDays)
            }
            else { $null }

            $daysSincePasswordSet = if ($computer.PasswordLastSet) {
                [math]::Round(($now - $computer.PasswordLastSet).TotalDays)
            }
            else { $null }

            $results.Add([PSCustomObject]@{
                PSTypeName            = 'PSWinOps.ADStaleComputer'
                Name                  = $computer.Name
                SamAccountName        = $computer.SamAccountName
                Enabled               = $computer.Enabled
                OperatingSystem       = $computer.OperatingSystem
                OperatingSystemVersion = $computer.OperatingSystemVersion
                IPv4Address           = $computer.IPv4Address
                LastLogonDate         = $computer.LastLogonDate
                DaysSinceLogon        = $daysSinceLogon
                PasswordLastSet       = $computer.PasswordLastSet
                DaysSincePasswordSet  = $daysSincePasswordSet
                WhenCreated           = $computer.WhenCreated
                Description           = $computer.Description
                DistinguishedName     = $computer.DistinguishedName
                Timestamp             = $queryTimestamp
            })
        }

        $results | Sort-Object -Property @{
            Expression = {
                if ($null -eq $_.DaysSinceLogon) { [int]::MaxValue } else { $_.DaysSinceLogon }
            }
            Descending = $true
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed — $($results.Count) stale computer(s) found"
    }
}
