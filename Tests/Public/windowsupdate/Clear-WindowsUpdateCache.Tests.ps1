BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockClearSuccess = [PSCustomObject]@{
        CachePath        = 'C:\Windows\SoftwareDistribution\Download'
        FileCount        = 42
        SizeBytes        = 524288000
        DataStoreCleared = $false
        Result           = 'Succeeded'
        Errors           = @()
    }

    $script:mockClearWithDataStore = [PSCustomObject]@{
        CachePath        = 'C:\Windows\SoftwareDistribution\Download'
        FileCount        = 68
        SizeBytes        = 1073741824
        DataStoreCleared = $true
        Result           = 'Succeeded'
        Errors           = @()
    }

    $script:mockPartialSuccess = [PSCustomObject]@{
        CachePath        = 'C:\Windows\SoftwareDistribution\Download'
        FileCount        = 42
        SizeBytes        = 524288000
        DataStoreCleared = $false
        Result           = 'PartialSuccess'
        Errors           = @('Download folder: Access denied to file xyz')
    }
}

Describe -Name 'Clear-WindowsUpdateCache' -Tag 'Unit' -Fixture {

    Context 'Function metadata' {

        It -Name 'Should be an exported function' -Test {
            Get-Command -Name 'Clear-WindowsUpdateCache' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should support ShouldProcess' -Test {
            (Get-Command -Name 'Clear-WindowsUpdateCache').Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It -Name 'Should have ConfirmImpact High' -Test {
            $cmdletAttr = (Get-Command -Name 'Clear-WindowsUpdateCache').ScriptBlock.Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $cmdletAttr.ConfirmImpact | Should -Be 'High'
        }
    }

    Context 'Happy path - clear download cache' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockClearSuccess
            }
            $script:result = Clear-WindowsUpdateCache -Confirm:$false
        }

        It -Name 'Should return a result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have PSTypeName PSWinOps.WindowsUpdateCacheResult' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateCacheResult'
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProperties = @(
                'ComputerName', 'CachePath', 'FileCount', 'SizeFreedMB',
                'DataStoreCleared', 'Result', 'Timestamp'
            )
            foreach ($prop in $expectedProperties) {
                $script:result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should have Result Succeeded' -Test {
            $script:result.Result | Should -Be 'Succeeded'
        }

        It -Name 'Should calculate SizeFreedMB correctly' -Test {
            $script:result.SizeFreedMB | Should -Be 500
        }

        It -Name 'Should have FileCount 42' -Test {
            $script:result.FileCount | Should -Be 42
        }

        It -Name 'Should have DataStoreCleared false' -Test {
            $script:result.DataStoreCleared | Should -BeFalse
        }

        It -Name 'Should have ComputerName' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should have Timestamp' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}
        }
    }

    Context 'Clear with DataStore' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockClearWithDataStore
            }
            $script:result = Clear-WindowsUpdateCache -IncludeDataStore -Confirm:$false
        }

        It -Name 'Should have DataStoreCleared true' -Test {
            $script:result.DataStoreCleared | Should -BeTrue
        }

        It -Name 'Should calculate SizeFreedMB for larger size' -Test {
            $script:result.SizeFreedMB | Should -Be 1024
        }

        It -Name 'Should pass IncludeDataStore to scriptblock' -Test {
            Clear-WindowsUpdateCache -IncludeDataStore -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ArgumentList -contains $true
            }
        }
    }

    Context 'Partial success with errors' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPartialSuccess
            }
            $script:result = Clear-WindowsUpdateCache -Confirm:$false 3>&1
        }

        It -Name 'Should return PartialSuccess result' -Test {
            $output = $script:result | Where-Object -FilterScript { $_ -is [PSCustomObject] -and $_.PSObject.TypeNames -contains 'PSWinOps.WindowsUpdateCacheResult' }
            $output.Result | Should -Be 'PartialSuccess'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockClearSuccess
            }
            $script:result = Clear-WindowsUpdateCache -ComputerName 'SRV01' -Confirm:$false
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockClearSuccess
            }
            $script:results = 'SRV01', 'SRV02' | Clear-WindowsUpdateCache -Confirm:$false
        }

        It -Name 'Should return results for each machine' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should set correct ComputerName for each result' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'WhatIf support' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockClearSuccess
            }
        }

        It -Name 'Should not call Invoke-RemoteOrLocal with WhatIf' -Test {
            Clear-WindowsUpdateCache -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Per-machine error handling' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                throw 'Access denied'
            }
        }

        It -Name 'Should write error for failed machine' -Test {
            { Clear-WindowsUpdateCache -ComputerName 'BADHOST' -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Clear-WindowsUpdateCache -ComputerName '' } | Should -Throw
        }
    }
}