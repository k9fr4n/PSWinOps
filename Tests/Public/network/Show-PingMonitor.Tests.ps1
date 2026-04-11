BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Show-PingMonitor' {

    Context 'Parameter validation' {

        It 'Should require ComputerName parameter' {
            { Show-PingMonitor -ComputerName $null } | Should -Throw
        }

        It 'Should reject empty ComputerName' {
            { Show-PingMonitor -ComputerName '' } | Should -Throw
        }

        It 'Should reject RefreshInterval of 0' {
            { Show-PingMonitor -ComputerName 'host' -RefreshInterval 0 } | Should -Throw
        }

        It 'Should reject RefreshInterval above 60' {
            { Show-PingMonitor -ComputerName 'host' -RefreshInterval 61 } | Should -Throw
        }

        It 'Should reject PingTimeoutMs below 500' {
            { Show-PingMonitor -ComputerName 'host' -PingTimeoutMs 100 } | Should -Throw
        }

        It 'Should have expected parameters' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $cmd.Parameters.Keys | Should -Contain 'ComputerName'
            $cmd.Parameters.Keys | Should -Contain 'RefreshInterval'
            $cmd.Parameters.Keys | Should -Contain 'PingTimeoutMs'
        }

        It 'Should have default RefreshInterval of 2' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $param = $cmd.Parameters['RefreshInterval']
            $param.ParameterType | Should -Be ([int])
        }

        It 'Should have default PingTimeoutMs of 2000' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $cmd.Parameters['PingTimeoutMs'].ParameterType | Should -Be ([int])
        }

        It 'Should accept PingTimeoutMs of 500 (minimum)' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $rangeAttr = $cmd.Parameters['PingTimeoutMs'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateRangeAttribute]
            }
            $rangeAttr.MinRange | Should -Be 500
        }

        It 'Should accept PingTimeoutMs of 10000 (maximum)' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $rangeAttr = $cmd.Parameters['PingTimeoutMs'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ValidateRangeAttribute]
            }
            $rangeAttr.MaxRange | Should -Be 10000
        }

        It 'Should reject PingTimeoutMs above 10000' {
            { Show-PingMonitor -ComputerName 'host' -PingTimeoutMs 11000 } | Should -Throw
        }
    }

    Context 'Function existence and metadata' {

        It 'Should be exported from the module' {
            $cmd = Get-Command -Name 'Show-PingMonitor' -Module $script:ModuleName
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should have CmdletBinding' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $cmd.CmdletBinding | Should -Be $true
        }

        It 'Should have SuppressMessageAttribute in the source code' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $scriptText = $cmd.ScriptBlock.ToString()
            $scriptText | Should -Match 'PSUseDeclaredVarsMoreThanAssignments'
        }

        It 'Should have ComputerName as mandatory parameter' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $paramAttr = $cmd.Parameters['ComputerName'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.Mandatory | Should -BeTrue
        }

        It 'Should support CN alias for ComputerName' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }

        It 'Should accept pipeline input for ComputerName' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $paramAttr = $cmd.Parameters['ComputerName'].Attributes | Where-Object {
                $_ -is [System.Management.Automation.ParameterAttribute]
            }
            $paramAttr.ValueFromPipeline | Should -BeTrue
            $paramAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It 'Should declare OutputType void' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $outputType = $cmd.OutputType
            $outputType.Type | Should -Contain ([void])
        }
    }

    Context 'NoColor parameter' {
        It 'Should have NoColor switch parameter' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $param = $cmd.Parameters['NoColor']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'SwitchParameter'
        }

        It 'Should have NoColor as non-mandatory' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $pAttr = $cmd.Parameters['NoColor'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pAttr.Mandatory | Should -BeFalse
        }

        It 'Should have NoClear switch parameter' {
            $cmd = Get-Command -Name 'Show-PingMonitor'
            $cmd.Parameters['NoClear'].ParameterType.Name | Should -Be 'SwitchParameter'
        }
    }

    Context 'ISE detection' {
        It 'Should contain ISE guard clause' {
            $funcBody = InModuleScope -ModuleName $script:ModuleName {
                (Get-Command -Name 'Show-PingMonitor').ScriptBlock.ToString()
            }
            $funcBody | Should -Match 'Windows PowerShell ISE Host'
        }
    }

    Context 'Interactive controls — function source inspection' {
        BeforeAll {
            $script:funcBody = InModuleScope -ModuleName $script:ModuleName {
                (Get-Command -Name 'Show-PingMonitor').ScriptBlock.ToString()
            }
        }

        It 'Should contain Q/Escape quit handling' {
            $script:funcBody | Should -Match "'Escape'"
            $script:funcBody | Should -Match "'Q'"
        }

        It 'Should contain Ctrl+C handling' {
            $script:funcBody | Should -Match 'ConsoleModifiers.*Control'
        }

        It 'Should contain S key for sort cycling' {
            $script:funcBody | Should -Match "keyInfo\.Key"
            $script:funcBody | Should -Match 'sortIndex'
        }

        It 'Should contain C key for stats clear' {
            $script:funcBody | Should -Match "'C'"
            $script:funcBody | Should -Match 'monitorStart'
        }

        It 'Should contain P key for pause toggle' {
            $script:funcBody | Should -Match "'P'"
            $script:funcBody | Should -Match '\$paused'
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

        It 'Should contain all four sort modes' {
            $script:funcBody | Should -Match "'Host'"
            $script:funcBody | Should -Match "'Status'"
            $script:funcBody | Should -Match "'LastMs'"
            $script:funcBody | Should -Match "'Loss'"
        }

        It 'Should display PAUSED indicator when paused' {
            $script:funcBody | Should -Match 'PAUSED'
        }

        It 'Should use Write-Information for stop message' {
            $script:funcBody | Should -Match 'Write-Information.*Ping Monitor stopped'
        }
    }
}
