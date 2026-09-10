#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Set-DisplayLanguage' {

    Context 'Local happy path' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    PackAction        = 'Installed'
                    UserLanguageSet   = $true
                    AppliedToSystem   = $false
                    AppliedToNewUsers = $false
                    Status            = 'Success'
                }
            }
            $script:result = Set-DisplayLanguage -Language 'en-US' -Confirm:$false
        }

        It -Name 'Should return PSWinOps.DisplayLanguageResult type' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.DisplayLanguageResult'
        }

        It -Name 'Should set ComputerName to the local computer' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should return the requested Language and pack/user status' -Test {
            $script:result.Language | Should -Be 'en-US'
            $script:result.PackAction | Should -Be 'Installed'
            $script:result.UserLanguageSet | Should -Be $true
            $script:result.Status | Should -Be 'Success'
        }

        It -Name 'Should format Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $script:result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }

    Context 'Explicit remote machine with Credential' {

        BeforeAll {
            $script:cred = [System.Management.Automation.PSCredential]::new('user', (ConvertTo-SecureString -String 'p@ss' -AsPlainText -Force))
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    PackAction        = 'AlreadyPresent'
                    UserLanguageSet   = $true
                    AppliedToSystem   = $false
                    AppliedToNewUsers = $false
                    Status            = 'Success'
                }
            }
            $script:remoteResult = Set-DisplayLanguage -Language 'fr-FR' -ComputerName 'SRV01' -Credential $script:cred -Confirm:$false
        }

        It -Name 'Should forward ComputerName and Credential to Invoke-RemoteOrLocal' -Test {
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Scope Context -ParameterFilter {
                $ComputerName -eq 'SRV01' -and $Credential -eq $script:cred
            }
        }

        It -Name 'Should set ComputerName to SRV01 on the returned object' -Test {
            $script:remoteResult.ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline of multiple machine names' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    PackAction        = 'AlreadyPresent'
                    UserLanguageSet   = $true
                    AppliedToSystem   = $false
                    AppliedToNewUsers = $false
                    Status            = 'Success'
                }
            }
            $script:pipelineResults = 'SRV01', 'SRV02' | Set-DisplayLanguage -Language 'en-US' -Confirm:$false
        }

        It -Name 'Should return one object per machine' -Test {
            @($script:pipelineResults).Count | Should -Be 2
            $script:pipelineResults[0].ComputerName | Should -Be 'SRV01'
            $script:pipelineResults[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'NoInstall skips a missing language pack' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    PackAction        = 'Skipped'
                    UserLanguageSet   = $false
                    AppliedToSystem   = $false
                    AppliedToNewUsers = $false
                    Status            = 'Skipped'
                }
            }
            $script:skipResult = Set-DisplayLanguage -Language 'en-US' -NoInstall -Confirm:$false
        }

        It -Name 'Should return Skipped status without setting the user language' -Test {
            $script:skipResult.PackAction | Should -Be 'Skipped'
            $script:skipResult.UserLanguageSet | Should -Be $false
            $script:skipResult.Status | Should -Be 'Skipped'
        }
    }

    Context 'ApplyToSystem requires administrator privileges' {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $false }
        }

        It -Name 'Should throw a terminating error when not elevated' -Test {
            { Set-DisplayLanguage -Language 'en-US' -ApplyToSystem -Confirm:$false } | Should -Throw
        }
    }

    Context 'ApplyToSystem propagates settings when elevated' {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { $true }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    PackAction        = 'AlreadyPresent'
                    UserLanguageSet   = $true
                    AppliedToSystem   = $true
                    AppliedToNewUsers = $false
                    Status            = 'Success'
                }
            }
            $script:systemResult = Set-DisplayLanguage -Language 'en-US' -ApplyToSystem -Confirm:$false
        }

        It -Name 'Should reflect AppliedToSystem on the returned object' -Test {
            $script:systemResult.AppliedToSystem | Should -Be $true
        }
    }

    Context 'WhatIf writes nothing' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return [PSCustomObject]@{
                    PackAction        = 'Installed'
                    UserLanguageSet   = $true
                    AppliedToSystem   = $false
                    AppliedToNewUsers = $false
                    Status            = 'Success'
                }
            }
            $script:whatIfResult = Set-DisplayLanguage -Language 'en-US' -WhatIf
        }

        It -Name 'Should not invoke Invoke-RemoteOrLocal' -Test {
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Scope Context
        }

        It -Name 'Should not return any output object' -Test {
            $script:whatIfResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should reject a language tag that does not match the BCP-47 pattern' -Test {
            { Set-DisplayLanguage -Language 'english' -Confirm:$false } | Should -Throw
        }

        It -Name 'Should reject a null or empty ComputerName' -Test {
            { Set-DisplayLanguage -Language 'en-US' -ComputerName '' -Confirm:$false } | Should -Throw
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw "The 'LanguagePackManagement' module is not available on this computer."
                }
                return [PSCustomObject]@{
                    PackAction        = 'AlreadyPresent'
                    UserLanguageSet   = $true
                    AppliedToSystem   = $false
                    AppliedToNewUsers = $false
                    Status            = 'Success'
                }
            }
        }

        It -Name 'Should write an error for the failing machine and continue to the next one' -Test {
            $script:isolationResults = 'SRV01', 'SRV02' | Set-DisplayLanguage -Language 'en-US' -Confirm:$false -ErrorVariable errVar -ErrorAction SilentlyContinue
            $errVar | Should -Not -BeNullOrEmpty
            @($script:isolationResults).Count | Should -Be 1
            $script:isolationResults[0].ComputerName | Should -Be 'SRV02'
        }
    }
}
