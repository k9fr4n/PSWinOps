#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockMetadata = [PSCustomObject]@{
        ConfiguredSource = 'WSUS'
        ConfiguredUrl    = 'https://wsus.corp.local:8531'
        TargetGroup      = 'Servers-Prod'
        EffectiveSource  = 'WSUS'
        TotalCount       = 4
    }

    $script:mockMetadataSingle = [PSCustomObject]@{
        ConfiguredSource = 'WSUS'
        ConfiguredUrl    = 'https://wsus.corp.local:8531'
        TargetGroup      = 'Servers-Prod'
        EffectiveSource  = 'WSUS'
        TotalCount       = 1
    }

    $script:mockUpdates = @(
        [PSCustomObject]@{
            Title           = '2026-03 Cumulative Update for Windows Server 2022 (KB5034441)'
            KBArticle       = 'KB5034441'
            KBArticleIDs    = @('5034441')
            Classification  = 'Security Updates'
            Products        = @('Windows Server 2022', 'Microsoft Server Operating System-24H2')
            Description     = 'A cumulative security update for Windows Server 2022'
            ReleaseNotes    = 'https://support.microsoft.com/kb/5034441'
            MsrcSeverity    = 'Critical'
            CveIDs          = @('CVE-2026-1234', 'CVE-2026-5678')
            IsDownloaded    = $false
            IsHidden        = $false
            IsInstalled     = $false
            IsMandatory     = $true
            IsUninstallable = $true
            EulaAccepted    = $true
            Deadline        = [datetime]'2026-04-15'
            RebootRequired  = $true
            MaxSizeBytes    = 47316992
            UpdateId        = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
            RevisionNumber  = 201
        },
        [PSCustomObject]@{
            Title           = '2026-03 Security Update for .NET Framework (KB5035432)'
            KBArticle       = 'KB5035432'
            KBArticleIDs    = @('5035432')
            Classification  = 'Critical Updates'
            Products        = @('Windows Server 2022')
            Description     = 'A critical security update for .NET Framework'
            ReleaseNotes    = ''
            MsrcSeverity    = 'Important'
            CveIDs          = @('CVE-2026-9012')
            IsDownloaded    = $true
            IsHidden        = $false
            IsInstalled     = $false
            IsMandatory     = $false
            IsUninstallable = $false
            EulaAccepted    = $false
            Deadline        = $null
            RebootRequired  = $false
            MaxSizeBytes    = 12582912
            UpdateId        = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
            RevisionNumber  = 100
        },
        [PSCustomObject]@{
            Title           = 'Windows Malicious Software Removal Tool - March 2026'
            KBArticle       = ''
            KBArticleIDs    = @()
            Classification  = 'Update Rollups'
            Products        = @('Windows Server 2022')
            Description     = 'This tool checks your computer for infection'
            ReleaseNotes    = ''
            MsrcSeverity    = ''
            CveIDs          = @()
            IsDownloaded    = $false
            IsHidden        = $false
            IsInstalled     = $false
            IsMandatory     = $false
            IsUninstallable = $false
            EulaAccepted    = $true
            Deadline        = $null
            RebootRequired  = $false
            MaxSizeBytes    = 5242880
            UpdateId        = 'c3d4e5f6-a7b8-9012-cdef-123456789012'
            RevisionNumber  = 50
        },
        [PSCustomObject]@{
            Title           = 'Definition Update for Windows Defender (KB2267602)'
            KBArticle       = 'KB2267602'
            KBArticleIDs    = @('2267602')
            Classification  = 'Definition Updates'
            Products        = @('Windows Defender')
            Description     = 'Definition update for Windows Defender Antivirus'
            ReleaseNotes    = ''
            MsrcSeverity    = ''
            CveIDs          = @()
            IsDownloaded    = $true
            IsHidden        = $false
            IsInstalled     = $false
            IsMandatory     = $false
            IsUninstallable = $false
            EulaAccepted    = $true
            Deadline        = $null
            RebootRequired  = $false
            MaxSizeBytes    = 2097152
            UpdateId        = 'd4e5f6a7-b8c9-0123-defa-234567890123'
            RevisionNumber  = 1
        }
    )
}

Describe 'Get-WindowsUpdate' {

    Context 'Happy path - local machine, no filters' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    Metadata = $script:mockMetadata
                    Entries  = $script:mockUpdates
                }
            }

            $script:results = Get-WindowsUpdate
        }

        It -Name 'Should return results' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should return all 4 mock updates' -Test {
            @($script:results).Count | Should -Be 4
        }

        It -Name 'Should set correct PSTypeName on each object' -Test {
            foreach ($item in $script:results) {
                $item.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdate'
            }
        }

        It -Name 'Should set ComputerName to local machine' -Test {
            foreach ($item in $script:results) {
                $item.ComputerName | Should -Be $env:COMPUTERNAME
            }
        }

        It -Name 'Should include Timestamp in ISO 8601 format' -Test {
            foreach ($item in $script:results) {
                $item.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
            }
        }

        It -Name 'Should calculate SizeMB from MaxSizeBytes' -Test {
            $securityUpdate = $script:results | Where-Object -Property 'KBArticle' -EQ 'KB5034441'
            $securityUpdate.SizeMB | Should -Be ([math]::Round(47316992 / 1MB, 2))
        }
    }

    Context 'Classification filter' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadata; Entries = $script:mockUpdates }
            }
        }

        It -Name 'Should filter by single classification' -Test {
            $filtered = Get-WindowsUpdate -Classification 'Security Updates'
            @($filtered).Count | Should -Be 1
            $filtered.KBArticle | Should -Be 'KB5034441'
        }

        It -Name 'Should filter by multiple classifications' -Test {
            $filtered = Get-WindowsUpdate -Classification 'Security Updates', 'Critical Updates'
            @($filtered).Count | Should -Be 2
        }

        It -Name 'Should return nothing when classification matches none' -Test {
            $filtered = Get-WindowsUpdate -Classification 'Drivers'
            $filtered | Should -BeNullOrEmpty
        }
    }

    Context 'Product filter' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadata; Entries = $script:mockUpdates }
            }
        }

        It -Name 'Should filter by single product' -Test {
            $filtered = Get-WindowsUpdate -Product 'Windows Defender'
            @($filtered).Count | Should -Be 1
            $filtered.KBArticle | Should -Be 'KB2267602'
        }

        It -Name 'Should match when product is in the Products array' -Test {
            $filtered = Get-WindowsUpdate -Product 'Microsoft Server Operating System-24H2'
            @($filtered).Count | Should -Be 1
            $filtered.KBArticle | Should -Be 'KB5034441'
        }

        It -Name 'Should return all matching when product matches multiple updates' -Test {
            $filtered = Get-WindowsUpdate -Product 'Windows Server 2022'
            @($filtered).Count | Should -Be 3
        }

        It -Name 'Should return nothing when product matches none' -Test {
            $filtered = Get-WindowsUpdate -Product 'Microsoft Office'
            $filtered | Should -BeNullOrEmpty
        }
    }

    Context 'KBArticleID filter' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadata; Entries = $script:mockUpdates }
            }
        }

        It -Name 'Should filter by single KB with prefix' -Test {
            $filtered = Get-WindowsUpdate -KBArticleID 'KB5034441'
            @($filtered).Count | Should -Be 1
            $filtered.KBArticle | Should -Be 'KB5034441'
        }

        It -Name 'Should filter by single KB without prefix' -Test {
            $filtered = Get-WindowsUpdate -KBArticleID '5034441'
            @($filtered).Count | Should -Be 1
            $filtered.KBArticle | Should -Be 'KB5034441'
        }

        It -Name 'Should filter by multiple KBs' -Test {
            $filtered = Get-WindowsUpdate -KBArticleID 'KB5034441', 'KB2267602'
            @($filtered).Count | Should -Be 2
        }

        It -Name 'Should return nothing when KB matches none' -Test {
            $filtered = Get-WindowsUpdate -KBArticleID 'KB9999999'
            $filtered | Should -BeNullOrEmpty
        }
    }

    Context 'Combined Classification and Product filter' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadata; Entries = $script:mockUpdates }
            }
        }

        It -Name 'Should apply both filters' -Test {
            $filtered = Get-WindowsUpdate -Classification 'Security Updates' -Product 'Windows Server 2022'
            @($filtered).Count | Should -Be 1
            $filtered.KBArticle | Should -Be 'KB5034441'
        }

        It -Name 'Should return nothing when filters are mutually exclusive' -Test {
            $filtered = Get-WindowsUpdate -Classification 'Security Updates' -Product 'Windows Defender'
            $filtered | Should -BeNullOrEmpty
        }
    }

    Context 'MicrosoftUpdate switch' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadata; Entries = $script:mockUpdates }
            }
        }

        It -Name 'Should pass $false by default (use machine config)' -Test {
            Get-WindowsUpdate
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ArgumentList[1] -eq $false
            }
        }

        It -Name 'Should pass $true when MicrosoftUpdate is specified' -Test {
            Get-WindowsUpdate -MicrosoftUpdate
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ArgumentList[1] -eq $true
            }
        }
    }

    Context 'IncludeHidden switch' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadata; Entries = $script:mockUpdates }
            }
        }

        It -Name 'Should pass $false to scriptblock when IncludeHidden not specified' -Test {
            Get-WindowsUpdate
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ArgumentList[0] -eq $false
            }
        }

        It -Name 'Should pass $true to scriptblock when IncludeHidden is specified' -Test {
            Get-WindowsUpdate -IncludeHidden
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ArgumentList[0] -eq $true
            }
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadataSingle; Entries = @($script:mockUpdates[0]) }
            }

            $script:result = Get-WindowsUpdate -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-RemoteOrLocal with correct ComputerName' -Test {
            Get-WindowsUpdate -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ComputerName -eq 'SRV01'
            }
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadataSingle; Entries = @($script:mockUpdates[0]) }
            }

            $script:results = 'SRV01', 'SRV02' | Get-WindowsUpdate
        }

        It -Name 'Should process each machine from pipeline' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should set correct ComputerName for each result' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine' -Test {
            'SRV01', 'SRV02' | Get-WindowsUpdate
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Empty results' {

        BeforeAll {
            $emptyMeta = [PSCustomObject]@{
                ConfiguredSource = 'Windows Update'
                ConfiguredUrl    = $null
                TargetGroup      = $null
                EffectiveSource  = 'Windows Update'
                TotalCount       = 0
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $emptyMeta; Entries = @() }
            }
        }

        It -Name 'Should return nothing when no updates available' -Test {
            $result = Get-WindowsUpdate
            $result | Should -BeNullOrEmpty
        }

        It -Name 'Should not throw when no updates available' -Test {
            { Get-WindowsUpdate } | Should -Not -Throw
        }
    }

    Context 'Per-machine failure continues' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                throw 'WinRM connection failed'
            }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-WindowsUpdate -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should not throw with default ErrorAction' -Test {
            { Get-WindowsUpdate -ComputerName 'BADHOST' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It -Name 'Should return no output for failed machine' -Test {
            $result = Get-WindowsUpdate -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Get-WindowsUpdate -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-WindowsUpdate -ComputerName $null } | Should -Throw
        }

        It -Name 'Should accept CN alias for ComputerName' -Test {
            $paramMeta = (Get-Command -Name 'Get-WindowsUpdate').Parameters['ComputerName']
            $paramMeta.Aliases | Should -Contain 'CN'
        }

        It -Name 'Should accept DNSHostName alias for ComputerName' -Test {
            $paramMeta = (Get-Command -Name 'Get-WindowsUpdate').Parameters['ComputerName']
            $paramMeta.Aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should throw when Classification is empty string' -Test {
            { Get-WindowsUpdate -Classification '' } | Should -Throw
        }

        It -Name 'Should throw when Product is empty string' -Test {
            { Get-WindowsUpdate -Product '' } | Should -Throw
        }

        It -Name 'Should throw when KBArticleID is empty string' -Test {
            { Get-WindowsUpdate -KBArticleID '' } | Should -Throw
        }

        It -Name 'Should have MicrosoftUpdate switch parameter' -Test {
            $paramMeta = (Get-Command -Name 'Get-WindowsUpdate').Parameters['MicrosoftUpdate']
            $paramMeta | Should -Not -BeNullOrEmpty
            $paramMeta.ParameterType | Should -Be ([switch])
        }
    }

    Context 'Output object properties' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{ Metadata = $script:mockMetadataSingle; Entries = @($script:mockUpdates[0]) }
            }

            $script:result = Get-WindowsUpdate
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProperties = @(
                'ComputerName', 'Title', 'KBArticle', 'Classification', 'Products',
                'Description', 'ReleaseNotes', 'MsrcSeverity', 'CveIDs',
                'IsDownloaded', 'IsHidden', 'IsInstalled', 'IsMandatory',
                'IsUninstallable', 'EulaAccepted', 'Deadline', 'RebootRequired',
                'SizeMB', 'UpdateId', 'RevisionNumber', 'Timestamp'
            )
            foreach ($prop in $expectedProperties) {
                $script:result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should return Products as array' -Test {
            $script:result.Products | Should -BeOfType [string]
            @($script:result.Products).Count | Should -BeGreaterOrEqual 1
        }

        It -Name 'Should return CveIDs as array' -Test {
            @($script:result.CveIDs).Count | Should -Be 2
            $script:result.CveIDs | Should -Contain 'CVE-2026-1234'
        }

        It -Name 'Should preserve MsrcSeverity' -Test {
            $script:result.MsrcSeverity | Should -Be 'Critical'
        }

        It -Name 'Should preserve Description' -Test {
            $script:result.Description | Should -Be 'A cumulative security update for Windows Server 2022'
        }

        It -Name 'Should preserve Deadline' -Test {
            $script:result.Deadline | Should -Be ([datetime]'2026-04-15')
        }

        It -Name 'Should preserve EulaAccepted' -Test {
            $script:result.EulaAccepted | Should -BeTrue
        }

        It -Name 'Should preserve IsUninstallable' -Test {
            $script:result.IsUninstallable | Should -BeTrue
        }

        It -Name 'Should preserve IsInstalled' -Test {
            $script:result.IsInstalled | Should -BeFalse
        }

        It -Name 'Should preserve UpdateId GUID' -Test {
            $script:result.UpdateId | Should -Be 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        }

        It -Name 'Should preserve RevisionNumber' -Test {
            $script:result.RevisionNumber | Should -Be 201
        }

        It -Name 'Should preserve boolean properties' -Test {
            $script:result.IsDownloaded | Should -BeFalse
            $script:result.IsMandatory | Should -BeTrue
            $script:result.RebootRequired | Should -BeTrue
        }
    }
}