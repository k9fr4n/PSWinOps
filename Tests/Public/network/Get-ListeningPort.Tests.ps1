BeforeAll {
    # Stub Windows-only commands BEFORE module import so Pester can mock them
    if (-not (Get-Command -Name 'Get-NetTCPConnection' -ErrorAction SilentlyContinue)) {
        function global:Get-NetTCPConnection { }
    }
    if (-not (Get-Command -Name 'Get-NetUDPEndpoint' -ErrorAction SilentlyContinue)) {
        function global:Get-NetUDPEndpoint { }
    }

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

    Context 'UDP endpoints (via remote path)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @(
                    [PSCustomObject]@{ Protocol = 'UDP'; LocalAddress = '0.0.0.0'; LocalPort = 53; ProcessId = 200; ProcessName = 'dns' },
                    [PSCustomObject]@{ Protocol = 'UDP'; LocalAddress = '0.0.0.0'; LocalPort = 67; ProcessId = 200; ProcessName = 'dns' }
                )
            }
        }

        It 'Should return UDP endpoints when Protocol is UDP' {
            $result = Get-ListeningPort -ComputerName 'REMOTE01' -Protocol UDP
            $result.Count | Should -Be 2
            $result[0].Protocol | Should -Be 'UDP'
        }

        It 'Should return both TCP and UDP with default Protocol' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @(
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 80; ProcessId = 100; ProcessName = 'httpd' },
                    [PSCustomObject]@{ Protocol = 'UDP'; LocalAddress = '0.0.0.0'; LocalPort = 53; ProcessId = 200; ProcessName = 'dns' }
                )
            }
            $result = Get-ListeningPort -ComputerName 'REMOTE01'
            ($result | Where-Object Protocol -eq 'TCP').Count | Should -BeGreaterThan 0
            ($result | Where-Object Protocol -eq 'UDP').Count | Should -BeGreaterThan 0
        }

        It 'Should accept multiple protocol values' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @(
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 80; ProcessId = 100; ProcessName = 'httpd' },
                    [PSCustomObject]@{ Protocol = 'UDP'; LocalAddress = '0.0.0.0'; LocalPort = 53; ProcessId = 200; ProcessName = 'dns' }
                )
            }
            $result = Get-ListeningPort -ComputerName 'REMOTE01' -Protocol 'TCP', 'UDP'
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ProcessName filter (via remote path)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @(
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 80; ProcessId = 100; ProcessName = 'httpd' },
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 443; ProcessId = 300; ProcessName = 'nginx' }
                )
            }
        }

        It 'Should return results for remote machines with ProcessName' {
            $result = Get-ListeningPort -ComputerName 'REMOTE01' -ProcessName 'http*'
            # Note: ProcessName filtering happens inside the remote scriptblock; 
            # since we mock Invoke-Command entirely, all results come back
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Special process IDs (via remote path)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @(
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 135; ProcessId = 0; ProcessName = 'System Idle' },
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 445; ProcessId = 4; ProcessName = 'System' },
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 8080; ProcessId = 99999; ProcessName = '[Unknown]' }
                )
            }
        }

        It 'Should preserve PID 0 label from remote query' {
            $result = Get-ListeningPort -ComputerName 'REMOTE01' -Protocol TCP
            ($result | Where-Object ProcessId -eq 0).ProcessName | Should -Be 'System Idle'
        }

        It 'Should preserve PID 4 label from remote query' {
            $result = Get-ListeningPort -ComputerName 'REMOTE01' -Protocol TCP
            ($result | Where-Object ProcessId -eq 4).ProcessName | Should -Be 'System'
        }

        It 'Should preserve unknown PID label from remote query' {
            $result = Get-ListeningPort -ComputerName 'REMOTE01' -Protocol TCP
            ($result | Where-Object ProcessId -eq 99999).ProcessName | Should -Be '[Unknown]'
        }
    }

    Context 'Remote with Credential' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 3389; ProcessId = 500; ProcessName = 'TermService' })
            }
        }

        It 'Should pass Credential to Invoke-Command when provided' {
            $cred = [PSCredential]::new('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            Get-ListeningPort -ComputerName 'REMOTE01' -Credential $cred
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 22; ProcessId = 1; ProcessName = 'sshd' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -ParameterFilter {
                $ComputerName -eq 'BADSERVER'
            } -MockWith { throw 'Connection refused' }
        }

        It 'Should continue after a machine fails' {
            $result = Get-ListeningPort -ComputerName 'SRV01', 'BADSERVER', 'SRV02' -ErrorAction SilentlyContinue
            $result.Count | Should -Be 2
        }

        It 'Should write error for the failing machine' {
            $null = Get-ListeningPort -ComputerName 'BADSERVER' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Should reject invalid Protocol' {
            { Get-ListeningPort -Protocol 'SCTP' } | Should -Throw
        }

        It 'Should support Name alias for ComputerName' {
            $cmd = Get-Command -Name 'Get-ListeningPort'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }

        It 'Should have Protocol as string array' {
            $cmd = Get-Command -Name 'Get-ListeningPort'
            $cmd.Parameters['Protocol'].ParameterType | Should -Be ([string[]])
        }

        It 'Should reject Port 0' {
            { Get-ListeningPort -Port 0 } | Should -Throw
        }

        It 'Should reject Port above 65535' {
            { Get-ListeningPort -Port 70000 } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Get-ListeningPort -ComputerName '' } | Should -Throw
        }
    }

    Context 'Local execution - TCP and UDP via scriptblock' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; OwningProcess = [uint32]1234; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 53; OwningProcess = [uint32]5678 }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @(
                    [PSCustomObject]@{ Id = 1234; ProcessName = 'httpd' },
                    [PSCustomObject]@{ Id = 5678; ProcessName = 'dns' }
                )
            }
        }

        It 'Should return both TCP and UDP results for local machine' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME
            $result | Should -Not -BeNullOrEmpty
            ($result | Where-Object Protocol -eq 'TCP') | Should -Not -BeNullOrEmpty
            ($result | Where-Object Protocol -eq 'UDP') | Should -Not -BeNullOrEmpty
        }

        It 'Should resolve process names for local TCP connections' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME -Protocol TCP
            $result[0].ProcessName | Should -Be 'httpd'
        }

        It 'Should resolve process names for local UDP endpoints' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME -Protocol UDP
            $result[0].ProcessName | Should -Be 'dns'
        }

        It 'Should handle localhost as local machine' {
            $result = Get-ListeningPort -ComputerName 'localhost' -Protocol TCP
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Local execution - special PIDs in scriptblock' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 135; OwningProcess = [uint32]0; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 445; OwningProcess = [uint32]4; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 8080; OwningProcess = [uint32]99999; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @([PSCustomObject]@{ Id = 100; ProcessName = 'svchost' })
            }
        }

        It 'Should label PID 0 as System Idle locally' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME -Protocol TCP
            ($result | Where-Object ProcessId -eq 0).ProcessName | Should -Be 'System Idle'
        }

        It 'Should label PID 4 as System locally' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME -Protocol TCP
            ($result | Where-Object ProcessId -eq 4).ProcessName | Should -Be 'System'
        }

        It 'Should label unknown PID as [Unknown] locally' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME -Protocol TCP
            ($result | Where-Object ProcessId -eq 99999).ProcessName | Should -Be '[Unknown]'
        }
    }

    Context 'Local execution - Port filter in scriptblock' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; OwningProcess = [uint32]100; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 443; OwningProcess = [uint32]100; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @([PSCustomObject]@{ Id = 100; ProcessName = 'nginx' })
            }
        }

        It 'Should filter by port locally' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME -Protocol TCP -Port 443
            $result | Should -HaveCount 1
            $result[0].LocalPort | Should -Be 443
        }
    }

    Context 'Local execution - ProcessName filter in scriptblock' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; OwningProcess = [uint32]100; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 443; OwningProcess = [uint32]200; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-Process' -MockWith {
                @(
                    [PSCustomObject]@{ Id = 100; ProcessName = 'httpd' },
                    [PSCustomObject]@{ Id = 200; ProcessName = 'nginx' }
                )
            }
        }

        It 'Should filter by process name locally' {
            $result = Get-ListeningPort -ComputerName $env:COMPUTERNAME -Protocol TCP -ProcessName 'httpd'
            $result | Should -HaveCount 1
            $result[0].ProcessName | Should -Be 'httpd'
        }
    }

}
