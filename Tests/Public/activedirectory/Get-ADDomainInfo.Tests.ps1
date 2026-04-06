#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent

    # Stubs with parameters so Pester ParameterFilter can bind $Filter, $Identity, etc.
    $adStubs = @{
        'Get-ADDomain'                      = { param($Server, $Credential) }
        'Get-ADForest'                      = { param($Server, $Credential) }
        'Get-ADDomainController'            = { param($Filter, $Server, $Credential) }
        'Get-ADUser'                        = { param($Filter, $Identity, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
        'Get-ADComputer'                    = { param($Filter, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
        'Get-ADGroup'                       = { param($Filter, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
        'Get-ADOrganizationalUnit'          = { param($Filter, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
        'Get-ADDefaultDomainPasswordPolicy' = { param($Server, $Credential) }
        'Get-ADFineGrainedPasswordPolicy'   = { param($Filter, $Server, $Credential) }
        'Get-ADOptionalFeature'             = { param($Filter, $Server, $Credential) }
    }
    foreach ($cmdlet in $adStubs.Keys) {
        if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
            New-Item -Path "function:global:$cmdlet" -Value $adStubs[$cmdlet] -Force | Out-Null
        }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        $adStubs = @{
            'Get-ADDomain'                      = { param($Server, $Credential) }
            'Get-ADForest'                      = { param($Server, $Credential) }
            'Get-ADDomainController'            = { param($Filter, $Server, $Credential) }
            'Get-ADUser'                        = { param($Filter, $Identity, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
            'Get-ADComputer'                    = { param($Filter, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
            'Get-ADGroup'                       = { param($Filter, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
            'Get-ADOrganizationalUnit'          = { param($Filter, $Properties, $SearchBase, $Server, $Credential, $ErrorAction) }
            'Get-ADDefaultDomainPasswordPolicy' = { param($Server, $Credential) }
            'Get-ADFineGrainedPasswordPolicy'   = { param($Filter, $Server, $Credential) }
            'Get-ADOptionalFeature'             = { param($Filter, $Server, $Credential) }
        }
        foreach ($cmdlet in $adStubs.Keys) {
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

Describe -Name 'Get-ADDomainInfo' -Fixture {

    BeforeAll {
        Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }

        $script:mockDomain = [PSCustomObject]@{
            DNSRoot              = 'contoso.com'
            NetBIOSName          = 'CONTOSO'
            DistinguishedName    = 'DC=contoso,DC=com'
            DomainMode           = 'Windows2016Domain'
            PDCEmulator          = 'DC01.contoso.com'
            RIDMaster            = 'DC01.contoso.com'
            InfrastructureMaster = 'DC01.contoso.com'
        }

        $script:mockForest = [PSCustomObject]@{
            Name               = 'contoso.com'
            ForestMode         = 'Windows2016Forest'
            SchemaMaster       = 'DC01.contoso.com'
            DomainNamingMaster = 'DC01.contoso.com'
        }

        $script:mockDCs = @(
            [PSCustomObject]@{
                HostName        = 'DC01.contoso.com'
                Site            = 'Paris'
                IPv4Address     = '10.0.0.10'
                IsGlobalCatalog = $true
                IsReadOnly      = $false
                OperatingSystem = 'Windows Server 2022 Datacenter'
            }
            [PSCustomObject]@{
                HostName        = 'DC02.contoso.com'
                Site            = 'Lyon'
                IPv4Address     = '10.0.1.10'
                IsGlobalCatalog = $true
                IsReadOnly      = $false
                OperatingSystem = 'Windows Server 2022 Datacenter'
            }
        )

        $script:mockPasswordPolicy = [PSCustomObject]@{
            MinPasswordLength            = 12
            MaxPasswordAge               = [TimeSpan]::FromDays(90)
            MinPasswordAge               = [TimeSpan]::FromDays(1)
            PasswordHistoryCount         = 24
            ComplexityEnabled            = $true
            ReversibleEncryptionEnabled  = $false
            LockoutThreshold             = 5
            LockoutDuration              = [TimeSpan]::FromMinutes(30)
            LockoutObservationWindow     = [TimeSpan]::FromMinutes(30)
        }

        $script:mockFGPP = @(
            [PSCustomObject]@{ Name = 'SvcAccounts-PSO' }
            [PSCustomObject]@{ Name = 'Admins-PSO' }
        )

        $script:mockRecycleBin = [PSCustomObject]@{
            Name          = 'Recycle Bin Feature'
            EnabledScopes = @('CN=Partitions,CN=Configuration,DC=contoso,DC=com')
        }

        Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomain }
        Mock -CommandName 'Get-ADForest' -ModuleName 'PSWinOps' -MockWith { return $script:mockForest }
        Mock -CommandName 'Get-ADDomainController' -ModuleName 'PSWinOps' -MockWith { return $script:mockDCs }
        Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith { return @(1..150) }
        Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith { return @(1..50) }
        Mock -CommandName 'Get-ADGroup' -ModuleName 'PSWinOps' -MockWith { return @(1..80) }
        Mock -CommandName 'Get-ADOrganizationalUnit' -ModuleName 'PSWinOps' -MockWith { return @(1..25) }
        Mock -CommandName 'Get-ADDefaultDomainPasswordPolicy' -ModuleName 'PSWinOps' -MockWith { return $script:mockPasswordPolicy }
        Mock -CommandName 'Get-ADFineGrainedPasswordPolicy' -ModuleName 'PSWinOps' -MockWith { return $script:mockFGPP }
        Mock -CommandName 'Get-ADOptionalFeature' -ModuleName 'PSWinOps' -MockWith { return $script:mockRecycleBin }
    }

    Context -Name 'Happy path' -Fixture {

        BeforeAll {
            $script:result = Get-ADDomainInfo
        }

        It -Name 'Should return a single object' -Test {
            @($script:result).Count | Should -Be 1
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ADDomainInfo'
        }
    }

    Context -Name 'Domain identity' -Fixture {

        BeforeAll {
            $script:result = Get-ADDomainInfo
        }

        It -Name 'Should return domain DNS name' -Test {
            $script:result.DomainName | Should -Be 'contoso.com'
        }

        It -Name 'Should return NetBIOS name' -Test {
            $script:result.NetBIOSName | Should -Be 'CONTOSO'
        }

        It -Name 'Should return functional levels' -Test {
            $script:result.DomainFunctionalLevel | Should -Be 'Windows2016Domain'
            $script:result.ForestFunctionalLevel | Should -Be 'Windows2016Forest'
        }
    }

    Context -Name 'FSMO role holders' -Fixture {

        BeforeAll {
            $script:result = Get-ADDomainInfo
        }

        It -Name 'Should return all 5 FSMO roles' -Test {
            $script:result.PDCEmulator | Should -Be 'DC01.contoso.com'
            $script:result.RIDMaster | Should -Be 'DC01.contoso.com'
            $script:result.InfrastructureMaster | Should -Be 'DC01.contoso.com'
            $script:result.SchemaMaster | Should -Be 'DC01.contoso.com'
            $script:result.DomainNamingMaster | Should -Be 'DC01.contoso.com'
        }
    }

    Context -Name 'Domain controller inventory' -Fixture {

        BeforeAll {
            $script:result = Get-ADDomainInfo
        }

        It -Name 'Should return DC count' -Test {
            $script:result.DomainControllerCount | Should -Be 2
        }

        It -Name 'Should return DC list with details' -Test {
            $script:result.DomainControllers | Should -HaveCount 2
            $script:result.DomainControllers[0].HostName | Should -Be 'DC01.contoso.com'
        }

        It -Name 'Should return comma-separated sites' -Test {
            $script:result.Sites | Should -Match 'Lyon'
            $script:result.Sites | Should -Match 'Paris'
        }
    }

    Context -Name 'Object counts' -Fixture {

        BeforeAll {
            # Override mocks with specific counts
            # Filter strings are: "Enabled -eq $true" and "Enabled -eq $false"
            # Match on '\$true' vs '\$false' to avoid overlap
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @(1..100)
            } -ParameterFilter { $Filter -match '\$true' }
            Mock -CommandName 'Get-ADUser' -ModuleName 'PSWinOps' -MockWith {
                return @(1..20)
            } -ParameterFilter { $Filter -match '\$false' }
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @(1..40)
            } -ParameterFilter { $Filter -match '\$true' }
            Mock -CommandName 'Get-ADComputer' -ModuleName 'PSWinOps' -MockWith {
                return @(1..5)
            } -ParameterFilter { $Filter -match '\$false' }

            $script:result = Get-ADDomainInfo
        }

        It -Name 'Should count enabled and disabled users separately' -Test {
            $script:result.EnabledUsers | Should -Be 100
            $script:result.DisabledUsers | Should -Be 20
            $script:result.TotalUsers | Should -Be 120
        }

        It -Name 'Should count enabled and disabled computers separately' -Test {
            $script:result.EnabledComputers | Should -Be 40
            $script:result.DisabledComputers | Should -Be 5
            $script:result.TotalComputers | Should -Be 45
        }

        It -Name 'Should count groups' -Test {
            $script:result.GroupCount | Should -Be 80
        }

        It -Name 'Should count OUs' -Test {
            $script:result.OUCount | Should -Be 25
        }
    }

    Context -Name 'Password policy' -Fixture {

        BeforeAll {
            $script:result = Get-ADDomainInfo
        }

        It -Name 'Should return min password length' -Test {
            $script:result.MinPasswordLength | Should -Be 12
        }

        It -Name 'Should return max password age in days' -Test {
            $script:result.MaxPasswordAgeDays | Should -Be 90
        }

        It -Name 'Should return lockout threshold' -Test {
            $script:result.LockoutThreshold | Should -Be 5
        }

        It -Name 'Should return FGPP count' -Test {
            $script:result.FineGrainedPolicyCount | Should -Be 2
        }
    }

    Context -Name 'Optional features' -Fixture {

        BeforeAll {
            $script:result = Get-ADDomainInfo
        }

        It -Name 'Should detect Recycle Bin as enabled' -Test {
            $script:result.RecycleBinEnabled | Should -BeTrue
        }
    }

    Context -Name 'Server parameter' -Fixture {

        It -Name 'Should accept Server parameter' -Test {
            { Get-ADDomainInfo -Server 'dc01.contoso.com' } | Should -Not -Throw
        }
    }

    Context -Name 'Error handling' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith {
                throw 'Cannot contact domain'
            }
        }

        It -Name 'Should not throw on failure' -Test {
            { Get-ADDomainInfo -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context -Name 'Output shape' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-ADDomain' -ModuleName 'PSWinOps' -MockWith { return $script:mockDomain }
            $script:result = Get-ADDomainInfo
            $script:propertyNames = $script:result.PSObject.Properties.Name
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProps = @(
                'DomainName', 'NetBIOSName', 'DistinguishedName',
                'DomainFunctionalLevel', 'ForestFunctionalLevel', 'ForestName',
                'PDCEmulator', 'RIDMaster', 'InfrastructureMaster',
                'SchemaMaster', 'DomainNamingMaster',
                'DomainControllerCount', 'DomainControllers', 'Sites',
                'EnabledUsers', 'DisabledUsers', 'TotalUsers',
                'EnabledComputers', 'DisabledComputers', 'TotalComputers',
                'GroupCount', 'OUCount',
                'MinPasswordLength', 'MaxPasswordAgeDays', 'PasswordHistoryCount',
                'ComplexityEnabled', 'LockoutThreshold', 'FineGrainedPolicyCount',
                'RecycleBinEnabled', 'Timestamp'
            )
            foreach ($prop in $expectedProps) {
                $script:propertyNames | Should -Contain $prop
            }
        }

        It -Name 'Should have ISO 8601 Timestamp' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }
}
