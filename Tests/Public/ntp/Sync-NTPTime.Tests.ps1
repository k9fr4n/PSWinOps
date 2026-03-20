#Requires -Version 5.1

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
}

Describe -Name 'Sync-NTPTime' -Fixture {

    BeforeAll {
        # Mock data: successful w32tm /resync output (English)
        $script:successOutput = [PSCustomObject]@{
            Output   = "Sending resync command to local computer`r`nThe command completed successfully."
            ExitCode = 0
        }

        # Mock data: failed w32tm /resync output
        $script:failureOutput = [PSCustomObject]@{
            Output   = 'The computer did not resync because no time data was available.'
            ExitCode = 1
        }
    }

    Context -Name 'When resyncing the local machine (happy path)' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            # Local path uses bare w32tm call (not Invoke-Command)
            Mock -CommandName 'w32tm' -ModuleName 'PSWinOps' -MockWith {
                $global:LASTEXITCODE = 0
                return "Sending resync command to local computer`r`nThe command completed successfully."
            }
            Mock -CommandName 'Out-String' -ModuleName 'PSWinOps' -MockWith {
                return ($input | ForEach-Object { "$_" }) -join "`r`n"
            }
        }

        It -Name 'Should return a success result for the local machine' -Test {
            $result = Sync-NTPTime
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Success | Should -BeTrue
            $result.ServiceRestarted | Should -BeFalse
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should call w32tm (not Invoke-Command) for local execution' -Test {
            Sync-NTPTime
            Should -Invoke -CommandName 'w32tm' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context -Name 'When resyncing a remote machine (happy path)' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:successOutput
            }
        }

        It -Name 'Should return a success result for the remote machine' -Test {
            $result = Sync-NTPTime -ComputerName 'REMOTE-SRV01'
            $result | Should -Not -BeNullOrEmpty
            $result.ComputerName | Should -Be 'REMOTE-SRV01'
            $result.Success | Should -BeTrue
            $result.ServiceRestarted | Should -BeFalse
        }

        It -Name 'Should invoke Invoke-Command with the remote ComputerName' -Test {
            Sync-NTPTime -ComputerName 'REMOTE-SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'REMOTE-SRV01'
            }
        }
    }

    Context -Name 'When pipeline input provides multiple machines' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:successOutput
            }
        }

        It -Name 'Should return one result per machine' -Test {
            $result = 'SRV01', 'SRV02', 'SRV03' | Sync-NTPTime
            $result.Count | Should -Be 3
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[1].ComputerName | Should -Be 'SRV02'
            $result[2].ComputerName | Should -Be 'SRV03'
        }

        It -Name 'Should report success for all machines' -Test {
            $result = 'SRV01', 'SRV02' | Sync-NTPTime
            $result | ForEach-Object { $_.Success | Should -BeTrue }
        }
    }

    Context -Name 'When -RestartService is specified' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:successOutput
            }
        }

        It -Name 'Should set ServiceRestarted to true and still succeed' -Test {
            $result = Sync-NTPTime -ComputerName 'REMOTE-SRV01' -RestartService
            $result.ServiceRestarted | Should -BeTrue
            $result.Success | Should -BeTrue
            $result.ComputerName | Should -Be 'REMOTE-SRV01'
        }

        It -Name 'Should call Invoke-Command twice (restart + resync)' -Test {
            Sync-NTPTime -ComputerName 'REMOTE-SRV01' -RestartService
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context -Name 'When w32tm resync reports failure' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:failureOutput
            }
        }

        It -Name 'Should return Success = false with the failure message' -Test {
            $result = Sync-NTPTime -ComputerName 'REMOTE-SRV01'
            $result.Success | Should -BeFalse
            $result.Message | Should -Match 'did not resync'
            $result.ComputerName | Should -Be 'REMOTE-SRV01'
        }
    }

    Context -Name 'When per-machine failure occurs' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:successOutput
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -ParameterFilter {
                $ComputerName -eq 'BADSERVER'
            } -MockWith {
                throw 'Connection refused'
            }
        }

        It -Name 'Should continue processing other machines after one fails' -Test {
            $result = Sync-NTPTime -ComputerName 'SRV01', 'BADSERVER', 'SRV02' -ErrorVariable syncError -ErrorAction SilentlyContinue
            $result.Count | Should -Be 2
            $result[0].ComputerName | Should -Be 'SRV01'
            $result[0].Success | Should -BeTrue
            $result[1].ComputerName | Should -Be 'SRV02'
            $result[1].Success | Should -BeTrue
        }

        It -Name 'Should write an error for the failing machine' -Test {
            $null = Sync-NTPTime -ComputerName 'SRV01', 'BADSERVER', 'SRV02' -ErrorVariable syncError -ErrorAction SilentlyContinue
            $syncError | Should -Not -BeNullOrEmpty
            "$syncError" | Should -Match 'BADSERVER'
        }
    }

    Context -Name 'When ShouldProcess is respected (-WhatIf)' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $true }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:successOutput
            }
        }

        It -Name 'Should NOT invoke any command with -WhatIf' -Test {
            Sync-NTPTime -ComputerName 'SRV01' -WhatIf
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should NOT invoke any command with -WhatIf and -RestartService' -Test {
            Sync-NTPTime -ComputerName 'SRV01' -RestartService -WhatIf
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context -Name 'When parameter validation fails' -Fixture {

        It -Name 'Should throw on empty string ComputerName' -Test {
            { Sync-NTPTime -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw on null ComputerName' -Test {
            { Sync-NTPTime -ComputerName $null } | Should -Throw
        }
    }

    Context -Name 'Elevation check - should throw when not administrator' -Fixture {

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith { return $false }
        }

        It -Name 'Should throw UnauthorizedAccessException when not elevated' -Test {
            { Sync-NTPTime -ErrorAction Stop } | Should -Throw -ExpectedMessage '*Administrator privileges*'
        }

        It -Name 'Should not call Invoke-Command when not elevated' -Test {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {}
            try { Sync-NTPTime -ErrorAction Stop } catch {}
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

}
