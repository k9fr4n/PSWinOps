#Requires -Version 5.1

function Invoke-ADSecurityAudit {
    <#
    .SYNOPSIS
        Performs a comprehensive Active Directory security audit inspired by PingCastle

    .DESCRIPTION
        Runs 32 security checks across four categories (Privileged Accounts, Anomalies,
        Configuration, and Stale Objects) against the current or specified AD domain.
        Each finding is returned as an individual object with category, severity, affected
        account, detail, and remediation guidance. No external dependencies are required;
        all checks use standard ActiveDirectory module cmdlets.

    .PARAMETER Category
        Limits the audit to one or more specific categories. Valid values are
        PrivilegedAccounts, Anomaly, Configuration, and StaleObjects. When omitted,
        all categories are audited.

    .PARAMETER StaleThresholdDays
        Number of days used to determine stale accounts and passwords. Defaults to 180.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory queries.

    .EXAMPLE
        Invoke-ADSecurityAudit

        Runs all 32 checks against the current domain and returns all findings.

    .EXAMPLE
        Invoke-ADSecurityAudit -Category 'PrivilegedAccounts' -Server 'dc01.contoso.com'

        Audits only privileged account checks against a specific domain controller.

    .EXAMPLE
        Invoke-ADSecurityAudit | Where-Object Severity -eq 'Critical' | Export-Csv -Path 'critical-findings.csv'

        Exports all critical findings to CSV for remediation tracking.

    .OUTPUTS
        PSWinOps.ADSecurityFinding
        Returns one object per finding with Category, CheckId, Check, Severity,
        SamAccountName, ObjectType, Detail, and Recommendation properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)
        Requires: Domain read access (Domain Admin recommended for full coverage)

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://www.pingcastle.com/documentation/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('PrivilegedAccounts', 'Anomaly', 'Configuration', 'StaleObjects')]
        [string[]]$Category,

        [Parameter()]
        [ValidateRange(30, 3650)]
        [int]$StaleThresholdDays = 180,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting AD Security Audit"

        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module is not available: $_"
            return
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Server')) { $adSplat['Server'] = $Server }
        if ($PSBoundParameters.ContainsKey('Credential')) { $adSplat['Credential'] = $Credential }

        $runAll = -not $PSBoundParameters.ContainsKey('Category')
        $findings = [System.Collections.Generic.List[PSCustomObject]]::new()
        $timestamp = Get-Date -Format 'o'
        $now = Get-Date
        $cutoffDate = $now.AddDays(-$StaleThresholdDays)

        # ---- Helper ----
        function Add-Finding {
            param(
                [string]$Category, [string]$CheckId, [string]$Check,
                [string]$Severity, [string]$SamAccountName,
                [string]$ObjectType, [string]$Detail, [string]$Recommendation
            )
            $findings.Add([PSCustomObject]@{
                PSTypeName     = 'PSWinOps.ADSecurityFinding'
                Category       = $Category
                CheckId        = $CheckId
                Check          = $Check
                Severity       = $Severity
                SamAccountName = $SamAccountName
                ObjectType     = $ObjectType
                Detail         = $Detail
                Recommendation = $Recommendation
                Timestamp      = $timestamp
            })
        }

        # ---- Pre-fetch data ----
        Write-Progress -Activity 'AD Security Audit' -Status 'Gathering AD data...' -PercentComplete 5

        $userProps = @(
            'SamAccountName', 'Name', 'Enabled', 'AdminCount', 'LastLogonDate',
            'PasswordLastSet', 'PasswordNeverExpires', 'PasswordNotRequired',
            'AllowReversiblePasswordEncryption', 'DoesNotRequirePreAuth',
            'UseDESKeyOnly', 'TrustedForDelegation', 'TrustedToAuthForDelegation',
            'ServicePrincipalName', 'SIDHistory',
            'msDS-AllowedToDelegateTo',
            'Description', 'DistinguishedName'
        )

        $computerProps = @(
            'SamAccountName', 'Name', 'Enabled', 'OperatingSystem', 'OperatingSystemVersion',
            'TrustedForDelegation', 'TrustedToAuthForDelegation',
            'msDS-AllowedToDelegateTo', 'msDS-AllowedToActOnBehalfOfOtherIdentity',
            'ms-Mcs-AdmPwdExpirationTime',
            'LastLogonDate', 'PasswordLastSet', 'Description', 'DistinguishedName'
        )

        try {
            $allUsers = @(Get-ADUser -Filter "Enabled -eq `$true" -Properties $userProps -ErrorAction Stop @adSplat)
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Fetched $($allUsers.Count) enabled users"
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query users: $_"
            $allUsers = @()
        }

        try {
            $allComputers = @(Get-ADComputer -Filter "Enabled -eq `$true" -Properties $computerProps -ErrorAction Stop @adSplat)
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Fetched $($allComputers.Count) enabled computers"
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query computers: $_"
            $allComputers = @()
        }

        # Domain controllers list (to exclude from delegation checks)
        try {
            $domainControllers = @(Get-ADDomainController -Filter * -ErrorAction Stop @adSplat)
            $dcNames = $domainControllers | ForEach-Object { $_.HostName.Split('.')[0].ToUpper() }
        }
        catch {
            $domainControllers = @()
            $dcNames = @()
        }

        # Build privileged members set
        $privilegedGroupNames = @(
            'Domain Admins', 'Enterprise Admins', 'Schema Admins',
            'Administrators', 'Account Operators', 'Backup Operators',
            'Server Operators', 'Print Operators'
        )

        $privilegedDNs = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        foreach ($groupName in $privilegedGroupNames) {
            try {
                $members = Get-ADGroupMember -Identity $groupName -Recursive -ErrorAction Stop @adSplat
                foreach ($member in $members) {
                    [void]$privilegedDNs.Add($member.distinguishedName)
                }
            }
            catch {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Could not enumerate '$groupName': $_"
            }
        }

        # Domain and forest info
        try {
            $domain = Get-ADDomain -ErrorAction Stop @adSplat
            $forest = Get-ADForest -ErrorAction Stop @adSplat
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query domain/forest: $_"
        }
    }

    process {
        # ==================================================================
        # CATEGORY 1: PRIVILEGED ACCOUNTS
        # ==================================================================
        if ($runAll -or 'PrivilegedAccounts' -in $Category) {
            Write-Progress -Activity 'AD Security Audit' -Status 'Checking Privileged Accounts...' -PercentComplete 20

            # PA-01: Schema Admins not empty
            try {
                $schemaMembers = @(Get-ADGroupMember -Identity 'Schema Admins' -ErrorAction Stop @adSplat)
                foreach ($member in $schemaMembers) {
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-01' `
                        -Check 'Schema Admins Not Empty' -Severity 'High' `
                        -SamAccountName $member.SamAccountName -ObjectType $member.objectClass `
                        -Detail "Schema Admins should be empty in production. Member: $($member.Name)" `
                        -Recommendation 'Remove all members from Schema Admins unless performing a schema modification'
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] PA-01 skipped: $_" }

            # PA-02: Protected Users group empty or underused
            try {
                $protectedMembers = @(Get-ADGroupMember -Identity 'Protected Users' -ErrorAction Stop @adSplat)
                $adminUsers = $allUsers | Where-Object { $_.AdminCount -eq 1 }
                $adminCount = @($adminUsers).Count
                if ($protectedMembers.Count -eq 0 -and $adminCount -gt 0) {
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-02' `
                        -Check 'Protected Users Group Empty' -Severity 'High' `
                        -SamAccountName 'N/A' -ObjectType 'Group' `
                        -Detail "Protected Users group is empty but $adminCount privileged accounts exist" `
                        -Recommendation 'Add privileged user accounts to the Protected Users group to prevent credential theft'
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] PA-02 skipped: $_" }

            # PA-03: AdminCount orphans
            foreach ($user in $allUsers) {
                if ($user.AdminCount -eq 1 -and -not $privilegedDNs.Contains($user.DistinguishedName)) {
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-03' `
                        -Check 'AdminCount Orphan' -Severity 'Medium' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "AdminCount=1 but not a member of any privileged group. AdminSDHolder ACL is stale." `
                        -Recommendation 'Clear AdminCount attribute and reset ACL inheritance on this account'
                }
            }

            # PA-04: Kerberoastable admin accounts
            foreach ($user in $allUsers) {
                if ($user.AdminCount -eq 1 -and $user.ServicePrincipalName.Count -gt 0) {
                    $spns = ($user.ServicePrincipalName | Select-Object -First 3) -join ', '
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-04' `
                        -Check 'Kerberoastable Admin Account' -Severity 'Critical' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "Privileged account with SPN set: $spns. Kerberos TGS can be requested and cracked offline." `
                        -Recommendation 'Remove SPN, use gMSA, or move account to Protected Users group'
                }
            }

            # PA-05: Privileged accounts with stale passwords
            foreach ($user in $allUsers) {
                if ($user.AdminCount -eq 1 -and $user.PasswordLastSet -and $user.PasswordLastSet -lt $cutoffDate) {
                    $age = [math]::Round(($now - $user.PasswordLastSet).TotalDays)
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-05' `
                        -Check 'Stale Admin Password' -Severity 'High' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "Privileged account password is $age days old (threshold: $StaleThresholdDays days)" `
                        -Recommendation 'Rotate password immediately and enforce regular rotation for privileged accounts'
                }
            }

            # PA-06: Inactive privileged accounts
            foreach ($user in $allUsers) {
                if ($user.AdminCount -eq 1 -and ($null -eq $user.LastLogonDate -or $user.LastLogonDate -lt $cutoffDate)) {
                    $lastLogon = if ($user.LastLogonDate) { $user.LastLogonDate.ToString('yyyy-MM-dd') } else { 'Never' }
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-06' `
                        -Check 'Inactive Privileged Account' -Severity 'High' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "Privileged account has not logged in since $lastLogon" `
                        -Recommendation 'Disable or remove inactive privileged accounts to reduce attack surface'
                }
            }

            # PA-07: Privileged accounts with Password Never Expires
            foreach ($user in $allUsers) {
                if ($user.AdminCount -eq 1 -and $user.PasswordNeverExpires) {
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-07' `
                        -Check 'Admin Password Never Expires' -Severity 'High' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail 'Privileged account has PasswordNeverExpires flag set' `
                        -Recommendation 'Remove PasswordNeverExpires flag and enforce regular password rotation'
                }
            }

            # PA-08: Service accounts in Domain Admins / Enterprise Admins
            foreach ($user in $allUsers) {
                if ($user.ServicePrincipalName.Count -gt 0 -and $privilegedDNs.Contains($user.DistinguishedName)) {
                    Add-Finding -Category 'PrivilegedAccounts' -CheckId 'PA-08' `
                        -Check 'Service Account in Privileged Group' -Severity 'High' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "Service account (has SPN) is a member of a privileged group" `
                        -Recommendation 'Use gMSA and apply least-privilege principle. Remove from privileged groups.'
                }
            }
        }

        # ==================================================================
        # CATEGORY 2: ANOMALIES
        # ==================================================================
        if ($runAll -or 'Anomaly' -in $Category) {
            Write-Progress -Activity 'AD Security Audit' -Status 'Checking Anomalies...' -PercentComplete 40

            # AN-01: AS-REP Roastable (DoesNotRequirePreAuth)
            foreach ($user in $allUsers) {
                if ($user.DoesNotRequirePreAuth -eq $true) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-01' `
                        -Check 'AS-REP Roastable Account' -Severity 'Critical' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail 'Kerberos pre-authentication is disabled. AS-REP can be captured and cracked offline.' `
                        -Recommendation 'Enable Kerberos pre-authentication unless absolutely required'
                }
            }

            # AN-02: Password Not Required
            foreach ($user in $allUsers) {
                if ($user.PasswordNotRequired -eq $true) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-02' `
                        -Check 'Password Not Required' -Severity 'Critical' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail 'PASSWD_NOTREQD flag is set. Account can have an empty password.' `
                        -Recommendation 'Clear the PASSWD_NOTREQD flag and set a strong password'
                }
            }

            # AN-03: Reversible Encryption
            foreach ($user in $allUsers) {
                if ($user.AllowReversiblePasswordEncryption -eq $true) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-03' `
                        -Check 'Reversible Encryption Enabled' -Severity 'Critical' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail 'Password is stored with reversible encryption (effectively cleartext).' `
                        -Recommendation 'Disable reversible encryption and force a password change'
                }
            }

            # AN-04: DES-only Kerberos
            foreach ($user in $allUsers) {
                if ($user.UseDESKeyOnly -eq $true) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-04' `
                        -Check 'DES-Only Kerberos Encryption' -Severity 'High' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail 'Account is restricted to DES encryption, which is cryptographically broken.' `
                        -Recommendation 'Disable USE_DES_KEY_ONLY flag and migrate to AES encryption'
                }
            }

            # AN-05: Kerberoastable users (all, not just admins)
            foreach ($user in $allUsers) {
                if ($user.ServicePrincipalName.Count -gt 0 -and $user.AdminCount -ne 1) {
                    $spns = ($user.ServicePrincipalName | Select-Object -First 3) -join ', '
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-05' `
                        -Check 'Kerberoastable User Account' -Severity 'Medium' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "User account with SPN: $spns. TGS ticket can be requested and cracked offline." `
                        -Recommendation 'Use gMSA for service accounts. If SPN is required, ensure a strong password (25+ chars).'
                }
            }

            # AN-06: Unconstrained Delegation (non-DC)
            foreach ($user in $allUsers) {
                if ($user.TrustedForDelegation -eq $true) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-06' `
                        -Check 'Unconstrained Delegation (User)' -Severity 'Critical' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail 'User account trusted for unconstrained delegation. Any TGT presented can be reused.' `
                        -Recommendation 'Switch to constrained delegation or RBCD. Never use unconstrained delegation.'
                }
            }

            foreach ($computer in $allComputers) {
                $computerShortName = $computer.Name.ToUpper()
                if ($computer.TrustedForDelegation -eq $true -and $computerShortName -notin $dcNames) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-06' `
                        -Check 'Unconstrained Delegation (Computer)' -Severity 'Critical' `
                        -SamAccountName $computer.SamAccountName -ObjectType 'Computer' `
                        -Detail "Non-DC computer trusted for unconstrained delegation: $($computer.Name)" `
                        -Recommendation 'Switch to constrained delegation or RBCD. Unconstrained delegation on non-DCs is a critical risk.'
                }
            }

            # AN-07: Constrained Delegation with Protocol Transition
            foreach ($user in $allUsers) {
                if ($user.TrustedToAuthForDelegation -eq $true) {
                    $targets = ($user.'msDS-AllowedToDelegateTo' | Select-Object -First 3) -join ', '
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-07' `
                        -Check 'Protocol Transition Delegation (User)' -Severity 'High' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "Constrained delegation with protocol transition. Targets: $targets" `
                        -Recommendation 'Review if protocol transition is necessary. Consider RBCD as safer alternative.'
                }
            }

            foreach ($computer in $allComputers) {
                if ($computer.TrustedToAuthForDelegation -eq $true) {
                    $targets = ($computer.'msDS-AllowedToDelegateTo' | Select-Object -First 3) -join ', '
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-07' `
                        -Check 'Protocol Transition Delegation (Computer)' -Severity 'High' `
                        -SamAccountName $computer.SamAccountName -ObjectType 'Computer' `
                        -Detail "Constrained delegation with protocol transition. Targets: $targets" `
                        -Recommendation 'Review if protocol transition is necessary. Consider RBCD as safer alternative.'
                }
            }

            # AN-08: SID History present
            foreach ($user in $allUsers) {
                if ($user.SIDHistory.Count -gt 0) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-08' `
                        -Check 'SID History Present' -Severity 'High' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "Account has $($user.SIDHistory.Count) SID(s) in SIDHistory. Potential privilege escalation vector." `
                        -Recommendation 'Remove SID History after migration is validated. Use: Set-ADUser -Remove @{SIDHistory=...}'
                }
            }

            # AN-09: Pre-Windows 2000 Compatible Access group
            try {
                $preWin2000 = @(Get-ADGroupMember -Identity 'Pre-Windows 2000 Compatible Access' -ErrorAction Stop @adSplat)
                foreach ($member in $preWin2000) {
                    if ($member.SamAccountName -in @('Authenticated Users', 'Everyone')) {
                        Add-Finding -Category 'Anomaly' -CheckId 'AN-09' `
                            -Check 'Pre-Windows 2000 Compatible Access' -Severity 'High' `
                            -SamAccountName $member.SamAccountName -ObjectType $member.objectClass `
                            -Detail "Dangerous principal '$($member.SamAccountName)' in Pre-Windows 2000 Compatible Access group allows anonymous enumeration" `
                            -Recommendation 'Remove Authenticated Users/Everyone from this group and reboot DCs'
                    }
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] AN-09 skipped: $_" }

            # AN-10: Password Never Expires (enabled, non-AdminCount accounts)
            foreach ($user in $allUsers) {
                if ($user.PasswordNeverExpires -and $user.AdminCount -ne 1) {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-10' `
                        -Check 'Password Never Expires' -Severity 'Medium' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail 'Password is set to never expire on a non-privileged account' `
                        -Recommendation 'Remove PasswordNeverExpires flag. Use FGPP if a longer expiry is needed.'
                }
            }

            # AN-11: Very old passwords (>365 days)
            foreach ($user in $allUsers) {
                if ($user.PasswordLastSet -and $user.PasswordLastSet -lt $now.AddDays(-365)) {
                    $age = [math]::Round(($now - $user.PasswordLastSet).TotalDays)
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-11' `
                        -Check 'Very Old Password' -Severity 'Medium' `
                        -SamAccountName $user.SamAccountName -ObjectType 'User' `
                        -Detail "Password is $age days old (>365 days). Risk of compromise through credential stuffing." `
                        -Recommendation 'Force a password change on this account'
                }
            }

            # AN-12: RBCD configured on computers
            foreach ($computer in $allComputers) {
                if ($null -ne $computer.'msDS-AllowedToActOnBehalfOfOtherIdentity') {
                    Add-Finding -Category 'Anomaly' -CheckId 'AN-12' `
                        -Check 'RBCD Configured' -Severity 'Informational' `
                        -SamAccountName $computer.SamAccountName -ObjectType 'Computer' `
                        -Detail "Resource-Based Constrained Delegation is configured on $($computer.Name)" `
                        -Recommendation 'Verify that RBCD configuration is intentional and properly scoped'
                }
            }
        }

        # ==================================================================
        # CATEGORY 3: CONFIGURATION
        # ==================================================================
        if ($runAll -or 'Configuration' -in $Category) {
            Write-Progress -Activity 'AD Security Audit' -Status 'Checking Configuration...' -PercentComplete 60

            # CF-01: KRBTGT password age
            try {
                $krbtgt = Get-ADUser -Identity 'krbtgt' -Properties 'PasswordLastSet' -ErrorAction Stop @adSplat
                if ($krbtgt.PasswordLastSet) {
                    $krbtgtAge = [math]::Round(($now - $krbtgt.PasswordLastSet).TotalDays)
                    if ($krbtgtAge -gt 180) {
                        Add-Finding -Category 'Configuration' -CheckId 'CF-01' `
                            -Check 'KRBTGT Password Age' -Severity 'High' `
                            -SamAccountName 'krbtgt' -ObjectType 'User' `
                            -Detail "KRBTGT password is $krbtgtAge days old. Should be rotated every 180 days maximum." `
                            -Recommendation 'Rotate KRBTGT password twice (with replication interval between resets)'
                    }
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] CF-01 skipped: $_" }

            # CF-02: LAPS deployment
            try {
                $lapsComputers = @($allComputers | Where-Object { $_.'ms-Mcs-AdmPwdExpirationTime' })
                $nonDCComputers = @($allComputers | Where-Object { $_.Name.ToUpper() -notin $dcNames })
                if ($nonDCComputers.Count -gt 0) {
                    $lapsCoverage = [math]::Round(($lapsComputers.Count / $nonDCComputers.Count) * 100)
                    if ($lapsCoverage -lt 80) {
                        $missing = $nonDCComputers.Count - $lapsComputers.Count
                        Add-Finding -Category 'Configuration' -CheckId 'CF-02' `
                            -Check 'LAPS Coverage Insufficient' -Severity 'High' `
                            -SamAccountName 'N/A' -ObjectType 'Configuration' `
                            -Detail "LAPS covers $lapsCoverage% of computers ($($lapsComputers.Count)/$($nonDCComputers.Count)). $missing computers unprotected." `
                            -Recommendation 'Deploy LAPS to all servers and workstations via GPO'
                    }
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] CF-02 skipped: $_" }

            # CF-03: Weak password policy
            try {
                $policy = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop @adSplat
                if ($policy.MinPasswordLength -lt 12) {
                    Add-Finding -Category 'Configuration' -CheckId 'CF-03' `
                        -Check 'Weak Password Policy' -Severity 'High' `
                        -SamAccountName 'N/A' -ObjectType 'Configuration' `
                        -Detail "Minimum password length is $($policy.MinPasswordLength) (recommended: 12+)" `
                        -Recommendation 'Increase minimum password length to at least 12 characters'
                }
                if (-not $policy.ComplexityEnabled) {
                    Add-Finding -Category 'Configuration' -CheckId 'CF-03' `
                        -Check 'Password Complexity Disabled' -Severity 'High' `
                        -SamAccountName 'N/A' -ObjectType 'Configuration' `
                        -Detail 'Password complexity requirements are disabled in Default Domain Policy' `
                        -Recommendation 'Enable password complexity or implement a custom password filter'
                }

                # CF-04: No lockout policy
                if ($policy.LockoutThreshold -eq 0) {
                    Add-Finding -Category 'Configuration' -CheckId 'CF-04' `
                        -Check 'No Account Lockout Policy' -Severity 'High' `
                        -SamAccountName 'N/A' -ObjectType 'Configuration' `
                        -Detail 'Account lockout threshold is 0 (disabled). Brute-force attacks are unrestricted.' `
                        -Recommendation 'Set lockout threshold to 5-10 attempts with 30-minute lockout duration'
                }

                # CF-05: No FGPP
                $fgppCount = @(Get-ADFineGrainedPasswordPolicy -Filter * -ErrorAction Stop @adSplat).Count
                if ($fgppCount -eq 0) {
                    Add-Finding -Category 'Configuration' -CheckId 'CF-05' `
                        -Check 'No Fine-Grained Password Policies' -Severity 'Medium' `
                        -SamAccountName 'N/A' -ObjectType 'Configuration' `
                        -Detail 'No FGPP configured. All accounts use the same password policy.' `
                        -Recommendation 'Create FGPP for privileged and service accounts with stricter requirements'
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] CF-03/04/05 skipped: $_" }

            # CF-06: Recycle Bin not enabled
            try {
                $recycleBin = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" -ErrorAction Stop @adSplat
                if (-not $recycleBin -or $recycleBin.EnabledScopes.Count -eq 0) {
                    Add-Finding -Category 'Configuration' -CheckId 'CF-06' `
                        -Check 'Recycle Bin Not Enabled' -Severity 'Medium' `
                        -SamAccountName 'N/A' -ObjectType 'Configuration' `
                        -Detail 'AD Recycle Bin is not enabled. Deleted objects cannot be easily recovered.' `
                        -Recommendation 'Enable-ADOptionalFeature "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target $forest'
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] CF-06 skipped: $_" }

            # CF-07: Domain functional level outdated
            if ($domain) {
                $domainLevel = $domain.DomainMode.ToString()
                if ($domainLevel -match '2008|2003|2000|2012') {
                    Add-Finding -Category 'Configuration' -CheckId 'CF-07' `
                        -Check 'Domain Functional Level Outdated' -Severity 'Medium' `
                        -SamAccountName 'N/A' -ObjectType 'Configuration' `
                        -Detail "Domain functional level is '$domainLevel'. Modern security features require 2016+." `
                        -Recommendation 'Raise domain functional level after ensuring all DCs are on a supported OS'
                }
            }

            # CF-08: Forest functional level outdated
            if ($forest) {
                $forestLevel = $forest.ForestMode.ToString()
                if ($forestLevel -match '2008|2003|2000|2012') {
                    Add-Finding -Category 'Configuration' -CheckId 'CF-08' `
                        -Check 'Forest Functional Level Outdated' -Severity 'Medium' `
                        -SamAccountName 'N/A' -ObjectType 'Configuration' `
                        -Detail "Forest functional level is '$forestLevel'. Modern security features require 2016+." `
                        -Recommendation 'Raise forest functional level after raising all domain functional levels'
                }
            }

            # CF-09: Trust SID Filtering disabled
            try {
                $trusts = @(Get-ADTrust -Filter * -Properties 'SIDFilteringQuarantined', 'SIDFilteringForestAware' -ErrorAction Stop @adSplat)
                foreach ($trust in $trusts) {
                    if ($trust.SIDFilteringQuarantined -eq $false) {
                        Add-Finding -Category 'Configuration' -CheckId 'CF-09' `
                            -Check 'Trust SID Filtering Disabled' -Severity 'High' `
                            -SamAccountName $trust.Name -ObjectType 'Trust' `
                            -Detail "SID Filtering is disabled on trust '$($trust.Name)'. SID History across trust boundary is allowed." `
                            -Recommendation 'Enable SID Filtering: netdom trust /domain:<trusted> /quarantine:yes'
                    }
                }
            }
            catch { Write-Verbose -Message "[$($MyInvocation.MyCommand)] CF-09 skipped: $_" }
        }

        # ==================================================================
        # CATEGORY 4: STALE OBJECTS
        # ==================================================================
        if ($runAll -or 'StaleObjects' -in $Category) {
            Write-Progress -Activity 'AD Security Audit' -Status 'Checking Stale Objects...' -PercentComplete 80

            # SO-01: Obsolete OS computers
            $obsoletePatterns = @(
                @{ Pattern = '2003'; Severity = 'Critical' }
                @{ Pattern = '2008'; Severity = 'Critical' }
                @{ Pattern = 'Windows XP'; Severity = 'Critical' }
                @{ Pattern = 'Windows Vista'; Severity = 'Critical' }
                @{ Pattern = 'Windows 7 '; Severity = 'High' }
                @{ Pattern = '2012'; Severity = 'High' }
            )

            foreach ($computer in $allComputers) {
                if (-not $computer.OperatingSystem) { continue }
                foreach ($osCheck in $obsoletePatterns) {
                    if ($computer.OperatingSystem -match $osCheck.Pattern) {
                        Add-Finding -Category 'StaleObjects' -CheckId 'SO-01' `
                            -Check 'Obsolete Operating System' -Severity $osCheck.Severity `
                            -SamAccountName $computer.SamAccountName -ObjectType 'Computer' `
                            -Detail "Running $($computer.OperatingSystem) — end of support" `
                            -Recommendation 'Migrate to a supported OS or decommission this system'
                        break
                    }
                }
            }

            # SO-02: DCs on outdated OS
            foreach ($dc in $domainControllers) {
                if ($dc.OperatingSystem -and $dc.OperatingSystem -match '2008|2003|2012') {
                    Add-Finding -Category 'StaleObjects' -CheckId 'SO-02' `
                        -Check 'Domain Controller on Outdated OS' -Severity 'Critical' `
                        -SamAccountName $dc.HostName -ObjectType 'DomainController' `
                        -Detail "DC running $($dc.OperatingSystem)" `
                        -Recommendation 'Migrate DC to Windows Server 2019 or later urgently'
                }
            }

            # SO-03: Stale user accounts
            $staleUsers = @($allUsers | Where-Object {
                $null -eq $_.LastLogonDate -or $_.LastLogonDate -lt $cutoffDate
            })
            if ($staleUsers.Count -gt 0) {
                Add-Finding -Category 'StaleObjects' -CheckId 'SO-03' `
                    -Check 'Stale User Accounts' -Severity 'Medium' `
                    -SamAccountName "($($staleUsers.Count) accounts)" -ObjectType 'User' `
                    -Detail "$($staleUsers.Count) enabled user accounts have not logged in for over $StaleThresholdDays days" `
                    -Recommendation "Review with: Get-ADStaleAccount -DaysInactive $StaleThresholdDays -AccountType User"
            }

            # SO-04: Stale computer accounts
            $staleComputers = @($allComputers | Where-Object {
                $null -eq $_.LastLogonDate -or $_.LastLogonDate -lt $cutoffDate
            })
            if ($staleComputers.Count -gt 0) {
                Add-Finding -Category 'StaleObjects' -CheckId 'SO-04' `
                    -Check 'Stale Computer Accounts' -Severity 'Medium' `
                    -SamAccountName "($($staleComputers.Count) accounts)" -ObjectType 'Computer' `
                    -Detail "$($staleComputers.Count) enabled computer accounts have not logged in for over $StaleThresholdDays days" `
                    -Recommendation "Review with: Get-ADStaleComputer -DaysInactive $StaleThresholdDays"
            }
        }

        # ==================================================================
        # OUTPUT
        # ==================================================================
        Write-Progress -Activity 'AD Security Audit' -Completed

        $severityOrder = @{ 'Critical' = 1; 'High' = 2; 'Medium' = 3; 'Informational' = 4 }

        $findings | Sort-Object -Property @(
            @{ Expression = { $severityOrder[$_.Severity] } }
            @{ Expression = 'Category' }
            @{ Expression = 'CheckId' }
            @{ Expression = 'SamAccountName' }
        )

        # Summary via Write-Information (capturable with 6> or -InformationAction)
        $criticalCount = @($findings | Where-Object Severity -eq 'Critical').Count
        $highCount = @($findings | Where-Object Severity -eq 'High').Count
        $mediumCount = @($findings | Where-Object Severity -eq 'Medium').Count
        $infoCount = @($findings | Where-Object Severity -eq 'Informational').Count

        $summary = [System.Text.StringBuilder]::new()
        [void]$summary.AppendLine('')
        [void]$summary.AppendLine('  AD Security Audit Summary')
        [void]$summary.AppendLine('  ========================')
        [void]$summary.AppendLine("  Total findings : $($findings.Count)")
        if ($criticalCount -gt 0) { [void]$summary.AppendLine("  Critical       : $criticalCount") }
        if ($highCount -gt 0) { [void]$summary.AppendLine("  High           : $highCount") }
        if ($mediumCount -gt 0) { [void]$summary.AppendLine("  Medium         : $mediumCount") }
        if ($infoCount -gt 0) { [void]$summary.AppendLine("  Informational  : $infoCount") }
        Write-Information -MessageData $summary.ToString() -InformationAction Continue
    }
}
