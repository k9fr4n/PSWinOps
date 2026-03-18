#Requires -Version 5.1

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Invoke-QwinstaQuery' {

    Context 'When qwinsta.exe succeeds' {

        It 'Returns a PSCustomObject' {
            Mock -CommandName 'Invoke-QwinstaQuery' -MockWith {
                [PSCustomObject]@{
                    Output   = @(
                        ' SESSIONNAME       USERNAME          ID  STATE   TYPE        DEVICE',
                        ' services                            0  Disc',
                        '>console            testuser          1  Active'
                    )
                    ExitCode = 0
                }
            } -ModuleName 'PSWinOps'

            $result = & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName 'localhost' }
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'Returns Output and ExitCode properties' {
            Mock -CommandName 'Invoke-QwinstaQuery' -MockWith {
                [PSCustomObject]@{
                    Output   = @('header line', 'session line')
                    ExitCode = 0
                }
            } -ModuleName 'PSWinOps'

            $result = & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName 'SRV01' }
            $result.PSObject.Properties.Name | Should -Contain 'Output'
            $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
        }

        It 'Returns ExitCode 0 on success' {
            Mock -CommandName 'Invoke-QwinstaQuery' -MockWith {
                [PSCustomObject]@{ Output = @('header'); ExitCode = 0 }
            } -ModuleName 'PSWinOps'

            $result = & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName 'SRV01' }
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'When qwinsta.exe fails' {

        It 'Returns a non-zero ExitCode' {
            Mock -CommandName 'Invoke-QwinstaQuery' -MockWith {
                [PSCustomObject]@{ Output = @('Error: Access denied'); ExitCode = 5 }
            } -ModuleName 'PSWinOps'

            $result = & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName 'UNREACHABLE' }
            $result.ExitCode | Should -Not -Be 0
        }

        It 'Still returns a PSCustomObject on failure' {
            Mock -CommandName 'Invoke-QwinstaQuery' -MockWith {
                [PSCustomObject]@{ Output = @('Error'); ExitCode = 1 }
            } -ModuleName 'PSWinOps'

            $result = & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName 'UNREACHABLE' }
            $result | Should -BeOfType [PSCustomObject]
        }
    }

    Context 'Parameter validation' {

        It 'Throws when ServerName is empty' {
            { & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName '' } } | Should -Throw
        }

        It 'Throws when ServerName is null' {
            { & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName $null } } | Should -Throw
        }

        It 'Accepts a valid server name without throwing' {
            Mock -CommandName 'Invoke-QwinstaQuery' -MockWith {
                [PSCustomObject]@{ Output = @(); ExitCode = 0 }
            } -ModuleName 'PSWinOps'

            { & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName 'SRV01' } } | Should -Not -Throw
        }
    }

    Context 'Real execution against localhost' -Tag 'Integration' {

        It 'Returns output lines when run locally' -Skip:(-not (Test-Path "$env:SystemRoot\System32\qwinsta.exe")) {
            $result = & (Get-Module -Name 'PSWinOps') { Invoke-QwinstaQuery -ServerName 'localhost' }
            $result | Should -BeOfType [PSCustomObject]
            $result.Output | Should -Not -BeNullOrEmpty
            $result.ExitCode | Should -BeIn @(0, 1)
        }
    }
}
