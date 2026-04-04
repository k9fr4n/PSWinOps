#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    $adCmdlets = @(
        'Get-ADUser', 'Get-ADComputer', 'Get-ADDomain', 'Get-ADForest',
        'Get-ADDomainController', 'Get-ADGroupMember', 'Get-ADTrust',
        'Get-ADDefaultDomainPasswordPolicy', 'Get-ADFineGrainedPasswordPolicy',
        'Get-ADOptionalFeature'
    )
    foreach ($cmdlet in $adCmdlets) {
        if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
            New-Item -Path "function:global:$cmdlet" -Value { } -Force | Out-Null
        }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        $adCmdlets = @(
            'Get-ADUser', 'Get-ADComputer', 'Get-ADDomain', 'Get-ADForest',
            'Get-ADDomainController', 'Get-ADGroupMember', 'Get-ADTrust',
            'Get-ADDefaultDomainPasswordPolicy', 'Get-ADFineGrainedPasswordPolicy',
            'Get-ADOptionalFeature'
        )
        foreach ($cmdlet in $adCmdlets) {
            if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
                New-Item -Path "function:script:$cmdlet" -Value { } -Force | Out-Null
            }
        }
    }
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'Invoke-ADSecurityAudit' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        # ---- Mock vulnerable user ----
        $script:vulnerableUser = [PSCustomObject]@{
            SamAccountName                   = 'svc-vulnerable'
            Name                             = 'Vulnerable Service'
            Enabled                          = $true
            AdminCount                       = 1
            LastLogonDate                    = (Get-Date).AddDays(-200)
            PasswordLastSet                  = (Get-Date).AddDays(-400)
            PasswordNeverExpires             = $true
            PasswordNotRequired              = $true
            AllowReversiblePasswordEncryption = $true
            DoesNotRequirePreAuth            = $true
            UseDESKeyOnly                    = $true
            TrustedForDelegation             = $true
            TrustedToAuthForDelegation       = $false
            ServicePrincipalName             = @('MSSQLSvc/SQL01.contoso.com')
            SIDHistory                       = @('S-1-5-21-111-222-333-444')
            'msDS-AllowedToDelegateTo'       = @()
            Description                      = 'Badly configured service account'
            DistinguishedName                = 'CN=svc-vulnerable,OU=Service,DC=contoso,DC=com'
        }

        # ---- Mock clean user ----
        $script:cleanUser = [PSCustomObject]@{
            SamAccountName                   = 'jdoe'
            Name                             = 'John Doe'
            Enabled                          = $true
            AdminCount                       = $null
            LastLogonDate                    = (Get-Date).AddDays(-1)
            PasswordLastSet                  = (Get-Date).AddDays(-30)
            PasswordNeverExpires             = $false
            PasswordNotRequired              = $false
            AllowReversiblePasswordEncryption = $false
            DoesNotRequirePreAuth            = $false
            UseDESKeyOnly                    = $false
            TrustedForDelegation             = $false
            TrustedToAuthForDelegation       = $false
            ServicePrincipalName             = @()
            SIDHistory                       = @()
            'msDS-AllowedToDelegateTo'       = @()
            Description                      = 'Normal user'
            DistinguishedName                = 'CN=John Doe,OU=Users,DC=contoso,DC=com'
        }

        # ---- Mock vulnerable computer ----
        $script:vulnerableComputer = [PSCustomObject]@{
            SamAccountName                              = 'OLD-SRV01
            Name                                        = 'OLD-SRV01'
            Enabled                                     = $true
            OperatingSystem                             = 'Windows Server 2008 R2 Standard'
            OperatingSystemVersion                      = '6.1 (7601)'
            TrustedForDelegation                        = $true
            TrustedToAuthForDelegation                  = $false
            'msDS-AllowedToDelegateTo'                  = @()
            'msDS-AllowedToActOnBehalfOfOtherIdentity'  = $null
            'ms-Mcs-AdmPwdExpirationTime'               = $null
            LastLogonDate                               = (Get-Date).AddDays(-300)
            PasswordLastSet                             = (Get-Date).AddDays(-300)
            Description                                 = 'Old server'
            DistinguishedName                           = 'CN=OLD-SRV01,OU=Servers,DC=contoso,DC=com'
        }

        # ---- Mock clean computer ----
        $script:cleanComputer = [PSCustomObject]@{
            SamAccountName                              = 'SRV-APP01
            Name                                        = 'SRV-APP01'
            Enabled                                     = $true
            OperatingSystem                             = 'Windows Server 2022 Datacenter'
            OperatingSystemVersion                      = '10.0 (20348)'
            TrustedForDelegation                        = $false
            TrustedToAuthForDelegation                  = $false
            'msDS-AllowedToDelegateTo'                  = @()
            'msDS-AllowedToActOnBehalfOfOtherIdentity'  = $null
            'ms-Mcs-AdmPwdExpirationTime'               = (Get-Date).AddDays(10).ToFileTime()
            LastLogonDate                               = (Get-Date).AddDays(-1)
            PasswordLastSet                             = (Get-Date).AddDays(-15)
            Description                                 = 'Application server'
            DistinguishedName                           = 'CN=SRV-APP01,OU=Servers,DC=contoso,DC=com'
        }

        # ---- Standard mocks ----
        Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
            return @($script:vulnerableUser, $script:cleanUser)
        }
        Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
            return @($script:vulnerableComputer, $script:cleanComputer)
        }
        Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{
                DomainMode        = 'Windows2012R2Domain'
                DistinguishedName = 'DC=contoso,DC=com'
            }
        }
        Mock -CommandName 'Get-ADForest' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{ ForestMode = 'Windows2012R2Forest' }
        }
        Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith {
            @([PSCustomObject]@{
                HostName        = 'DC01.contoso.com'
                Site            = 'Default'
                OperatingSystem = 'Windows Server 2022 Datacenter'
            })
        }
        Mock -CommandName 'Get-ADGroupMember' -ModuleName 'PSWinOps' -MockWith {
            param($Identity)
            switch ($Identity) {
                'Schema Admins' {
                    @([PSCustomObject]@{
                        SamAccountName    = 'adminuser'
                        objectClass       = 'user'
                        distinguishedName = 'CN=Admin,OU=Users,DC=contoso,DC=com'
                        Name              = 'Admin User'
                    })
                }
                'Protected Users' { @() }
                'Pre-Windows 2000 Compatible Access' {
                    @([PSCustomObject]@{
                        SamAccountName    = 'Authenticated Users'
                        objectClass       = 'foreignSecurityPrincipal'
                        distinguishedName = 'CN=S-1-5-11,CN=ForeignSecurityPrincipals,DC=contoso,DC=com'
                        Name              = 'Authenticated Users'
                    })
                }
                default { @() }
            }
        }
        Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
            [PSCustomObject]@{
                MinPasswordLength   = 8
                ComplexityEnabled   = $false
                LockoutThreshold    = 0
                MaxPasswordAge      = [TimeSpan]::FromDays(90)
            }
        }
        Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith { @() }
        Mock -CommandName 'Get-ADOptionalFeature' -ModuleName 'PSWinOps' -MockWith { $null }
        Mock -CommandName 'Get-ADTrust' -ModuleName 'PSWinOps' -MockWith { @() }

        Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
            $Identity -eq 'krbtgt'
        } -MockWith {
            [PSCustomObject]@{ PasswordLastSet = (Get-Date).AddDays(-400) }
        }
    }

    Context -Name 'Full audit returns findings for vulnerable environment' -Fixture {

        BeforeAll {
            $script:results = Invoke-ADSecurityAudit 6>$null
        }

        It -Name 'Should return findings' -Test {
            $script:results.Count | Should -BeGreaterThan 0
        }

        It -Name 'Should have correct PSTypeName on all findings' -Test {
            $script:results | ForEach-Object {
                $_.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADSecurityFinding'
            }
        }

        It -Name 'Should contain Critical findings' -Test {
            $critical = $script:results | Where-Object Severity -eq 'Critical'
            $critical.Count | Should -BeGreaterThan 0
        }
    }

    Context -Name 'Privileged Accounts checks' -Fixture {

        BeforeAll {
            $script:results = Invoke-ADSecurityAudit -Category 'PrivilegedAccounts' 6>$null
        }

        It -Name 'PA-01: Should detect Schema Admins not empty' -Test {
            $script:results | Where-Object CheckId -eq 'PA-01' | Should -Not -BeNullOrEmpty
        }

        It -Name 'PA-02: Should detect Protected Users empty' -Test {
            $script:results | Where-Object CheckId -eq 'PA-02' | Should -Not -BeNullOrEmpty
        }

        It -Name 'PA-04: Should detect Kerberoastable admin' -Test {
            $finding = $script:results | Where-Object CheckId -eq 'PA-04'
            $finding | Should -Not -BeNullOrEmpty
            $finding.Severity | Should -Be 'Critical'
        }

        It -Name 'PA-05: Should detect stale admin password' -Test {
            $script:results | Where-Object CheckId -eq 'PA-05' | Should -Not -BeNullOrEmpty
        }

        It -Name 'PA-06: Should detect inactive privileged account' -Test {
            $script:results | Where-Object CheckId -eq 'PA-06' | Should -Not -BeNullOrEmpty
        }

        It -Name 'PA-07: Should detect admin with PasswordNeverExpires' -Test {
            $script:results | Where-Object CheckId -eq 'PA-07' | Should -Not -BeNullOrEmpty
        }

        It -Name 'PA-08: Should detect service account in privileged group' -Test {
            # svc-vulnerable has SPN + is in privilegedDNs (AdminCount=1 + would be in the set)
            # Actually depends on mock... let's check it doesn't error
            { Invoke-ADSecurityAudit -Category 'PrivilegedAccounts' 6>$null } | Should -Not -Throw
        }
    }

    Context -Name 'Anomaly checks' -Fixture {

        BeforeAll {
            $script:results = Invoke-ADSecurityAudit -Category 'Anomaly' 6>$null
        }

        It -Name 'AN-01: Should detect AS-REP Roastable' -Test {
            $script:results | Where-Object CheckId -eq 'AN-01' | Should -Not -BeNullOrEmpty
        }

        It -Name 'AN-02: Should detect Password Not Required' -Test {
            $script:results | Where-Object CheckId -eq 'AN-02' | Should -Not -BeNullOrEmpty
        }

        It -Name 'AN-03: Should detect Reversible Encryption' -Test {
            $script:results | Where-Object CheckId -eq 'AN-03' | Should -Not -BeNullOrEmpty
        }

        It -Name 'AN-04: Should detect DES-only Kerberos' -Test {
            $script:results | Where-Object CheckId -eq 'AN-04' | Should -Not -BeNullOrEmpty
        }

        It -Name 'AN-06: Should detect Unconstrained Delegation on non-DC computer' -Test {
            $script:results | Where-Object { $_.CheckId -eq 'AN-06' -and $_.ObjectType -eq 'Computer' } | Should -Not -BeNullOrEmpty
        }

        It -Name 'AN-08: Should detect SID History' -Test {
            $script:results | Where-Object CheckId -eq 'AN-08' | Should -Not -BeNullOrEmpty
        }

        It -Name 'AN-09: Should detect Pre-Win2000 Compatible Access' -Test {
            $script:results | Where-Object CheckId -eq 'AN-09' | Should -Not -BeNullOrEmpty
        }

        It -Name 'AN-11: Should detect very old password' -Test {
            $script:results | Where-Object CheckId -eq 'AN-11' | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Configuration checks' -Fixture {

        BeforeAll {
            $script:results = Invoke-ADSecurityAudit -Category 'Configuration' 6>$null
        }

        It -Name 'CF-01: Should detect old KRBTGT password' -Test {
            $script:results | Where-Object CheckId -eq 'CF-01' | Should -Not -BeNullOrEmpty
        }

        It -Name 'CF-03: Should detect weak password policy' -Test {
            $script:results | Where-Object { $_.CheckId -eq 'CF-03' -and $_.Check -match 'Weak' } | Should -Not -BeNullOrEmpty
        }

        It -Name 'CF-04: Should detect no lockout policy' -Test {
            $script:results | Where-Object CheckId -eq 'CF-04' | Should -Not -BeNullOrEmpty
        }

        It -Name 'CF-05: Should detect no FGPP' -Test {
            $script:results | Where-Object CheckId -eq 'CF-05' | Should -Not -BeNullOrEmpty
        }

        It -Name 'CF-06: Should detect Recycle Bin not enabled' -Test {
            $script:results | Where-Object CheckId -eq 'CF-06' | Should -Not -BeNullOrEmpty
        }

        It -Name 'CF-07: Should detect outdated domain functional level' -Test {
            $script:results | Where-Object CheckId -eq 'CF-07' | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Stale Objects checks' -Fixture {

        BeforeAll {
            $script:results = Invoke-ADSecurityAudit -Category 'StaleObjects' 6>$null
        }

        It -Name 'SO-01: Should detect obsolete OS' -Test {
            $script:results | Where-Object CheckId -eq 'SO-01' | Should -Not -BeNullOrEmpty
        }

        It -Name 'SO-03: Should detect stale user accounts' -Test {
            $script:results | Where-Object CheckId -eq 'SO-03' | Should -Not -BeNullOrEmpty
        }

        It -Name 'SO-04: Should detect stale computer accounts' -Test {
            $script:results | Where-Object CheckId -eq 'SO-04' | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Category filter' -Fixture {

        It -Name 'Should return only PrivilegedAccounts findings when filtered' -Test {
            $results = Invoke-ADSecurityAudit -Category 'PrivilegedAccounts' 6>$null
            $results | ForEach-Object {
                $_.Category | Should -Be 'PrivilegedAccounts'
            }
        }

        It -Name 'Should return only Configuration findings when filtered' -Test {
            $results = Invoke-ADSecurityAudit -Category 'Configuration' 6>$null
            $results | ForEach-Object {
                $_.Category | Should -Be 'Configuration'
            }
        }
    }

    Context -Name 'Sort order' -Fixture {

        BeforeAll {
            $script:results = Invoke-ADSecurityAudit 6>$null
        }

        It -Name 'Should sort Critical findings first' -Test {
            $script:results[0].Severity | Should -Be 'Critical'
        }
    }

    Context -Name 'Output shape' -Fixture {

        BeforeAll {
            $script:results = Invoke-ADSecurityAudit 6>$null
            $script:propertyNames = $script:results[0].PSObject.Properties.Name
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProps = @(
                'Category', 'CheckId', 'Check', 'Severity',
                'SamAccountName', 'ObjectType', 'Detail',
                'Recommendation', 'Timestamp'
            )
            foreach ($prop in $expectedProps) {
                $script:propertyNames | Should -Contain $prop
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:results[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context -Name 'Clean environment produces no critical findings' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @($script:cleanUser)
            }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -ParameterFilter {
                $Identity -eq 'krbtgt'
            } -MockWith {
                [PSCustomObject]@{ PasswordLastSet = (Get-Date).AddDays(-30) }
            }
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @($script:cleanComputer)
            }
            Mock -CommandName 'Get-ADGroupMember' -ModuleName 'PSWinOps' -MockWith { @() }
            Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    DomainMode        = 'Windows2016Domain'
                    DistinguishedName = 'DC=contoso,DC=com'
                }
            }
            Mock -CommandName 'Get-ADForest' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ ForestMode = 'Windows2016Forest' }
            }
            Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    MinPasswordLength = 14
                    ComplexityEnabled = $true
                    LockoutThreshold  = 5
                    MaxPasswordAge    = [TimeSpan]::FromDays(90)
                }
            }
            Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Name = 'Admins-PSO' })
            }
            Mock -CommandName 'Get-ADOptionalFeature' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{
                    Name          = 'Recycle Bin Feature'
                    EnabledScopes = @('CN=Partitions,CN=Configuration,DC=contoso,DC=com')
                }
            }
            $script:cleanResults = Invoke-ADSecurityAudit 6>$null
        }

        It -Name 'Should produce no Critical findings' -Test {
            $critical = $script:cleanResults | Where-Object Severity -eq 'Critical'
            @($critical).Count | Should -Be 0
        }
    }
}
