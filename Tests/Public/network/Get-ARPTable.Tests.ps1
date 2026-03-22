BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'

    # Create stub functions so Pester can mock them on non-Windows platforms
    # Must be defined both globally and inside the module scope for scriptblock invocation
    $script:createdNetNeighborStub = $false
    $script:createdNetAdapterStub = $false
    if (-not (Get-Command -Name 'Get-NetNeighbor' -ErrorAction SilentlyContinue)) {
        function global:Get-NetNeighbor { }
        $script:createdNetNeighborStub = $true
    }
    if (-not (Get-Command -Name 'Get-NetAdapter' -ErrorAction SilentlyContinue)) {
        function global:Get-NetAdapter { }
        $script:createdNetAdapterStub = $true
    }

    # Re-import so the module picks up the newly available commands
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Use 'localhost' as fallback when $env:COMPUTERNAME is empty (Linux test environments)
    $script:localComputer = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'localhost' }
}

Describe 'Get-ARPTable' {

    Context 'Happy path - local machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetNeighbor' -MockWith {
                @(
                    [PSCustomObject]@{ IPAddress = '192.168.1.1'; LinkLayerAddress = 'AA-BB-CC-DD-EE-FF'; State = 'Reachable'; InterfaceIndex = 5; AddressFamily = 2 },
                    [PSCustomObject]@{ IPAddress = '192.168.1.100'; LinkLayerAddress = '11-22-33-44-55-66'; State = 'Stale'; InterfaceIndex = 5; AddressFamily = 2 }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith {
                @([PSCustomObject]@{ ifIndex = 5; Name = 'Ethernet' })
            }
        }

        It 'Should return ARP entries as structured objects' {
            $result = Get-ARPTable -ComputerName $script:localComputer
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'Should include PSTypeName PSWinOps.ArpEntry' {
            $result = Get-ARPTable -ComputerName $script:localComputer
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ArpEntry'
        }

        It 'Should include ComputerName and Timestamp' {
            $result = Get-ARPTable -ComputerName $script:localComputer
            $result[0].ComputerName | Should -Be $script:localComputer
            $result[0].Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should include IP and MAC addresses' {
            $result = Get-ARPTable -ComputerName $script:localComputer
            $result[0].IPAddress | Should -Be '192.168.1.1'
            $result[0].MACAddress | Should -Not -BeNullOrEmpty
        }

        It 'Should format MAC address with colon separators (XX:XX:XX:XX:XX:XX)' {
            $result = Get-ARPTable -ComputerName $script:localComputer
            $result[0].MACAddress | Should -Be 'AA:BB:CC:DD:EE:FF'
            $result[1].MACAddress | Should -Be '11:22:33:44:55:66'
        }

        It 'Should include interface alias' {
            $result = Get-ARPTable -ComputerName $script:localComputer
            $result[0].InterfaceAlias | Should -Be 'Ethernet'
        }
    }

    Context 'State filter' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetNeighbor' -MockWith {
                @(
                    [PSCustomObject]@{ IPAddress = '10.0.0.1'; LinkLayerAddress = 'AA-BB-11-22-33-44'; State = 'Reachable'; InterfaceIndex = 3; AddressFamily = 2 },
                    [PSCustomObject]@{ IPAddress = '10.0.0.2'; LinkLayerAddress = 'AA-BB-55-66-77-88'; State = 'Stale'; InterfaceIndex = 3; AddressFamily = 2 }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetAdapter' -MockWith { @() }
        }

        It 'Should filter by Reachable state' {
            $result = Get-ARPTable -ComputerName $script:localComputer -State Reachable
            $result.Count | Should -Be 1
            $result[0].State | Should -Be 'Reachable'
        }
    }

    Context 'Remote machine' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @(
                    [PSCustomObject]@{ IPAddress = '10.10.10.1'; LinkLayerAddr = 'AA:BB:CC:DD:EE:FF'; State = 'Reachable'; InterfaceAlias = 'Ethernet0'; InterfaceIndex = 2; AddressFamily = 'IPv4' }
                )
            }
        }

        It 'Should query remote machine via Invoke-Command' {
            $result = Get-ARPTable -ComputerName 'REMOTE01'
            $result | Should -Not -BeNullOrEmpty
            $result[0].ComputerName | Should -Be 'REMOTE01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    Context 'Pipeline input' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith {
                @([PSCustomObject]@{ IPAddress = '10.0.0.1'; LinkLayerAddr = 'AA:BB:CC:DD:EE:FF'; State = 'Reachable'; InterfaceAlias = 'Eth0'; InterfaceIndex = 1; AddressFamily = 'IPv4' })
            }
        }

        It 'Should accept multiple computers via pipeline' {
            $result = 'REMOTE01', 'REMOTE02' | Get-ARPTable
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    Context 'Error handling' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-Command' -MockWith { throw 'Connection refused' }
        }

        It 'Should write error and continue on per-machine failure' {
            $result = Get-ARPTable -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Should reject invalid State' {
            { Get-ARPTable -State 'InvalidState' } | Should -Throw
        }

        It 'Should reject invalid AddressFamily' {
            { Get-ARPTable -AddressFamily 'IPX' } | Should -Throw
        }
    }

    Context 'Integration' -Tag 'Integration' {

        It 'Should return ARP entries on a live Windows system' -Skip:(-not ($env:OS -eq 'Windows_NT')) {
            $result = Get-ARPTable
            $result | Should -Not -BeNullOrEmpty
            $result[0].IPAddress | Should -Match '\d+\.\d+\.\d+\.\d+'
        }
    }
}

AfterAll {
    # Clean up global stubs created for non-Windows platforms
    if ($script:createdNetNeighborStub) { Remove-Item -Path 'Function:\global:Get-NetNeighbor' -ErrorAction SilentlyContinue }
    if ($script:createdNetAdapterStub) { Remove-Item -Path 'Function:\global:Get-NetAdapter' -ErrorAction SilentlyContinue }
}
