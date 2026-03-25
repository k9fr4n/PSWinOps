#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-ServiceHealth' {

    BeforeAll {
        $script:mockServices = @(
            [PSCustomObject]@{ Name = 'W32Time'; DisplayName = 'Windows Time'; State = 'Running'; StartMode = 'Auto'; StartName = 'LocalSystem'; ProcessId = 1234 },
            [PSCustomObject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; State = 'Stopped'; StartMode = 'Auto'; StartName = 'LocalSystem'; ProcessId = 0 },
            [PSCustomObject]@{ Name = 'BITS'; DisplayName = 'Background Intelligent Transfer'; State = 'Stopped'; StartMode = 'Manual'; StartName = 'LocalSystem'; ProcessId = 0 },
            [PSCustomObject]@{ Name = 'RemoteRegistry'; DisplayName = 'Remote Registry'; State = 'Stopped'; StartMode = 'Disabled'; StartName = 'LocalService'; ProcessId = 0 }
        )
        # CimSession mock created inline via New-MockObject
    }

    Context 'Default - only degraded services' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            $script:results = Get-ServiceHealth
        }

        It -Name 'Should return only 1 degraded service' -Test {
            $script:results | Should -HaveCount 1
        }

        It -Name 'Should return Spooler as the degraded service' -Test {
            $script:results.ServiceName | Should -Be 'Spooler'
        }

        It -Name 'Should have Status Degraded' -Test {
            $script:results.Status | Should -Be 'Degraded'
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:results.PSObject.TypeNames | Should -Contain 'PSWinOps.ServiceHealth'
        }
    }

    Context 'IncludeAll switch' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            $script:results = Get-ServiceHealth -IncludeAll
        }

        It -Name 'Should return all 4 services' -Test {
            $script:results | Should -HaveCount 4
        }

        It -Name 'Should mark W32Time as Healthy' -Test {
            ($script:results | Where-Object -FilterScript { $_.ServiceName -eq 'W32Time' }).Status | Should -Be 'Healthy'
        }

        It -Name 'Should mark Spooler as Degraded' -Test {
            ($script:results | Where-Object -FilterScript { $_.ServiceName -eq 'Spooler' }).Status | Should -Be 'Degraded'
        }

        It -Name 'Should mark BITS as Stopped' -Test {
            ($script:results | Where-Object -FilterScript { $_.ServiceName -eq 'BITS' }).Status | Should -Be 'Stopped'
        }

        It -Name 'Should mark RemoteRegistry as Disabled' -Test {
            ($script:results | Where-Object -FilterScript { $_.ServiceName -eq 'RemoteRegistry' }).Status | Should -Be 'Disabled'
        }
    }

    Context 'ServiceName filter' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            $script:results = Get-ServiceHealth -ServiceName 'W32*' -IncludeAll
        }

        It -Name 'Should return only W32Time' -Test {
            $script:results | Should -HaveCount 1
            $script:results.ServiceName | Should -Be 'W32Time'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith { New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession' }
            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            $script:results = Get-ServiceHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return valid ServiceHealth for remote machine' -Test {
            $script:results.PSObject.TypeNames | Should -Contain 'PSWinOps.ServiceHealth'
        }

        It -Name 'Should query Get-CimInstance for remote machine' -Test {
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith { New-MockObject -Type 'Microsoft.Management.Infrastructure.CimSession' }
            Mock -CommandName 'Remove-CimSession' -ModuleName 'PSWinOps' -MockWith {}
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            $script:results = 'SRV01', 'SRV02' | Get-ServiceHealth -IncludeAll
        }

        It -Name 'Should query Get-CimInstance for each machine' -Test {
            Should -Invoke -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'New-CimSession' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-ServiceHealth -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-ServiceHealth -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-ServiceHealth -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-ServiceHealth -ComputerName $null } | Should -Throw
        }
    }
}
