#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockTask1 = [PSCustomObject]@{
        TaskName    = 'BackupDaily'
        TaskPath    = '\'
        State       = 'Ready'
        Author      = 'DOMAIN\admin'
        Description = 'Daily backup task'
    }

    $script:mockTask2 = [PSCustomObject]@{
        TaskName    = 'WindowsUpdate'
        TaskPath    = '\Microsoft\Windows\WindowsUpdate\'
        State       = 'Ready'
        Author      = 'Microsoft'
        Description = 'Windows Update task'
    }

    $script:mockTaskInfo = [PSCustomObject]@{
        LastRunTime    = [datetime]'2026-03-25 02:00:00'
        LastTaskResult = 0
        NextRunTime    = [datetime]'2026-03-26 02:00:00'
    }

}

Describe 'Get-ScheduledTaskDetail' {

    Context 'Happy path - local, default filters' {

        BeforeAll {
            Mock -CommandName 'Get-ScheduledTask' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockTask1, $script:mockTask2)
            }

            Mock -CommandName 'Get-ScheduledTaskInfo' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTaskInfo
            }

            Mock -CommandName 'ConvertTo-ScheduledTaskResultMessage' -ModuleName 'PSWinOps' -MockWith {
                return 'Success (0x0)'
            }

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = Get-ScheduledTaskDetail
        }

        It -Name 'Should return only non-Microsoft tasks' -Test {
            @($script:results).Count | Should -Be 1
        }

        It -Name 'Should return BackupDaily task' -Test {
            $script:results.TaskName | Should -Be 'BackupDaily'
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $script:results.PSObject.TypeNames | Should -Contain 'PSWinOps.ScheduledTaskDetail'
        }

        It -Name 'Should set State to Ready' -Test {
            $script:results.State | Should -Be 'Ready'
        }

        It -Name 'Should set correct LastRunTime' -Test {
            $script:results.LastRunTime | Should -Be ([datetime]'2026-03-25 02:00:00')
        }

        It -Name 'Should include a Timestamp' -Test {
            $script:results.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'IncludeMicrosoftTasks switch' {

        BeforeAll {
            Mock -CommandName 'Get-ScheduledTask' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockTask1, $script:mockTask2)
            }

            Mock -CommandName 'Get-ScheduledTaskInfo' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTaskInfo
            }

            Mock -CommandName 'ConvertTo-ScheduledTaskResultMessage' -ModuleName 'PSWinOps' -MockWith {
                return 'Success (0x0)'
            }

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = Get-ScheduledTaskDetail -IncludeMicrosoftTasks
        }

        It -Name 'Should return both tasks' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should include BackupDaily' -Test {
            @($script:results).TaskName | Should -Contain 'BackupDaily'
        }

        It -Name 'Should include WindowsUpdate' -Test {
            @($script:results).TaskName | Should -Contain 'WindowsUpdate'
        }
    }

    Context 'TaskName filter' {

        BeforeAll {
            Mock -CommandName 'Get-ScheduledTask' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockTask1, $script:mockTask2)
            }

            Mock -CommandName 'Get-ScheduledTaskInfo' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTaskInfo
            }

            Mock -CommandName 'ConvertTo-ScheduledTaskResultMessage' -ModuleName 'PSWinOps' -MockWith {
                return 'Success (0x0)'
            }

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = Get-ScheduledTaskDetail -TaskName 'Backup*' -IncludeMicrosoftTasks
        }

        It -Name 'Should return only matching task' -Test {
            @($script:results).Count | Should -Be 1
        }

        It -Name 'Should return BackupDaily' -Test {
            $script:results.TaskName | Should -Be 'BackupDaily'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Get-ScheduledTask' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockTask1)
            }

            Mock -CommandName 'Get-ScheduledTaskInfo' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTaskInfo
            }

            Mock -CommandName 'ConvertTo-ScheduledTaskResultMessage' -ModuleName 'PSWinOps' -MockWith {
                return 'Success (0x0)'
            }

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = Get-ScheduledTaskDetail -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should return valid ScheduledTaskDetail for remote machine' -Test {
            $script:results.PSObject.TypeNames | Should -Contain 'PSWinOps.ScheduledTaskDetail'
        }

    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Get-ScheduledTask' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockTask1)
            }

            Mock -CommandName 'Get-ScheduledTaskInfo' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockTaskInfo
            }

            Mock -CommandName 'ConvertTo-ScheduledTaskResultMessage' -ModuleName 'PSWinOps' -MockWith {
                return 'Success (0x0)'
            }

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            }
            $script:results = 'SRV01', 'SRV02' | Get-ScheduledTaskDetail
        }

        It -Name 'Should return results for each machine' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should return distinct ComputerName per machine' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }

    }

    Context 'Per-machine failure continues' {

        BeforeAll {
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-ScheduledTaskDetail -ComputerName 'BADSERVER' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADSERVER*'
        }

        It -Name 'Should not throw with default ErrorAction' -Test {
            { Get-ScheduledTaskDetail -ComputerName 'BADSERVER' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-ScheduledTaskDetail -ComputerName 'BADSERVER' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Get-ScheduledTaskDetail -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-ScheduledTaskDetail -ComputerName $null } | Should -Throw
        }

        It -Name 'Should have CmdletBinding attribute' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-ScheduledTaskDetail'
            $script:cmdInfo.CmdletBinding | Should -BeTrue
        }
    }

    Context 'HRESULT mapping - ConvertTo-ScheduledTaskResultMessage' {

        It -Name 'Should return success message for code 0' -Test {
            $script:result = & (Get-Module -Name 'PSWinOps') {
                ConvertTo-ScheduledTaskResultMessage -ResultCode 0
            }
            $script:result | Should -Be 'Success (0x0)'
        }

        It -Name 'Should return not-yet-run message for code 267011' -Test {
            $script:result = & (Get-Module -Name 'PSWinOps') {
                ConvertTo-ScheduledTaskResultMessage -ResultCode 267011
            }
            $script:result | Should -Be 'Task has not yet run (0x41303)'
        }

        It -Name 'Should return operator-refused message for code -2147020576' -Test {
            $script:result = & (Get-Module -Name 'PSWinOps') {
                ConvertTo-ScheduledTaskResultMessage -ResultCode (-2147020576)
            }
            $script:result | Should -Be 'Operator or user refused (0x800710E0)'
        }

        It -Name 'Should handle null result code gracefully' -Test {
            $script:result = & (Get-Module -Name 'PSWinOps') {
                ConvertTo-ScheduledTaskResultMessage -ResultCode $null
            }
            $script:result | Should -Be 'No run information available'
        }

        It -Name 'Should return unknown message for unmapped code' -Test {
            $script:result = & (Get-Module -Name 'PSWinOps') {
                ConvertTo-ScheduledTaskResultMessage -ResultCode 99999
            }
            $script:result | Should -BeLike 'Unknown*'
        }
    }
}
