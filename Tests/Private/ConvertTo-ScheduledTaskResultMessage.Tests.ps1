#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'ConvertTo-ScheduledTaskResultMessage' {

    Context 'Known result codes' {

        It 'Should return Success for code 0' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 0 }
            $result | Should -Be 'Success (0x0)'
        }

        It 'Should return Incorrect function for code 1' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 1 }
            $result | Should -Be 'Incorrect function (0x1)'
        }

        It 'Should return File not found for code 2' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 2 }
            $result | Should -Be 'File not found (0x2)'
        }

        It 'Should return Environment incorrect for code 10' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 10 }
            $result | Should -Be 'Environment incorrect (0xA)'
        }

        It 'Should return Task is currently running for code 267009' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 267009 }
            $result | Should -Be 'Task is currently running (0x41301)'
        }

        It 'Should return Task has not yet run for code 267011' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 267011 }
            $result | Should -Be 'Task has not yet run (0x41303)'
        }

        It 'Should return Task terminated by user for code 267014' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 267014 }
            $result | Should -Be 'Task terminated by user (0x41306)'
        }

        It 'Should return Operator or user refused for code -2147020576' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode (-2147020576) }
            $result | Should -Be 'Operator or user refused (0x800710E0)'
        }

        It 'Should return Instance already running for code -2147216609' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode (-2147216609) }
            $result | Should -Be 'Instance already running (0x8004131F)'
        }
    }

    Context 'Unknown result codes' {

        It 'Should return Unknown with hex for unrecognized code' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 9999 }
            $result | Should -BeLike 'Unknown (0x*'
        }

        It 'Should return Unknown with correct hex format' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 255 }
            $result | Should -Be 'Unknown (0xFF)'
        }
    }

    Context 'Null input' {

        It 'Should return no run information for null ResultCode' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode $null }
            $result | Should -Be 'No run information available'
        }
    }

    Context 'Output type' {

        It 'Should return a string' {
            $result = & (Get-Module -Name $script:ModuleName) { ConvertTo-ScheduledTaskResultMessage -ResultCode 0 }
            $result | Should -BeOfType [string]
        }
    }
}
