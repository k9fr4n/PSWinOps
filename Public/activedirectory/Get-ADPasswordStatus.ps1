#Requires -Version 5.1

function Get-ADPasswordStatus {
    <#
    .SYNOPSIS
        Audits password status of all Active Directory user accounts

    .DESCRIPTION
        Returns the password status of all enabled Active Directory user accounts including
        password age, expiry date, applied password policy (Fine-Grained Password Policy or
        Default Domain Policy), and problem flags. By default all enabled accounts are returned.
        Use the -ProblemsOnly switch to filter to accounts with password concerns only
        (expired, never expires, or must change at next logon).

    .PARAMETER ProblemsOnly
        When specified, returns only accounts with at least one password concern:
        expired password, password set to never expire, or must change at next logon.
        By default all enabled accounts are returned.

    .PARAMETER SearchBase
        The distinguished name of the OU to search within. If omitted, searches the entire domain.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADPasswordStatus

        Returns password status for all enabled user accounts in the domain.

    .EXAMPLE
        Get-ADPasswordStatus -ProblemsOnly -Server 'dc01.contoso.com'

        Returns only accounts with password concerns from a specific domain controller.

    .EXAMPLE
        Get-ADPasswordStatus -SearchBase 'OU=Users,DC=contoso,DC=com' | Where-Object DaysUntilExpiry -lt 14

        Returns accounts in a specific OU whose passwords expire within 14 days.

    .OUTPUTS
        PSWinOps.ADPasswordStatus
        Returns objects with account identity, password state flags, applied password
        policy name, password age, expiry date, and days until expiry.

    .NOTES
        Author: Franck SALLET
        Version: 2.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adfinegrainedpasswordpolicy
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$ProblemsOnly,

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
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module is not available: $_"
            return
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adSplat['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adSplat['Credential'] = $Credential
        }

        # -----------------------------------------------------------------
        # Pre-fetch password policies (1 query for default + 1 for all PSOs)
        # -----------------------------------------------------------------
        $defaultMaxAge = [TimeSpan]::Zero
        try {
            $defaultPolicy = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop @adSplat
            $defaultMaxAge = $defaultPolicy.MaxPasswordAge
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Default Domain Policy MaxPasswordAge: $defaultMaxAge"
        }
        catch {
            Write-Warning -Message "[$($MyInvocation.MyCommand)] Could not retrieve Default Domain Password Policy: $_"
        }

        $psoCache = @{}
        try {
            $fineGrainedPolicies = Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction Stop @adSplat
            foreach ($pso in $fineGrainedPolicies) {
                $psoCache[$pso.DistinguishedName] = $pso
            }
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Loaded $($psoCache.Count) Fine-Grained Password Policies"
        }
        catch {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] No Fine-Grained Password Policies found or access denied: $_"
        }
    }

    process {
        $adProperties = @(
            'PasswordLastSet'
            'PasswordExpired'
            'PasswordNeverExpires'
            'PasswordNotRequired'
            'CannotChangePassword'
            'Enabled'
            'Description'
            'DistinguishedName'
            'msDS-ResultantPSO'
        )

        $searchSplat = @{
            Filter      = "Enabled -eq `$true"
            Properties  = $adProperties
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('SearchBase')) {
            $searchSplat['SearchBase'] = $SearchBase
        }

        try {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying enabled users"
            $users = Get-ADUser @searchSplat @adSplat
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query users: $_"
            return
        }

        if (-not $users) {
            Write-Warning -Message "[$($MyInvocation.MyCommand)] No enabled user accounts found"
            return
        }

        $now = Get-Date
        $queryTimestamp = $now.ToString('o')
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($user in $users) {
            $isExpired = $user.PasswordExpired
            $neverExpires = $user.PasswordNeverExpires
            $mustChange = ($null -eq $user.PasswordLastSet)

            if ($ProblemsOnly) {
                if (-not ($isExpired -or $neverExpires -or $mustChange)) {
                    continue
                }
            }

            # Resolve applied password policy
            $policyName = 'Default Domain Policy'
            $maxAge = $defaultMaxAge
            $psoDN = $user.'msDS-ResultantPSO'

            if ($psoDN -and $psoCache.ContainsKey($psoDN)) {
                $appliedPSO = $psoCache[$psoDN]
                $policyName = $appliedPSO.Name
                $maxAge = $appliedPSO.MaxPasswordAge
            }
            elseif ($psoDN) {
                # PSO exists but was not in cache (permission issue) — extract name from DN
                $policyName = ($psoDN -split ',')[0] -replace '^CN='
            }

            # Calculate password age
            $passwordAge = $null
            if ($user.PasswordLastSet) {
                $passwordAge = [math]::Round(($now - $user.PasswordLastSet).TotalDays)
            }

            # Calculate expiry date and days until expiry
            $expiresOn = $null
            $daysUntilExpiry = $null

            if ($user.PasswordLastSet -and -not $neverExpires -and $maxAge -and $maxAge -gt [TimeSpan]::Zero) {
                $expiresOn = $user.PasswordLastSet + $maxAge
                $daysUntilExpiry = [math]::Round(($expiresOn - $now).TotalDays)
            }

            $maxAgeDays = $null
            if ($maxAge -and $maxAge -gt [TimeSpan]::Zero) {
                $maxAgeDays = [math]::Round($maxAge.TotalDays)
            }

            $entry = [PSCustomObject]@{
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
                PasswordPolicy       = $policyName
                MaxPasswordAgeDays   = $maxAgeDays
                PasswordExpiresOn    = $expiresOn
                DaysUntilExpiry      = $daysUntilExpiry
                Description          = $user.Description
                DistinguishedName    = $user.DistinguishedName
                Timestamp            = $queryTimestamp
            }

            $results.Add($entry)
        }

        $results | Sort-Object -Property @{
            Expression = {
                if ($null -eq $_.PasswordAgeDays) { [int]::MaxValue } else { $_.PasswordAgeDays }
            }
            Descending = $true
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed - $($results.Count) account(s) returned"
    }
}
