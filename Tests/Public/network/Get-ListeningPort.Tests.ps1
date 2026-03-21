BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-ListeningPort' {

    Context 'Happy path - local TCP listeners' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; OwningProcess = 1234; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 443; OwningProcess = 1234; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @([PSCustomObject]@{ Id = 1234; ProcessName = 'httpd' })
            }
        }

        It 'Should return listening ports with process names' {
            $result = Get-ListeningPort -Protocol TCP
            $result.Count | Should -Be 2
            $result[0].ProcessName | Should -Be 'httpd'
            $result[0].Protocol | Should -Be 'TCP'
        }

        It 'Should include PSTypeName PSWinOps.ListeningPort' {
            $result = Get-ListeningPort -Protocol TCP
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ListeningPort'
        }

        It 'Should include ComputerName and Timestamp' {
            $result = Get-ListeningPort -Protocol TCP
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
            $result[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Port filter' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; OwningProcess = 100; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 443; OwningProcess = 100; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @([PSCustomObject]@{ Id = 100; ProcessName = 'nginx' })
            }
        }

        It 'Should filter by specific port number' {
            $result = Get-ListeningPort -Protocol TCP -Port 443
            $result.Count | Should -Be 1
            $result[0].LocalPort | Should -Be 443
        }
    }

    Context 'Remote machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 3389; ProcessId = 500; ProcessName = 'TermService' })
            }
        }

        It 'Should query remote via Invoke-Command' {
            $result = Get-ListeningPort -ComputerName 'REMOTE01'
            $result.ComputerName | Should -Be 'REMOTE01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Pipeline input' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 22; ProcessId = 1; ProcessName = 'sshd' })
            }
        }

        It 'Should accept multiple computers via pipeline' {
            'SRV01', 'SRV02' | Get-ListeningPort
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Parameter validation' {

        It 'Should reject invalid Protocol' {
            { Get-ListeningPort -Protocol 'SCTP' } | Should -Throw
        }

        It 'Should reject Port 0' {
            { Get-ListeningPort -Port 0 } | Should -Throw
        }
    }
}
