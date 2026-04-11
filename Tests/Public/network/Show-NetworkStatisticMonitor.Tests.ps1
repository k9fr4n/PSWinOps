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

    Context 'NoColor parameter' {
        It 'Should have NoColor switch parameter' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $param = $cmd.Parameters['NoColor']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have NoColor as non-mandatory' {
            $cmd = Get-Command -Name 'Show-NetworkStatisticMonitor'
            $pAttr = $cmd.Parameters['NoColor'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pAttr.Mandatory | Should -BeFalse
        }
    }

    Context 'ISE detection' {
        It 'Should contain ISE guard clause' {
            $funcBody = InModuleScope -ModuleName $script:ModuleName {
                (Get-Command -Name 'Show-NetworkStatisticMonitor').ScriptBlock.ToString()
            }
            $funcBody | Should -Match 'Windows PowerShell ISE Host'
        }
    }

    Context 'Interactive controls — function source inspection' {
        BeforeAll {
            $script:funcBody = InModuleScope -ModuleName $script:ModuleName {
                (Get-Command -Name 'Show-NetworkStatisticMonitor').ScriptBlock.ToString()
            }
        }

        It 'Should contain Q/Escape quit handling' {
            $script:funcBody | Should -Match 'Escape'
            $script:funcBody | Should -Match "key\.Key\s+-eq\s+'Q'"
        }

        It 'Should contain Ctrl+C handling' {
            $script:funcBody | Should -Match 'ConsoleModifiers.*Control'
        }

        It 'Should contain S key for sort cycling' {
            $script:funcBody | Should -Match "key\.Key\s+-eq\s+'S'"
            $script:funcBody | Should -Match 'sortModeIndex'
        }

        It 'Should contain P key for pause toggle' {
            $script:funcBody | Should -Match "key\.Key\s+-eq\s+'P'"
            $script:funcBody | Should -Match '\$paused'
        }

        It 'Should contain R key for reverse sort' {
            $script:funcBody | Should -Match "key\.Key\s+-eq\s+'R'"
            $script:funcBody | Should -Match '\$sortDescending'
        }

        It 'Should use StringBuilder for frame rendering' {
            $script:funcBody | Should -Match 'System\.Text\.StringBuilder'
        }

        It 'Should use Console::Write for output' {
            $script:funcBody | Should -Match '\[Console\]::Write'
        }

        It 'Should restore console state in finally block' {
            $script:funcBody | Should -Match 'CursorVisible\s*=\s*\$previousCursorVisible'
            $script:funcBody | Should -Match 'TreatControlCAsInput\s*=\s*\$previousCtrlC'
        }

        It 'Should contain all five sort modes' {
            $script:funcBody | Should -Match "'Process'"
            $script:funcBody | Should -Match "'Protocol'"
            $script:funcBody | Should -Match "'State'"
            $script:funcBody | Should -Match "'LocalPort'"
            $script:funcBody | Should -Match "'RemoteAddr'"
        }

        It 'Should display PAUSED indicator when paused' {
            $script:funcBody | Should -Match 'PAUSED'
        }

        It 'Should use Write-Information for stop message' {
            $script:funcBody | Should -Match 'Write-Information.*Network Statistics Monitor stopped'
        }
    }

    Context 'ANSI color helpers' {
        BeforeAll {
            $script:funcBody = InModuleScope -ModuleName $script:ModuleName {
                (Get-Command -Name 'Show-NetworkStatisticMonitor').ScriptBlock.ToString()
            }
        }

        It 'Should have Get-ProtocolColor helper' {
            $script:funcBody | Should -Match 'function Get-ProtocolColor'
        }

        It 'Should have Get-StateColor helper' {
            $script:funcBody | Should -Match 'function Get-StateColor'
        }

        It 'Should color Established state green' {
            $script:funcBody | Should -Match "'Established'.*green"
        }

        It 'Should color CloseWait state red' {
            $script:funcBody | Should -Match "'CloseWait'.*red"
        }
    }
}
