#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    # Test data: Create misencoded strings for testing
    $script:originalText = 'portal'
    $script:misencodedCyrillic = [System.Text.Encoding]::ASCII.GetString(
        [System.Text.Encoding]::GetEncoding('Cyrillic').GetBytes($script:originalText)
    )
}

Describe -Name 'ConvertFrom-MisencodedString' -Fixture {

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should have mandatory String parameter' -Test {
            $commandInfo = Get-Command -Name 'ConvertFrom-MisencodedString'
            $stringParam = $commandInfo.Parameters['String']
            $stringParam.Attributes.Mandatory | Should -Be $true
        }

        It -Name 'Should accept pipeline input for String parameter' -Test {
            $commandInfo = Get-Command -Name 'ConvertFrom-MisencodedString'
            $stringParam = $commandInfo.Parameters['String']
            $stringParam.Attributes.ValueFromPipeline | Should -Be $true
        }

        It -Name 'Should have optional SourceEncoding parameter with default value' -Test {
            $commandInfo = Get-Command -Name 'ConvertFrom-MisencodedString'
            $sourceParam = $commandInfo.Parameters['SourceEncoding']
            $sourceParam.Attributes.Mandatory | Should -Be $false
        }

        It -Name 'Should throw when String is null' -Test {
            { ConvertFrom-MisencodedString -String $null } | Should -Throw
        }
    }

    Context -Name 'When converting Cyrillic-misencoded strings' -Fixture {

        It -Name 'Should convert a single misencoded string back to original' -Test {
            $result = ConvertFrom-MisencodedString -String $script:misencodedCyrillic
            $result | Should -BeOfType ([string])
            $result | Should -Be $script:originalText
        }

        It -Name 'Should handle empty string without error' -Test {
            $result = ConvertFrom-MisencodedString -String ''
            $result | Should -BeExactly ''
        }

        It -Name 'Should process multiple strings from pipeline' -Test {
            $testStrings = @('test1', 'test2', 'test3')
            $misencoded = $testStrings | ForEach-Object -Process {
                [System.Text.Encoding]::ASCII.GetString(
                    [System.Text.Encoding]::GetEncoding('Cyrillic').GetBytes($_)
                )
            }
            $results = $misencoded | ConvertFrom-MisencodedString
            $results.Count | Should -Be 3
            $results[0] | Should -Be 'test1'
            $results[1] | Should -Be 'test2'
            $results[2] | Should -Be 'test3'
        }
    }

    Context -Name 'When using custom encodings' -Fixture {

        It -Name 'Should support custom source encoding' -Test {
            $originalUtf8 = 'cafe'
            $misencodedWin1252 = [System.Text.Encoding]::GetEncoding('windows-1252').GetString(
                [System.Text.Encoding]::UTF8.GetBytes($originalUtf8)
            )
            $result = ConvertFrom-MisencodedString -String $misencodedWin1252 -SourceEncoding 'windows-1252' -TargetEncoding 'utf-8'
            $result | Should -Be $originalUtf8
        }

        It -Name 'Should throw on invalid source encoding name' -Test {
            { ConvertFrom-MisencodedString -String 'test' -SourceEncoding 'invalid-encoding-name' } | Should -Throw
        }

        It -Name 'Should throw on invalid target encoding name' -Test {
            { ConvertFrom-MisencodedString -String 'test' -TargetEncoding 'invalid-encoding-name' } | Should -Throw
        }
    }

    Context -Name 'Verbose output' -Fixture {

        It -Name 'Should write verbose messages when Verbose is enabled' -Test {
            $verboseOutput = ConvertFrom-MisencodedString -String 'test' -Verbose 4>&1
            $verboseOutput | Should -Not -BeNullOrEmpty
            $verboseMessages = $verboseOutput | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseMessages.Count | Should -BeGreaterThan 0
        }
    }

    Context -Name 'Error handling' -Fixture {

        It -Name 'Should write error but not throw on encoding conversion failure' -Test {
            Mock -CommandName 'Write-Error' -MockWith {} -ModuleName 'PSWinOps'

            # Create a string with surrogate pair that will cause encoding issues
            $invalidString = [string][char]0xD800 + [char]0x0041

            $result = ConvertFrom-MisencodedString -String $invalidString -ErrorAction SilentlyContinue

            Should -Invoke -CommandName 'Write-Error' -Times 1 -Exactly -ModuleName 'PSWinOps'
        }
    }

    Context -Name 'OutputType compliance' -Fixture {

        It -Name 'Should return a string type' -Test {
            $result = ConvertFrom-MisencodedString -String 'test'
            $result | Should -BeOfType ([string])
        }
    }
}
