#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-DriverInventory' {

    BeforeAll {
        $script:mockDrivers = @(
            [PSCustomObject]@{
                DeviceName    = 'Intel Ethernet Adapter'
                DeviceClass   = 'Net'
                Manufacturer  = 'Intel'
                DriverVersion = '12.18.9.23'
                DriverDate    = [datetime]'2021-05-14'
                IsSigned      = $true
                InfName       = 'oem12.inf'
            },
            [PSCustomObject]@{
                DeviceName    = 'Legacy Widget Controller'
                DeviceClass   = 'System'
                Manufacturer  = 'Acme'
                DriverVersion = $null
                DriverDate    = $null
                IsSigned      = $false
                InfName       = 'oem34.inf'
            }
        )
    }

    Context 'Happy path - local' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDrivers
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) {
                    & $ScriptBlock @ArgumentList
                } else {
                    & $ScriptBlock
                }
            }
            $script:result = Get-DriverInventory
        }

        It -Name 'Should return PSWinOps.DriverInventory type' -Test {
            $script:result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DriverInventory'
        }

        It -Name 'Should return one object per driver' -Test {
            $script:result | Should -HaveCount 2
        }

        It -Name 'Should map ComputerName to the local computer' -Test {
            $script:result[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should map driver fields correctly' -Test {
            $script:result[0].DeviceName | Should -Be 'Intel Ethernet Adapter'
            $script:result[0].DeviceClass | Should -Be 'Net'
            $script:result[0].Manufacturer | Should -Be 'Intel'
            $script:result[0].DriverVersion | Should -Be '12.18.9.23'
            $script:result[0].InfName | Should -Be 'oem12.inf'
        }

        It -Name 'Should emit IsSigned as a boolean' -Test {
            $script:result[0].IsSigned | Should -BeOfType [bool]
            $script:result[0].IsSigned | Should -BeTrue
            $script:result[1].IsSigned | Should -BeFalse
        }

        It -Name 'Should tolerate null version and date without excluding the row' -Test {
            $script:result[1].DriverVersion | Should -BeNullOrEmpty
            $script:result[1].DriverDate | Should -BeNullOrEmpty
        }
    }

    Context 'DeviceClass filter - case insensitive' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDrivers
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) {
                    & $ScriptBlock @ArgumentList
                } else {
                    & $ScriptBlock
                }
            }
            $script:result = Get-DriverInventory -DeviceClass 'net'
        }

        It -Name 'Should return only drivers of the requested class regardless of case' -Test {
            $script:result | Should -HaveCount 1
            $script:result[0].DeviceClass | Should -Be 'Net'
        }
    }

    Context 'UnsignedOnly filter' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDrivers
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) {
                    & $ScriptBlock @ArgumentList
                } else {
                    & $ScriptBlock
                }
            }
            $script:result = Get-DriverInventory -UnsignedOnly
        }

        It -Name 'Should return only unsigned drivers' -Test {
            $script:result | Should -HaveCount 1
            $script:result[0].IsSigned | Should -BeFalse
            $script:result[0].DeviceName | Should -Be 'Legacy Widget Controller'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDrivers
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) {
                    & $ScriptBlock @ArgumentList
                } else {
                    & $ScriptBlock
                }
            }
            $script:result = Get-DriverInventory -ComputerName 'SRV01'
        }

        It -Name 'Should return ComputerName SRV01' -Test {
            $script:result[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return valid DriverInventory objects for remote machine' -Test {
            $script:result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.DriverInventory'
            $script:result[0].DeviceName | Should -Be 'Intel Ethernet Adapter'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDrivers
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) {
                    & $ScriptBlock @ArgumentList
                } else {
                    & $ScriptBlock
                }
            }
            $script:results = 'SRV01', 'SRV02' | Get-DriverInventory
        }

        It -Name 'Should return results for both machines' -Test {
            $script:results | Should -HaveCount 4
        }

        It -Name 'Should return distinct ComputerName per machine' -Test {
            ($script:results | Where-Object { $_.ComputerName -eq 'SRV01' }) | Should -HaveCount 2
            ($script:results | Where-Object { $_.ComputerName -eq 'SRV02' }) | Should -HaveCount 2
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-DriverInventory -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-DriverInventory -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-DriverInventory -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-DriverInventory -ComputerName $null } | Should -Throw
        }
    }
}
