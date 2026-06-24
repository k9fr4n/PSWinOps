#Requires -Version 5.1

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Remove-StringDiacritic' {

    Context 'Diacritic removal' {

        It 'removes acute accent' {
            Remove-StringDiacritic -String 'café' | Should -Be 'cafe'
        }

        It 'removes cedilla' {
            Remove-StringDiacritic -String 'François' | Should -Be 'Francois'
        }

        It 'removes umlaut' {
            Remove-StringDiacritic -String 'Über' | Should -Be 'Uber'
        }

        It 'removes multiple diacritics in one string' {
            Remove-StringDiacritic -String 'Héllo Wörld' | Should -Be 'Hello World'
        }

        It 'removes tilde' {
            Remove-StringDiacritic -String 'señor' | Should -Be 'senor'
        }

        It 'removes ring above' {
            Remove-StringDiacritic -String 'Ångström' | Should -Be 'Angstrom'
        }

        It 'removes diaeresis' {
            Remove-StringDiacritic -String 'naïve' | Should -Be 'naive'
        }

        It 'handles a string with no diacritics unchanged' {
            Remove-StringDiacritic -String 'Hello World' | Should -Be 'Hello World'
        }

        It 'handles a string that is already pure ASCII unchanged' {
            Remove-StringDiacritic -String 'PSWinOps123' | Should -Be 'PSWinOps123'
        }
    }

    Context 'Pipeline support' {

        It 'accepts a single string from pipeline' {
            'François' | Remove-StringDiacritic | Should -Be 'Francois'
        }

        It 'processes multiple strings from pipeline' {
            $results = 'café', 'Über', 'señor' | Remove-StringDiacritic
            $results | Should -Be @('cafe', 'Uber', 'senor')
        }
    }

    Context 'Return type' {

        It 'returns a [string]' {
            $result = Remove-StringDiacritic -String 'café'
            $result | Should -BeOfType [string]
        }

        It 'does not return a PSCustomObject' {
            $result = Remove-StringDiacritic -String 'café'
            $result | Should -Not -BeOfType [System.Management.Automation.PSCustomObject]
        }
    }

    Context 'Parameter validation' {

        It 'throws on empty string' {
            { Remove-StringDiacritic -String '' } | Should -Throw
        }

        It 'throws when String is null' {
            { Remove-StringDiacritic -String $null } | Should -Throw
        }

        It 'String parameter is mandatory' {
            { Remove-StringDiacritic } | Should -Throw
        }
    }
}
