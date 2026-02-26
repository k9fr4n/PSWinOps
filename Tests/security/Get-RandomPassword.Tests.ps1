#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    # Define test data
    $script:defaultLength = 16
    $script:defaultUpperCount = 2
    $script:defaultLowerCount = 2
    $script:defaultNumericCount = 2
    $script:defaultSpecialCount = 2

    $script:upperCharSet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $script:lowerCharSet = 'abcdefghijklmnopqrstuvwxyz'
    $script:numericCharSet = '0123456789'
    $script:specialCharSet = '@.+-=*!#$%&?'
}

Describe -Name 'Get-RandomPassword' -Fixture {

    Context -Name 'Module integration' -Fixture {

        It -Name 'Should be available after module import' -Test {
            Get-Command -Name 'Get-RandomPassword' -Module 'PSWinOps' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have correct OutputType attribute' -Test {
            $command = Get-Command -Name 'Get-RandomPassword'
            $command.OutputType.Name | Should -Contain 'System.String'
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should reject length less than 8' -Test {
            { Get-RandomPassword -Length 7 } | Should -Throw
        }

        It -Name 'Should reject negative count values' -Test {
            { Get-RandomPassword -UpperCount -1 } | Should -Throw
        }

        It -Name 'Should throw when total constraints exceed length' -Test {
            { Get-RandomPassword -Length 10 -UpperCount 5 -LowerCount 5 -NumericCount 5 -SpecialCount 5 } | Should -Throw -ExpectedMessage '*exceeds password length*'
        }

        It -Name 'Should throw when all character class counts are zero' -Test {
            { Get-RandomPassword -UpperCount 0 -LowerCount 0 -NumericCount 0 -SpecialCount 0 } | Should -Throw -ExpectedMessage '*at least one character class*'
        }
    }

    Context -Name 'Password generation with default parameters' -Fixture {

        It -Name 'Should return a string' -Test {
            $result = Get-RandomPassword
            $result | Should -BeOfType ([string])
        }

        It -Name 'Should return password of default length 16' -Test {
            $result = Get-RandomPassword
            $result.Length | Should -Be 16
        }

        It -Name 'Should contain at least 2 uppercase characters' -Test {
            $result = Get-RandomPassword
            $upperCount = ($result.ToCharArray() | Where-Object { $_ -cin $script:upperCharSet.ToCharArray() }).Count
            $upperCount | Should -BeGreaterOrEqual 2
        }

        It -Name 'Should contain at least 2 lowercase characters' -Test {
            $result = Get-RandomPassword
            $lowerCount = ($result.ToCharArray() | Where-Object { $_ -cin $script:lowerCharSet.ToCharArray() }).Count
            $lowerCount | Should -BeGreaterOrEqual 2
        }

        It -Name 'Should contain at least 2 numeric characters' -Test {
            $result = Get-RandomPassword
            $numericCount = ($result.ToCharArray() | Where-Object { $_ -cin $script:numericCharSet.ToCharArray() }).Count
            $numericCount | Should -BeGreaterOrEqual 2
        }

        It -Name 'Should contain at least 2 special characters' -Test {
            $result = Get-RandomPassword
            $specialCount = ($result.ToCharArray() | Where-Object { $_ -cin $script:specialCharSet.ToCharArray() }).Count
            $specialCount | Should -BeGreaterOrEqual 2
        }
    }

    Context -Name 'Password generation with custom parameters' -Fixture {

        It -Name 'Should return password of specified length' -Test {
            $result = Get-RandomPassword -Length 24
            $result.Length | Should -Be 24
        }

        It -Name 'Should meet custom uppercase requirement' -Test {
            $result = Get-RandomPassword -Length 20 -UpperCount 5
            $upperCount = ($result.ToCharArray() | Where-Object { $_ -cin $script:upperCharSet.ToCharArray() }).Count
            $upperCount | Should -BeGreaterOrEqual 5
        }

        It -Name 'Should generate password with zero special characters when SpecialCount is 0' -Test {
            $result = Get-RandomPassword -Length 16 -UpperCount 4 -LowerCount 4 -NumericCount 4 -SpecialCount 0
            $specialCount = ($result.ToCharArray() | Where-Object { $_ -cin $script:specialCharSet.ToCharArray() }).Count
            $specialCount | Should -Be 0
        }

        It -Name 'Should generate password with only numeric characters' -Test {
            $result = Get-RandomPassword -Length 12 -UpperCount 0 -LowerCount 0 -NumericCount 12 -SpecialCount 0
            $result | Should -Match '^\d+$'
        }
    }

    Context -Name 'Uniqueness and randomness' -Fixture {

        It -Name 'Should generate different passwords on consecutive calls' -Test {
            $password1 = Get-RandomPassword -Length 20
            $password2 = Get-RandomPassword -Length 20
            $password1 | Should -Not -Be $password2
        }

        It -Name 'Should generate 10 unique passwords' -Test {
            $passwords = 1..10 | ForEach-Object { Get-RandomPassword -Length 16 }
            $uniquePasswords = $passwords | Select-Object -Unique
            $uniquePasswords.Count | Should -Be 10
        }
    }

    Context -Name 'Error handling and edge cases' -Fixture {

        It -Name 'Should throw when constraints exceed length' -Test {
            { Get-RandomPassword -Length 8 -UpperCount 8 -LowerCount 2 -NumericCount 2 -SpecialCount 2 } | Should -Throw -ExpectedMessage '*exceeds password length*'
        }

        It -Name 'Should throw after exceeding max retries with impossible constraints' -Test {
            # Impossible: Length=8 with 8 uppercase + 1 lower + 1 numeric = 10 total required > 8 length
            { Get-RandomPassword -Length 8 -UpperCount 8 -LowerCount 1 -NumericCount 1 -SpecialCount 0 } | Should -Throw -ExpectedMessage '*exceeds password length*'
        }

        It -Name 'Should generate successfully with tight but valid constraints' -Test {
            $result = Get-RandomPassword -Length 8 -UpperCount 2 -LowerCount 2 -NumericCount 2 -SpecialCount 2
            $result.Length | Should -Be 8
        }

        It -Name 'Should accept MaxRetries parameter without error' -Test {
            $result = Get-RandomPassword -Length 16 -UpperCount 2 -LowerCount 2 -NumericCount 2 -SpecialCount 2 -MaxRetries 50
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 16
        }
    }

    Context -Name 'Verbose output' -Fixture {

        It -Name 'Should produce verbose output when -Verbose is specified' -Test {
            $verboseOutput = Get-RandomPassword -Length 16 -Verbose 4>&1
            $verboseOutput | Should -Not -BeNullOrEmpty
            $verboseOutput -join ' ' | Should -Match '\[Get-RandomPassword\].*Starting password generation|\[Get-RandomPassword\].*Character set size'
        }
    }
}

AfterAll {
    Remove-Module -Name 'PSWinOps' -Force -ErrorAction SilentlyContinue
}
