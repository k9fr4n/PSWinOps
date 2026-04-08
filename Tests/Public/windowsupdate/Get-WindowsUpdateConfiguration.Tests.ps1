#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockWsusData = [PSCustomObject]@{
        IsGPOConfigured                = $true
        WUServer                       = 'https://wsus.corp.local:8531'
        WUStatusServer                 = 'https://wsus.corp.local:8531'
        TargetGroup                    = 'Servers-Prod'
        TargetGroupEnabled             = 1
        DeferFeatureUpdates            = $null
        DeferFeatureUpdatesPeriodInDays = $null
        DeferQualityUpdates            = $null
        DeferQualityUpdatesPeriodInDays = $null
        BranchReadinessLevel           = $null
        PauseFeatureUpdatesStartTime   = $null
        PauseQualityUpdatesStartTime   = $null
        UseWUServer                    = 1
        NoAutoUpdate                   = 0
        AUOptions                      = 4
        ScheduledInstallDay            = 3
        ScheduledInstallTime           = 3
        NoAutoRebootWithLoggedOnUsers  = 1
    }

    $script:mockWufbData = [PSCustomObject]@{
        IsGPOConfigured                = $true
        WUServer                       = $null
        WUStatusServer                 = $null
        TargetGroup                    = $null
        TargetGroupEnabled             = $null
        DeferFeatureUpdates            = 1
        DeferFeatureUpdatesPeriodInDays = 30
        DeferQualityUpdates            = 1
        DeferQualityUpdatesPeriodInDays = 7
        BranchReadinessLevel           = 32
        PauseFeatureUpdatesStartTime   = $null
        PauseQualityUpdatesStartTime   = $null
        UseWUServer                    = $null
        NoAutoUpdate                   = $null
        AUOptions                      = 3
        ScheduledInstallDay            = $null
        ScheduledInstallTime           = $null
        NoAutoRebootWithLoggedOnUsers  = $null
    }

    $script:mockDefaultData = [PSCustomObject]@{
        IsGPOConfigured                = $false
        WUServer                       = $null
        WUStatusServer                 = $null
        TargetGroup                    = $null
        TargetGroupEnabled             = $null
        DeferFeatureUpdates            = $null
        DeferFeatureUpdatesPeriodInDays = $null
        DeferQualityUpdates            = $null
        DeferQualityUpdatesPeriodInDays = $null
        BranchReadinessLevel           = $null
        PauseFeatureUpdatesStartTime   = $null
        PauseQualityUpdatesStartTime   = $null
        UseWUServer                    = $null
        NoAutoUpdate                   = $null
        AUOptions                      = $null
        ScheduledInstallDay            = $null
        ScheduledInstallTime           = $null
        NoAutoRebootWithLoggedOnUsers  = $null
    }
}

Describe 'Get-WindowsUpdateConfiguration' {

    Context 'WSUS configuration' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockWsusData
            }

            $script:result = Get-WindowsUpdateConfiguration
        }

        It -Name 'Should return a result' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should set correct PSTypeName' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateConfiguration'
        }

        It -Name 'Should detect UpdateSource as WSUS' -Test {
            $script:result.UpdateSource | Should -Be 'WSUS'
        }

        It -Name 'Should return WSUS server URL' -Test {
            $script:result.WUServerUrl | Should -Be 'https://wsus.corp.local:8531'
        }

        It -Name 'Should return WSUS status server URL' -Test {
            $script:result.WUStatusServerUrl | Should -Be 'https://wsus.corp.local:8531'
        }

        It -Name 'Should set UseWUServer to true' -Test {
            $script:result.UseWUServer | Should -BeTrue
        }

        It -Name 'Should map AUOptions 4 to ScheduledInstall' -Test {
            $script:result.AutoUpdateOption | Should -Be 'ScheduledInstall'
        }

        It -Name 'Should map ScheduledInstallDay 3 to Tuesday' -Test {
            $script:result.ScheduledInstallDay | Should -Be 'Tuesday'
        }

        It -Name 'Should return ScheduledInstallTime' -Test {
            $script:result.ScheduledInstallTime | Should -Be 3
        }

        It -Name 'Should set NoAutoRebootWithLoggedOnUsers to true' -Test {
            $script:result.NoAutoRebootWithLoggedOnUsers | Should -BeTrue
        }

        It -Name 'Should return TargetGroup' -Test {
            $script:result.TargetGroup | Should -Be 'Servers-Prod'
        }

        It -Name 'Should set TargetGroupEnabled to true' -Test {
            $script:result.TargetGroupEnabled | Should -BeTrue
        }

        It -Name 'Should set IsGPOConfigured to true' -Test {
            $script:result.IsGPOConfigured | Should -BeTrue
        }

        It -Name 'Should set AutoUpdateEnabled to true' -Test {
            $script:result.AutoUpdateEnabled | Should -BeTrue
        }

        It -Name 'Should include Timestamp in ISO 8601 format' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }

    Context 'WUFB configuration' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockWufbData
            }

            $script:result = Get-WindowsUpdateConfiguration
        }

        It -Name 'Should detect UpdateSource as WUFB' -Test {
            $script:result.UpdateSource | Should -Be 'WUFB'
        }

        It -Name 'Should return DeferFeatureUpdatesDays' -Test {
            $script:result.DeferFeatureUpdatesDays | Should -Be 30
        }

        It -Name 'Should return DeferQualityUpdatesDays' -Test {
            $script:result.DeferQualityUpdatesDays | Should -Be 7
        }

        It -Name 'Should map BranchReadinessLevel 32 to SemiAnnual' -Test {
            $script:result.BranchReadinessLevel | Should -Be 'SemiAnnual'
        }

        It -Name 'Should set UseWUServer to false when null' -Test {
            $script:result.UseWUServer | Should -BeFalse
        }

        It -Name 'Should map AUOptions 3 to AutoDownload' -Test {
            $script:result.AutoUpdateOption | Should -Be 'AutoDownload'
        }
    }

    Context 'Default Windows Update (no GPO)' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDefaultData
            }

            $script:result = Get-WindowsUpdateConfiguration
        }

        It -Name 'Should detect UpdateSource as WindowsUpdate' -Test {
            $script:result.UpdateSource | Should -Be 'WindowsUpdate'
        }

        It -Name 'Should set IsGPOConfigured to false' -Test {
            $script:result.IsGPOConfigured | Should -BeFalse
        }

        It -Name 'Should return null for WUServerUrl' -Test {
            $script:result.WUServerUrl | Should -BeNullOrEmpty
        }

        It -Name 'Should return null for AutoUpdateOption when AUOptions is null' -Test {
            $script:result.AutoUpdateOption | Should -BeNullOrEmpty
        }

        It -Name 'Should return null for ScheduledInstallDay when not set' -Test {
            $script:result.ScheduledInstallDay | Should -BeNullOrEmpty
        }

        It -Name 'Should return null for BranchReadinessLevel when not set' -Test {
            $script:result.BranchReadinessLevel | Should -BeNullOrEmpty
        }

        It -Name 'Should return null for DeferFeatureUpdatesDays when not set' -Test {
            $script:result.DeferFeatureUpdatesDays | Should -BeNullOrEmpty
        }

        It -Name 'Should set TargetGroupEnabled to false when null' -Test {
            $script:result.TargetGroupEnabled | Should -BeFalse
        }
    }

    Context 'AutoUpdate disabled' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    IsGPOConfigured                = $true
                    WUServer                       = $null
                    WUStatusServer                 = $null
                    TargetGroup                    = $null
                    TargetGroupEnabled             = $null
                    DeferFeatureUpdates            = $null
                    DeferFeatureUpdatesPeriodInDays = $null
                    DeferQualityUpdates            = $null
                    DeferQualityUpdatesPeriodInDays = $null
                    BranchReadinessLevel           = $null
                    PauseFeatureUpdatesStartTime   = $null
                    PauseQualityUpdatesStartTime   = $null
                    UseWUServer                    = $null
                    NoAutoUpdate                   = 1
                    AUOptions                      = $null
                    ScheduledInstallDay            = $null
                    ScheduledInstallTime           = $null
                    NoAutoRebootWithLoggedOnUsers  = $null
                }
            }

            $script:result = Get-WindowsUpdateConfiguration
        }

        It -Name 'Should set AutoUpdateEnabled to false when NoAutoUpdate is 1' -Test {
            $script:result.AutoUpdateEnabled | Should -BeFalse
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockWsusData
            }

            $script:result = Get-WindowsUpdateConfiguration -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-RemoteOrLocal with correct ComputerName' -Test {
            Get-WindowsUpdateConfiguration -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ComputerName -eq 'SRV01'
            }
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockWsusData
            }

            $script:results = 'SRV01', 'SRV02' | Get-WindowsUpdateConfiguration
        }

        It -Name 'Should process each machine from pipeline' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should set correct ComputerName for each result' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine' -Test {
            'SRV01', 'SRV02' | Get-WindowsUpdateConfiguration
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure continues' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                throw 'Access denied'
            }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-WindowsUpdateConfiguration -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should not throw with default ErrorAction' -Test {
            { Get-WindowsUpdateConfiguration -ComputerName 'BADHOST' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It -Name 'Should return no output for failed machine' -Test {
            $failResult = Get-WindowsUpdateConfiguration -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Get-WindowsUpdateConfiguration -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-WindowsUpdateConfiguration -ComputerName $null } | Should -Throw
        }

        It -Name 'Should accept CN alias for ComputerName' -Test {
            $paramMeta = (Get-Command -Name 'Get-WindowsUpdateConfiguration').Parameters['ComputerName']
            $paramMeta.Aliases | Should -Contain 'CN'
        }

        It -Name 'Should accept DNSHostName alias for ComputerName' -Test {
            $paramMeta = (Get-Command -Name 'Get-WindowsUpdateConfiguration').Parameters['ComputerName']
            $paramMeta.Aliases | Should -Contain 'DNSHostName'
        }
    }

    Context 'AUOptions mapping completeness' {

        It -Name 'Should map AUOptions <AUOption> to <Expected>' -TestCases @(
            @{ AUOption = 1; Expected = 'Disabled' }
            @{ AUOption = 2; Expected = 'NotifyDownload' }
            @{ AUOption = 3; Expected = 'AutoDownload' }
            @{ AUOption = 4; Expected = 'ScheduledInstall' }
            @{ AUOption = 5; Expected = 'AllowLocalAdmin' }
        ) -Test {
            param($AUOption, $Expected)
            $mockAU = $AUOption
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    IsGPOConfigured = $true; WUServer = $null; WUStatusServer = $null
                    TargetGroup = $null; TargetGroupEnabled = $null
                    DeferFeatureUpdates = $null; DeferFeatureUpdatesPeriodInDays = $null
                    DeferQualityUpdates = $null; DeferQualityUpdatesPeriodInDays = $null
                    BranchReadinessLevel = $null; PauseFeatureUpdatesStartTime = $null
                    PauseQualityUpdatesStartTime = $null; UseWUServer = $null
                    NoAutoUpdate = $null; AUOptions = $mockAU
                    ScheduledInstallDay = $null; ScheduledInstallTime = $null
                    NoAutoRebootWithLoggedOnUsers = $null
                }
            }
            $result = Get-WindowsUpdateConfiguration
            $result.AutoUpdateOption | Should -Be $Expected
        }
    }

    Context 'ScheduledInstallDay mapping completeness' {

        It -Name 'Should map ScheduledInstallDay <DayValue> to <Expected>' -TestCases @(
            @{ DayValue = 0; Expected = 'EveryDay' }
            @{ DayValue = 1; Expected = 'Sunday' }
            @{ DayValue = 2; Expected = 'Monday' }
            @{ DayValue = 3; Expected = 'Tuesday' }
            @{ DayValue = 4; Expected = 'Wednesday' }
            @{ DayValue = 5; Expected = 'Thursday' }
            @{ DayValue = 6; Expected = 'Friday' }
            @{ DayValue = 7; Expected = 'Saturday' }
        ) -Test {
            param($DayValue, $Expected)
            $mockDay = $DayValue
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    IsGPOConfigured = $true; WUServer = $null; WUStatusServer = $null
                    TargetGroup = $null; TargetGroupEnabled = $null
                    DeferFeatureUpdates = $null; DeferFeatureUpdatesPeriodInDays = $null
                    DeferQualityUpdates = $null; DeferQualityUpdatesPeriodInDays = $null
                    BranchReadinessLevel = $null; PauseFeatureUpdatesStartTime = $null
                    PauseQualityUpdatesStartTime = $null; UseWUServer = $null
                    NoAutoUpdate = $null; AUOptions = $null
                    ScheduledInstallDay = $mockDay; ScheduledInstallTime = $null
                    NoAutoRebootWithLoggedOnUsers = $null
                }
            }
            $result = Get-WindowsUpdateConfiguration
            $result.ScheduledInstallDay | Should -Be $Expected
        }
    }

    Context 'BranchReadinessLevel mapping' {

        It -Name 'Should map BranchReadinessLevel <Level> to <Expected>' -TestCases @(
            @{ Level = 16; Expected = 'SemiAnnualPreview' }
            @{ Level = 32; Expected = 'SemiAnnual' }
            @{ Level = 64; Expected = 'LongTermServicing' }
        ) -Test {
            param($Level, $Expected)
            $mockBranch = $Level
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    IsGPOConfigured = $true; WUServer = $null; WUStatusServer = $null
                    TargetGroup = $null; TargetGroupEnabled = $null
                    DeferFeatureUpdates = 1; DeferFeatureUpdatesPeriodInDays = $null
                    DeferQualityUpdates = $null; DeferQualityUpdatesPeriodInDays = $null
                    BranchReadinessLevel = $mockBranch; PauseFeatureUpdatesStartTime = $null
                    PauseQualityUpdatesStartTime = $null; UseWUServer = $null
                    NoAutoUpdate = $null; AUOptions = $null
                    ScheduledInstallDay = $null; ScheduledInstallTime = $null
                    NoAutoRebootWithLoggedOnUsers = $null
                }
            }
            $result = Get-WindowsUpdateConfiguration
            $result.BranchReadinessLevel | Should -Be $Expected
        }
    }

    Context 'Output object properties' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockWsusData
            }

            $script:result = Get-WindowsUpdateConfiguration
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProperties = @(
                'ComputerName', 'UpdateSource', 'WUServerUrl', 'WUStatusServerUrl',
                'UseWUServer', 'AutoUpdateEnabled', 'AutoUpdateOption',
                'ScheduledInstallDay', 'ScheduledInstallTime',
                'NoAutoRebootWithLoggedOnUsers', 'DeferFeatureUpdatesDays',
                'DeferQualityUpdatesDays', 'BranchReadinessLevel',
                'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime',
                'TargetGroup', 'TargetGroupEnabled', 'IsGPOConfigured', 'Timestamp'
            )
            foreach ($prop in $expectedProperties) {
                $script:result.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }
}