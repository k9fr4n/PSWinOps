#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Show-NetworkStatisticMonitor' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have OutputType void' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $cmd.OutputType.Type | Should -Contain ([void])
        }

        It 'Should have ComputerName parameter with pipeline support' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $param = $cmd.Parameters['ComputerName']
            $param | Should -Not -BeNullOrEmpty
            $pAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pAttr.ValueFromPipeline | Should -BeTrue
            $pAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It 'Should have Protocol parameter with ValidateSet TCP/UDP' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $param = $cmd.Parameters['Protocol']
            $param | Should -Not -BeNullOrEmpty
            $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $vs.ValidValues | Should -Contain 'TCP'
            $vs.ValidValues | Should -Contain 'UDP'
        }

        It 'Should have State parameter with ValidateSet' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $param = $cmd.Parameters['State']
            $param | Should -Not -BeNullOrEmpty
            $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $vs.ValidValues | Should -Contain 'Established'
            $vs.ValidValues | Should -Contain 'Listen'
        }

        It 'Should have RefreshInterval parameter with default value 2' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $param = $cmd.Parameters['RefreshInterval']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'Int32'
        }

        It 'Should have Credential parameter of type PSCredential' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $param = $cmd.Parameters['Credential']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'PSCredential'
        }

        It 'Should reject invalid Protocol value' {
            { Show-NetworkStatisticMonitor -Protocol 'ICMP' } | Should -Throw
        }

        It 'Should reject RefreshInterval of 0' {
            { Show-NetworkStatisticMonitor -RefreshInterval 0 } | Should -Throw
        }

        It 'Should reject RefreshInterval above 300' {
            { Show-NetworkStatisticMonitor -RefreshInterval 301 } | Should -Throw
        }

        It 'Should have ValidateRange on RefreshInterval' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $vr = $cmd.Parameters['RefreshInterval'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $vr | Should -Not -BeNullOrEmpty
        }

        It 'Should reject empty ComputerName' {
            { Show-NetworkStatisticMonitor -ComputerName '' } | Should -Throw
        }

        It 'Should reject null ComputerName' {
            { Show-NetworkStatisticMonitor -ComputerName $null } | Should -Throw
        }
    }

    Context 'Monitor loop - calls Get-NetworkConnection and displays results' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                return @(
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.NetworkConnection'
                        ComputerName  = $env:COMPUTERNAME
                        Protocol      = 'TCP'
                        LocalAddress  = '127.0.0.1'
                        LocalPort     = 80
                        RemoteAddress = '10.0.0.1'
                        RemotePort    = 54321
                        State         = 'Established'
                        ProcessId     = 1234
                        ProcessName   = 'nginx'
                        Timestamp     = Get-Date -Format 'o'
                    }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                # Break the loop after first iteration by throwing
                throw 'StopLoop'
            }
        }

        It 'Should not return pipeline objects' {
            $results = Show-NetworkStatisticMonitor -Protocol TCP -ErrorAction SilentlyContinue 2>$null
            $results | Should -BeNullOrEmpty
        }

        It 'Should call Get-NetworkConnection' {
            Show-NetworkStatisticMonitor -Protocol TCP -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should call Clear-Host' {
            Show-NetworkStatisticMonitor -Protocol TCP -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Clear-Host' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should call Start-Sleep with the RefreshInterval' {
            Show-NetworkStatisticMonitor -RefreshInterval 5 -Protocol TCP -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Start-Sleep' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Seconds -eq 5
            }
        }
    }

    Context 'Pipeline - collects all computers before starting loop' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                return @(
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.NetworkConnection'
                        ComputerName  = 'REMOTE01'
                        Protocol      = 'TCP'
                        LocalAddress  = '10.0.0.5'
                        LocalPort     = 80
                        RemoteAddress = '10.0.0.100'
                        RemotePort    = 49152
                        State         = 'Established'
                        ProcessId     = 100
                        ProcessName   = 'w3wp'
                        Timestamp     = Get-Date -Format 'o'
                    }
                )
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                throw 'StopLoop'
            }
        }

        It 'Should pass all piped computers to Get-NetworkConnection' {
            'REMOTE01', 'REMOTE02' | Show-NetworkStatisticMonitor -Protocol TCP -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $ComputerName.Count -eq 2
            }
        }
    }

    Context 'Filter parameters are forwarded to Get-NetworkConnection' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                return @()
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                throw 'StopLoop'
            }
        }

        It 'Should forward Protocol filter to Get-NetworkConnection' {
            Show-NetworkStatisticMonitor -Protocol TCP -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -ParameterFilter {
                $Protocol -contains 'TCP'
            }
        }

        It 'Should forward State filter to Get-NetworkConnection' {
            Show-NetworkStatisticMonitor -Protocol TCP -State Established -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -ParameterFilter {
                $State -contains 'Established'
            }
        }

        It 'Should forward ProcessName filter to Get-NetworkConnection' {
            Show-NetworkStatisticMonitor -ProcessName 'svchost' -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Get-NetworkConnection' -ModuleName $script:ModuleName -ParameterFilter {
                $ProcessName -eq 'svchost'
            }
        }
    }

    Context 'Empty results - shows no-match message' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Get-NetworkConnection' -MockWith {
                return @()
            }
            Mock -ModuleName $script:ModuleName -CommandName 'Clear-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Write-Host' -MockWith { }
            Mock -ModuleName $script:ModuleName -CommandName 'Start-Sleep' -MockWith {
                throw 'StopLoop'
            }
        }

        It 'Should display no-match message when no results' {
            Show-NetworkStatisticMonitor -Protocol TCP -ErrorAction SilentlyContinue 2>$null
            Should -Invoke -CommandName 'Write-Host' -ModuleName $script:ModuleName -ParameterFilter {
                $Object -eq '(No matching connections found)'
            }
        }
    }
}
