#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Variables are used across Pester scopes via script: prefix'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'

    # Standard mock profiles for reuse across contexts
    $script:mockOldDate = (Get-Date).AddDays(-120)
    $script:mockRecentDate = (Get-Date).AddDays(-10)
    $script:mockProfiles = @(
        @{
            SID         = 'S-1-5-21-1234-5678-9012-1001'
            LocalPath   = 'C:\Users\john.doe'
            LastUseTime = $script:mockOldDate
            Loaded      = $false
            SizeMB      = [double]512.5
        },
        @{
            SID         = 'S-1-5-21-1234-5678-9012-1002'
            LocalPath   = 'C:\Users\jane.smith'
            LastUseTime = $script:mockRecentDate
            Loaded      = $false
            SizeMB      = [double]256.3
        },
        @{
            SID         = 'S-1-5-21-1234-5678-9012-1003'
            LocalPath   = 'C:\Users\svc_backup'
            LastUseTime = $script:mockOldDate
            Loaded      = $false
            SizeMB      = [double]10.0
        },
        @{
            SID         = 'S-1-5-21-1234-5678-9012-1004'
            LocalPath   = 'C:\Users\admin'
            LastUseTime = $script:mockOldDate
            Loaded      = $true
            SizeMB      = [double]1024.0
        }
    )
}

Describe 'Remove-UserProfile' {

    Context 'Parameter validation' {
        BeforeAll {
            $script:commandInfo = Get-Command -Name 'Remove-UserProfile' -Module $script:ModuleName
        }

        It -Name 'Should have CmdletBinding with SupportsShouldProcess' -Test {
            $script:commandInfo.CmdletBinding | Should -BeTrue
        }

        It -Name 'Should have ConfirmImpact set to High' -Test {
            $meta = [System.Management.Automation.CommandMetadata]::new($script:commandInfo)
            $meta.ConfirmImpact | Should -Be 'High'
        }

        It -Name 'Should have OutputType PSWinOps.UserProfileRemoval' -Test {
            $script:commandInfo.OutputType.Name | Should -Contain 'PSWinOps.UserProfileRemoval'
        }

        It -Name 'Should have ComputerName parameter with pipeline support' -Test {
            $param = $script:commandInfo.Parameters['ComputerName']
            $param | Should -Not -BeNullOrEmpty
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.ValueFromPipeline | Should -BeTrue
            $attr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It -Name 'Should have ComputerName aliases CN, Name, DNSHostName' -Test {
            $param = $script:commandInfo.Parameters['ComputerName']
            $param.Aliases | Should -Contain 'CN'
            $param.Aliases | Should -Contain 'Name'
            $param.Aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should have OlderThanDays with ValidateRange 1-3650' -Test {
            $param = $script:commandInfo.Parameters['OlderThanDays']
            $param | Should -Not -BeNullOrEmpty
            $range = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $range.MinRange | Should -Be 1
            $range.MaxRange | Should -Be 3650
        }

        It -Name 'Should have ExcludeUser parameter' -Test {
            $param = $script:commandInfo.Parameters['ExcludeUser']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.FullName | Should -Be 'System.String[]'
        }

        It -Name 'Should have SkipSizeCalculation switch' -Test {
            $param = $script:commandInfo.Parameters['SkipSizeCalculation']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -BeTrue
        }

        It -Name 'Should have Credential parameter' -Test {
            $param = $script:commandInfo.Parameters['Credential']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'PSCredential'
        }

        It -Name 'Should have Force switch' -Test {
            $param = $script:commandInfo.Parameters['Force']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -BeTrue
        }

        It -Name 'Should reject OlderThanDays of 0' -Test {
            { Remove-UserProfile -OlderThanDays 0 -WhatIf } | Should -Throw
        }

        It -Name 'Should reject empty ComputerName' -Test {
            { Remove-UserProfile -ComputerName '' -WhatIf } | Should -Throw
        }

        It -Name 'Should reject null ComputerName' -Test {
            { Remove-UserProfile -ComputerName $null -WhatIf } | Should -Throw
        }
    }

    Context 'Comment-based help' {
        BeforeAll {
            $script:helpInfo = Get-Help -Name 'Remove-UserProfile' -Full
        }

        It -Name 'Should have a synopsis' -Test {
            $script:helpInfo.Synopsis.Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a description' -Test {
            ($script:helpInfo.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have at least 3 examples' -Test {
            $script:helpInfo.Examples.Example.Count | Should -BeGreaterOrEqual 3
        }

        It -Name 'Should have OUTPUTS section' -Test {
            ($script:helpInfo.returnValues | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have Author in NOTES' -Test {
            ($script:helpInfo.alertSet | Out-String) | Should -Match 'Franck SALLET'
        }

        It -Name 'Should document all parameters' -Test {
            $expectedParams = @('ComputerName', 'OlderThanDays', 'ExcludeUser', 'SkipSizeCalculation', 'Credential', 'Force')
            foreach ($paramName in $expectedParams) {
                $script:helpInfo.Parameters.Parameter |
                    Where-Object -FilterScript { $_.Name -eq $paramName } |
                    Should -Not -BeNullOrEmpty -Because "Parameter '$paramName' should be documented"
            }
        }
    }

    Context 'Happy path — local with WhatIf' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:mockProfiles)
            }
        }

        It -Name 'Should return WhatIf results for eligible profiles' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            $results | Should -Not -BeNullOrEmpty
            # john.doe (old, not loaded) and svc_backup (old, not loaded) are eligible
            # jane.smith is recent (10 days) — skipped
            # admin is old but loaded — Skipped status
            $whatIfResults = $results | Where-Object { $_.Status -eq 'WhatIf' }
            $whatIfResults.Count | Should -BeGreaterOrEqual 1
        }

        It -Name 'Should have correct PSTypeName' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            foreach ($r in $results) {
                $r.PSTypeNames[0] | Should -Be 'PSWinOps.UserProfileRemoval'
            }
        }

        It -Name 'Should include ComputerName and Timestamp' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            foreach ($r in $results) {
                $r.ComputerName | Should -Not -BeNullOrEmpty
                $r.Timestamp | Should -Not -BeNullOrEmpty
            }
        }

        It -Name 'Should include expected output properties' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            $first = $results[0]
            $first.PSObject.Properties.Name | Should -Contain 'UserName'
            $first.PSObject.Properties.Name | Should -Contain 'LocalPath'
            $first.PSObject.Properties.Name | Should -Contain 'SID'
            $first.PSObject.Properties.Name | Should -Contain 'LastUseTime'
            $first.PSObject.Properties.Name | Should -Contain 'ProfileSizeMB'
            $first.PSObject.Properties.Name | Should -Contain 'DaysInactive'
            $first.PSObject.Properties.Name | Should -Contain 'Status'
            $first.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            foreach ($r in $results) {
                $r.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
            }
        }
    }

    Context 'Happy path — remote single machine' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:mockProfiles)
            }
        }

        It -Name 'Should target remote machine' -Test {
            $results = @(Remove-UserProfile -ComputerName 'SRV01' -OlderThanDays 90 -WhatIf)
            $results | Should -Not -BeNullOrEmpty
            $results[0].ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline — multiple machines' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:mockProfiles)
            }
        }

        It -Name 'Should process all machines from pipeline' -Test {
            $results = @('SRV01', 'SRV02' | Remove-UserProfile -OlderThanDays 90 -WhatIf)
            $results | Should -Not -BeNullOrEmpty
            $machines = $results | Select-Object -ExpandProperty ComputerName -Unique
            $machines | Should -Contain 'SRV01'
            $machines | Should -Contain 'SRV02'
        }
    }

    Context 'System profile exclusion' {
        BeforeAll {
            $script:systemProfiles = @(
                @{
                    SID         = 'S-1-5-18'
                    LocalPath   = 'C:\WINDOWS\system32\config\systemprofile'
                    LastUseTime = $script:mockOldDate
                    Loaded      = $false
                    SizeMB      = [double]1.0
                },
                @{
                    SID         = 'S-1-5-19'
                    LocalPath   = 'C:\WINDOWS\ServiceProfiles\LocalService'
                    LastUseTime = $script:mockOldDate
                    Loaded      = $false
                    SizeMB      = [double]1.0
                },
                @{
                    SID         = 'S-1-5-20'
                    LocalPath   = 'C:\WINDOWS\ServiceProfiles\NetworkService'
                    LastUseTime = $script:mockOldDate
                    Loaded      = $false
                    SizeMB      = [double]1.0
                },
                @{
                    SID         = 'S-1-5-21-1234-5678-9012-1001'
                    LocalPath   = 'C:\Users\john.doe'
                    LastUseTime = $script:mockOldDate
                    Loaded      = $false
                    SizeMB      = [double]100.0
                }
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:systemProfiles)
            }
        }

        It -Name 'Should never return system profiles' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            $systemResults = $results | Where-Object {
                $_.SID -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')
            }
            $systemResults | Should -BeNullOrEmpty
        }

        It -Name 'Should still return eligible non-system profiles' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            $results | Where-Object { $_.UserName -eq 'john.doe' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ExcludeUser filtering' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:mockProfiles)
            }
        }

        It -Name 'Should exclude exact username match' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -ExcludeUser 'john.doe' -WhatIf)
            $results | Where-Object { $_.UserName -eq 'john.doe' } | Should -BeNullOrEmpty
        }

        It -Name 'Should exclude wildcard patterns' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -ExcludeUser 'svc_*' -WhatIf)
            $results | Where-Object { $_.UserName -eq 'svc_backup' } | Should -BeNullOrEmpty
        }

        It -Name 'Should exclude multiple patterns' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -ExcludeUser 'john.doe', 'svc_*' -WhatIf)
            $results | Where-Object { $_.UserName -eq 'john.doe' } | Should -BeNullOrEmpty
            $results | Where-Object { $_.UserName -eq 'svc_backup' } | Should -BeNullOrEmpty
        }
    }

    Context 'Loaded profile handling' {
        BeforeAll {
            $script:loadedProfile = @(
                @{
                    SID         = 'S-1-5-21-1234-5678-9012-9999'
                    LocalPath   = 'C:\Users\active.user'
                    LastUseTime = $script:mockOldDate
                    Loaded      = $true
                    SizeMB      = [double]500.0
                }
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:loadedProfile)
            }
        }

        It -Name 'Should return Skipped status for loaded profiles' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -Confirm:$false)
            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'Skipped'
            $results[0].ErrorMessage | Should -Be 'Profile is currently loaded'
        }
    }

    Context 'Successful removal with -Force' {
        BeforeAll {
            $script:callCount = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    # First call: enumerate
                    @(
                        @{
                            SID         = 'S-1-5-21-1234-5678-9012-2001'
                            LocalPath   = 'C:\Users\old.user'
                            LastUseTime = $script:mockOldDate
                            Loaded      = $false
                            SizeMB      = [double]200.0
                        }
                    )
                }
                # Second+ calls: remove (return nothing)
            }
        }

        It -Name 'Should return Removed status' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -Force)
            $removed = $results | Where-Object { $_.Status -eq 'Removed' }
            $removed | Should -Not -BeNullOrEmpty
            $removed.UserName | Should -Be 'old.user'
        }
    }

    Context 'Removal failure handling' {
        BeforeAll {
            $script:removeCallCount = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:removeCallCount++
                if ($script:removeCallCount -eq 1) {
                    @(
                        @{
                            SID         = 'S-1-5-21-1234-5678-9012-3001'
                            LocalPath   = 'C:\Users\locked.user'
                            LastUseTime = $script:mockOldDate
                            Loaded      = $false
                            SizeMB      = [double]150.0
                        }
                    )
                } else {
                    throw 'Access denied'
                }
            }
        }

        It -Name 'Should return Failed status with ErrorMessage' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -Force)
            $failed = $results | Where-Object { $_.Status -eq 'Failed' }
            $failed | Should -Not -BeNullOrEmpty
            $failed.ErrorMessage | Should -Match 'Access denied'
        }
    }

    Context 'Per-machine error isolation' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                if ($ComputerName -eq 'BADHOST') {
                    throw 'Connection refused'
                }
                @($script:mockProfiles)
            }
        }

        It -Name 'Should continue processing after a machine failure' -Test {
            $results = @('BADHOST', 'GOODHOST' | Remove-UserProfile -OlderThanDays 90 -WhatIf -ErrorAction SilentlyContinue)
            $goodResults = $results | Where-Object { $_.ComputerName -eq 'GOODHOST' }
            $goodResults | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:mockProfiles)
            }
        }

        It -Name 'Should produce verbose messages' -Test {
            $verboseOutput = Remove-UserProfile -OlderThanDays 90 -WhatIf -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verboseOutput | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Age threshold filtering' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:mockProfiles)
            }
        }

        It -Name 'Should not return profiles newer than threshold' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            $results | Where-Object { $_.UserName -eq 'jane.smith' } | Should -BeNullOrEmpty
        }

        It -Name 'Should respect custom OlderThanDays value' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 5 -WhatIf)
            $recent = $results | Where-Object { $_.UserName -eq 'jane.smith' }
            $recent | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Null LastUseTime handling' {
        BeforeAll {
            $script:nullDateProfiles = @(
                @{
                    SID         = 'S-1-5-21-1234-5678-9012-4001'
                    LocalPath   = 'C:\Users\never.used'
                    LastUseTime = $null
                    Loaded      = $false
                    SizeMB      = [double]0.5
                }
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @($script:nullDateProfiles)
            }
        }

        It -Name 'Should include profiles with null LastUseTime' -Test {
            $results = @(Remove-UserProfile -OlderThanDays 90 -WhatIf)
            $results.Count | Should -Be 1
            $results[0].UserName | Should -Be 'never.used'
        }
    }
}
