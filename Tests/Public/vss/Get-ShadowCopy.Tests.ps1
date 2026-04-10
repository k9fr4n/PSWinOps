#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables used across It blocks'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-ShadowCopy' {

    BeforeAll {
        $script:testShadowId = '{AB12CD34-EF56-7890-AB12-CD34EF567890}'
        $script:testCreationTime = (Get-Date).AddDays(-3)

        $script:mockShadowData = @(
            [PSCustomObject]@{
                ShadowCopyId = $script:testShadowId
                DriveLetter  = 'C'
                VolumeName   = '\\?\Volume{abc123}\'
                CreationTime = $script:testCreationTime
                DeviceObject = '\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1'
                ProviderName = 'Microsoft Software Shadow Copy provider 1.0'
                StateCode    = 9
            }
        )
    }

    Context 'Happy path - local execution' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockShadowData
            }
            $script:result = Get-ShadowCopy
        }

        It 'Should return PSWinOps.ShadowCopy type' { $script:result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ShadowCopy' }
        It 'Should set ComputerName to local' { $script:result.ComputerName | Should -Be $env:COMPUTERNAME }
        It 'Should map StateCode 9 to Created' { $script:result.State | Should -Be 'Created' }
        It 'Should contain ShadowCopyId' { $script:result.ShadowCopyId | Should -Be $script:testShadowId }
        It 'Should contain DriveLetter' { $script:result.DriveLetter | Should -Be 'C' }
        It 'Should have Timestamp' { $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}' }
    }

    Context 'DriveLetter filter' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockShadowData }
            $script:result = Get-ShadowCopy -DriveLetter 'C'
        }
        It 'Should return filtered results' { $script:result.DriveLetter | Should -Be 'C' }
    }

    Context 'Remote single machine' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockShadowData }
            $script:result = Get-ShadowCopy -ComputerName 'SRV01'
        }
        It 'Should set ComputerName to remote' { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'Pipeline with multiple computers' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockShadowData }
            $script:result = @('SRV01', 'SRV02') | Get-ShadowCopy
        }
        It 'Should return results for each computer' { $script:result.Count | Should -BeGreaterOrEqual 2 }
        It 'Should set correct ComputerName for first' { $script:result[0].ComputerName | Should -Be 'SRV01' }
        It 'Should set correct ComputerName for second' { $script:result[1].ComputerName | Should -Be 'SRV02' }
    }

    Context 'Per-machine failure handling' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { throw 'RPC unavailable' }
            Mock -CommandName 'Write-Error' -ModuleName 'PSWinOps'
            $script:result = Get-ShadowCopy -ComputerName 'SRV01' -ErrorAction SilentlyContinue
        }
        It 'Should not throw' { { Get-ShadowCopy -ComputerName 'SRV01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
        It 'Should call Write-Error' { Should -Invoke -CommandName 'Write-Error' -ModuleName 'PSWinOps' -Times 1 -Exactly }
        It 'Should return no output' { $script:result | Should -BeNullOrEmpty }
    }

    Context 'Empty result' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $null }
            $script:result = Get-ShadowCopy -ComputerName 'SRV01'
        }
        It 'Should return no output' { $script:result | Should -BeNullOrEmpty }
    }

    Context 'Parameter validation' {
        BeforeAll { $script:cmdInfo = Get-Command -Name 'Get-ShadowCopy' -Module 'PSWinOps' }
        It 'Should accept CN alias' { $script:cmdInfo.Parameters['ComputerName'].Aliases | Should -Contain 'CN' }
        It 'Should accept Name alias' { $script:cmdInfo.Parameters['ComputerName'].Aliases | Should -Contain 'Name' }
        It 'Should accept DNSHostName alias' { $script:cmdInfo.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName' }
        It 'Should reject invalid DriveLetter' { { Get-ShadowCopy -DriveLetter 'ZZ' } | Should -Throw }
    }
}
