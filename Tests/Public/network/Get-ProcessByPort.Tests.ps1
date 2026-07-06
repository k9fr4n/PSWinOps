BeforeAll {
    # Stub Windows-only commands BEFORE module import so Pester can mock them
    if (-not (Get-Command -Name 'Get-NetTCPConnection' -ErrorAction SilentlyContinue)) {
        function global:Get-NetTCPConnection { param($State, $ErrorAction) }
    }
    if (-not (Get-Command -Name 'Get-NetUDPEndpoint' -ErrorAction SilentlyContinue)) {
        function global:Get-NetUDPEndpoint { param($ErrorAction) }
    }

    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-ProcessByPort' {

    Context 'Happy path - local TCP + UDP' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-CimInstance' -MockWith {
                @(
                    [PSCustomObject]@{ ProcessId = [uint32]1234; Name = 'httpd'; ExecutablePath = 'C:\httpd.exe'; CommandLine = 'httpd.exe -k start' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; RemoteAddress = '0.0.0.0'; RemotePort = 0; OwningProcess = [uint32]1234; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 53; OwningProcess = [uint32]1234 }
                )
            }
        }

        It 'Should return typed objects with ComputerName, Timestamp and PSTypeName' {
            $result = Get-ProcessByPort
            $result.Count | Should -Be 2
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ProcessPort'
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
            $result[0].Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should join TCP connection with owning process details' {
            $result = Get-ProcessByPort
            $tcpRow = $result | Where-Object Protocol -eq 'TCP'
            $tcpRow.ProcessName | Should -Be 'httpd'
            $tcpRow.ProcessPath | Should -Be 'C:\httpd.exe'
            $tcpRow.CommandLine | Should -Be 'httpd.exe -k start'
            $tcpRow.State | Should -Be 'Listen'
        }

        It 'Should include UDP endpoint with State/RemoteAddress/RemotePort as null' {
            $result = Get-ProcessByPort
            $udpRow = $result | Where-Object Protocol -eq 'UDP'
            $udpRow.State | Should -BeNullOrEmpty
            $udpRow.RemoteAddress | Should -BeNullOrEmpty
            $udpRow.RemotePort | Should -BeNullOrEmpty
        }
    }

    Context 'Port filter (local)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-CimInstance' -MockWith {
                @([PSCustomObject]@{ ProcessId = [uint32]100; Name = 'nginx'; ExecutablePath = 'C:\nginx.exe'; CommandLine = 'nginx.exe' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; RemoteAddress = $null; RemotePort = $null; OwningProcess = [uint32]100; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 443; RemoteAddress = $null; RemotePort = $null; OwningProcess = [uint32]100; State = 'Listen' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith { @() }
        }

        It 'Should narrow results to the requested LocalPort' {
            $result = Get-ProcessByPort -Port 443
            $result | Should -HaveCount 1
            $result[0].LocalPort | Should -Be 443
        }
    }

    Context 'State filter (local)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-CimInstance' -MockWith {
                @([PSCustomObject]@{ ProcessId = [uint32]100; Name = 'nginx'; ExecutablePath = 'C:\nginx.exe'; CommandLine = 'nginx.exe' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @(
                    [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 80; RemoteAddress = $null; RemotePort = $null; OwningProcess = [uint32]100; State = 'Listen' },
                    [PSCustomObject]@{ LocalAddress = '10.0.0.5'; LocalPort = 51000; RemoteAddress = '1.2.3.4'; RemotePort = 443; OwningProcess = [uint32]100; State = 'Established' }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith {
                @([PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 53; OwningProcess = [uint32]100 })
            }
        }

        It 'Should narrow TCP connections to the requested State and exclude UDP' {
            $result = Get-ProcessByPort -State Established
            $result | Should -HaveCount 1
            $result[0].Protocol | Should -Be 'TCP'
            $result[0].State | Should -Be 'Established'
        }
    }

    Context 'Process exited between queries (local)' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-CimInstance' -MockWith { @() }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetTCPConnection' -MockWith {
                @([PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 8080; RemoteAddress = $null; RemotePort = $null; OwningProcess = [uint32]9999; State = 'Listen' })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetUDPEndpoint' -MockWith { @() }
        }

        It 'Should keep the row with null process fields when the process is gone' {
            $result = Get-ProcessByPort -Port 8080
            $result | Should -HaveCount 1
            $result[0].ProcessId | Should -Be 9999
            $result[0].ProcessName | Should -BeNullOrEmpty
            $result[0].ProcessPath | Should -BeNullOrEmpty
            $result[0].CommandLine | Should -BeNullOrEmpty
        }
    }

    Context 'Explicit remote machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @(
                    [PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 3389; RemoteAddress = $null; RemotePort = $null; State = 'Listen'; ProcessId = 500; ProcessName = 'TermService'; ProcessPath = 'C:\svchost.exe'; CommandLine = 'svchost.exe -k termsvcs' }
                )
            }
        }

        It 'Should query the remote machine via Invoke-Command and stamp ComputerName' {
            $result = Get-ProcessByPort -ComputerName 'REMOTE01'
            $result.ComputerName | Should -Be 'REMOTE01'
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ProcessPort'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Pipeline of multiple machines' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 22; RemoteAddress = $null; RemotePort = $null; State = 'Listen'; ProcessId = 1; ProcessName = 'sshd'; ProcessPath = $null; CommandLine = $null })
            }
        }

        It 'Should query every machine received from the pipeline' {
            'SRV01', 'SRV02' | Get-ProcessByPort
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Credential propagation' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 3389; RemoteAddress = $null; RemotePort = $null; State = 'Listen'; ProcessId = 500; ProcessName = 'TermService'; ProcessPath = $null; CommandLine = $null })
            }
        }

        It 'Should forward the Credential to Invoke-Command' {
            $cred = [PSCredential]::new('user', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            Get-ProcessByPort -ComputerName 'REMOTE01' -Credential $cred
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ Protocol = 'TCP'; LocalAddress = '0.0.0.0'; LocalPort = 22; RemoteAddress = $null; RemotePort = $null; State = 'Listen'; ProcessId = 1; ProcessName = 'sshd'; ProcessPath = $null; CommandLine = $null })
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -ParameterFilter {
                $ComputerName -eq 'BADSERVER'
            } -MockWith { throw 'Connection refused' }
        }

        It 'Should continue processing remaining machines after one fails' {
            $result = Get-ProcessByPort -ComputerName 'SRV01', 'BADSERVER', 'SRV02' -ErrorAction SilentlyContinue
            $result.Count | Should -Be 2
        }

        It 'Should write an error for the failing machine' {
            $null = Get-ProcessByPort -ComputerName 'BADSERVER' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Should reject Port 0' {
            { Get-ProcessByPort -Port 0 } | Should -Throw
        }

        It 'Should reject Port above 65535' {
            { Get-ProcessByPort -Port 70000 } | Should -Throw
        }

        It 'Should reject an invalid State value' {
            { Get-ProcessByPort -State 'Closed' } | Should -Throw
        }

        It 'Should reject an empty ComputerName' {
            { Get-ProcessByPort -ComputerName '' } | Should -Throw
        }

        It 'Should support the CN alias for ComputerName' {
            $cmd = Get-Command -Name 'Get-ProcessByPort'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
    }
}
