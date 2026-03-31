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
    }

    Context 'Default - only degraded services' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
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
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
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
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = Get-ServiceHealth -ServiceName 'W32*' -IncludeAll
        }

        It -Name 'Should return only W32Time' -Test {
            $script:results | Should -HaveCount 1
            $script:results.ServiceName | Should -Be 'W32Time'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = Get-ServiceHealth -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return valid ServiceHealth for remote machine' -Test {
            $script:results.PSObject.TypeNames | Should -Contain 'PSWinOps.ServiceHealth'
        }

    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = 'SRV01', 'SRV02' | Get-ServiceHealth -IncludeAll
        }

        It -Name 'Should return results for both machines' -Test {
            $script:results.ComputerName | Select-Object -Unique | Should -HaveCount 2
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ComputerName -eq 'BADHOST'
            } -MockWith { throw 'Connection failed' }
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

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            $script:typeResult = Get-ServiceHealth
        }
        It -Name 'Should have PSTypeName PSWinOps.ServiceHealth' -Test { (@($script:typeResult))[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ServiceHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
            $script:typeResult = Get-ServiceHealth
        }
        It -Name 'Should have Timestamp matching ISO 8601' -Test { (@($script:typeResult))[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith { return $script:mockServices }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-ServiceHealth -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-ServiceHealth -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-ServiceHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-ServiceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-ServiceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-ServiceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-ServiceHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }
}