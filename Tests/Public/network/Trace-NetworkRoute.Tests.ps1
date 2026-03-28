BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Trace-NetworkRoute' {

    Context 'Happy path - route reaches destination' {

        BeforeEach {
            # Mock DNS resolution
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                $hopNumber = 0
                $mockPing = [PSCustomObject]@{}
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                    param($target, $timeout, $buffer, $options)
                    $ttl = $options.Ttl
                    if ($ttl -lt 3) {
                        [PSCustomObject]@{
                            Status = [System.Net.NetworkInformation.IPStatus]::TtlExpired
                            RoundtripTime = $ttl * 5
                            Address = [System.Net.IPAddress]::Parse("10.0.0.$ttl")
                        }
                    } else {
                        [PSCustomObject]@{
                            Status = [System.Net.NetworkInformation.IPStatus]::Success
                            RoundtripTime = 15
                            Address = [System.Net.IPAddress]::Parse('8.8.8.8')
                        }
                    }
                }.GetNewClosure()
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mockPing
            } -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
        }

        It 'Should return hop-by-hop results' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -SkipNameResolution
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3  # 2 intermediate + 1 destination
        }

        It 'Should include PSTypeName PSWinOps.TraceRouteHop' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -SkipNameResolution
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.TraceRouteHop'
        }

        It 'Should have incrementing hop numbers' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -SkipNameResolution
            $result[0].Hop | Should -Be 1
            $result[1].Hop | Should -Be 2
            $result[2].Hop | Should -Be 3
        }

        It 'Should mark final hop as Reached' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -SkipNameResolution
            $result[-1].Status | Should -Be 'Reached'
        }

        It 'Should mark intermediate hops as Hop' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -SkipNameResolution
            $result[0].Status | Should -Be 'Hop'
        }

        It 'Should include latency stats per hop' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -SkipNameResolution
            $result[0].AvgMs | Should -Not -BeNullOrEmpty
        }

        It 'Should include Destination and Timestamp' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -SkipNameResolution
            $result[0].Destination | Should -Be '8.8.8.8'
            $result[0].Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Timeout hops' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                $mockPing = [PSCustomObject]@{}
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                    param($target, $timeout, $buffer, $options)
                    [PSCustomObject]@{
                        Status        = [System.Net.NetworkInformation.IPStatus]::TimedOut
                        RoundtripTime = 0
                        Address       = $null
                    }
                }
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mockPing
            } -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
        }

        It 'Should show * for timed out hops' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -MaxHops 3 -SkipNameResolution 3>$null
            $result | ForEach-Object { $_.IPAddress | Should -Be '*' }
            $result | ForEach-Object { $_.Status | Should -Be 'TimedOut' }
        }

        It 'Should emit a warning when destination not reached' {
            $result = Trace-NetworkRoute -ComputerName '8.8.8.8' -MaxHops 2 -SkipNameResolution 3>&1
            $warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Pipeline input' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                $mockPing = [PSCustomObject]@{}
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Send' -Value {
                    param($target, $timeout, $buffer, $options)
                    [PSCustomObject]@{
                        Status = [System.Net.NetworkInformation.IPStatus]::Success
                        RoundtripTime = 5
                        Address = [System.Net.IPAddress]::Parse($target)
                    }
                }
                $mockPing | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mockPing
            } -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
        }

        It 'Should accept pipeline input' {
            $result = '8.8.8.8', '1.1.1.1' | Trace-NetworkRoute -MaxHops 1 -SkipNameResolution
            $destinations = $result | Select-Object -ExpandProperty Destination -Unique
            $destinations.Count | Should -Be 2
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty ComputerName' {
            { Trace-NetworkRoute -ComputerName '' } | Should -Throw
        }

        It 'Should reject MaxHops of 0' {
            { Trace-NetworkRoute -ComputerName '8.8.8.8' -MaxHops 0 } | Should -Throw
        }

        It 'Should reject MaxHops above 128' {
            { Trace-NetworkRoute -ComputerName '8.8.8.8' -MaxHops 129 } | Should -Throw
        }

        It 'Should reject TimeoutMs below 500' {
            { Trace-NetworkRoute -ComputerName '8.8.8.8' -TimeoutMs 100 } | Should -Throw
        }
    }

    Context 'Integration' -Tag 'Integration' {

        It 'Should trace route to localhost' -Skip:(-not ($env:OS -eq 'Windows_NT')) {
            $result = Trace-NetworkRoute -ComputerName 'localhost' -MaxHops 5
            $result | Should -Not -BeNullOrEmpty
        }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'Verbose output' {
        BeforeAll {
            Mock -ModuleName 'PSWinOps' -CommandName 'Invoke-Command' -MockWith { return @() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Trace-NetworkRoute -ComputerName '8.8.8.8' -Verbose -ErrorAction SilentlyContinue 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Trace-NetworkRoute -ComputerName '8.8.8.8' -Verbose -ErrorAction SilentlyContinue 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Trace-NetworkRoute'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Trace-NetworkRoute' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Trace-NetworkRoute' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Trace-NetworkRoute' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
    }
}