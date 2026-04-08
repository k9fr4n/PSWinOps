BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockUninstallSuccess = @(
        [PSCustomObject]@{ KBArticle = 'KB5034441'; Result = 'Succeeded'; ExitCode = 0; RebootRequired = $false }
    )
    $script:mockUninstallReboot = @(
        [PSCustomObject]@{ KBArticle = 'KB5034441'; Result = 'SucceededRebootRequired'; ExitCode = 3010; RebootRequired = $true }
    )
    $script:mockNotInstalled = @(
        [PSCustomObject]@{ KBArticle = 'KB9999999'; Result = 'NotInstalled'; ExitCode = -1; RebootRequired = $false }
    )
    $script:mockNotUninstallable = @(
        [PSCustomObject]@{ KBArticle = 'KB5034441'; Result = 'NotUninstallable'; ExitCode = 2359303; RebootRequired = $false }
    )
}

Describe -Name 'Uninstall-WindowsUpdate' -Tag 'Unit' -Fixture {

    Context 'Function metadata' {

        It -Name 'Should be an exported function' -Test {
            Get-Command -Name 'Uninstall-WindowsUpdate' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should support ShouldProcess' -Test {
            (Get-Command -Name 'Uninstall-WindowsUpdate').Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It -Name 'Should have ConfirmImpact High' -Test {
            $cmdletAttr = (Get-Command -Name 'Uninstall-WindowsUpdate').ScriptBlock.Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $cmdletAttr.ConfirmImpact | Should -Be 'High'
        }

        It -Name 'Should require KBArticleID' -Test {
            (Get-Command -Name 'Uninstall-WindowsUpdate').Parameters['KBArticleID'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Happy path - uninstall succeeds' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUninstallSuccess
            }
            $script:result = Uninstall-WindowsUpdate -KBArticleID 'KB5034441' -Confirm:$false
        }

        It -Name 'Should return a result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have PSTypeName PSWinOps.WindowsUpdateUninstallResult' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateUninstallResult'
        }

        It -Name 'Should have Result Succeeded' -Test {
            $script:result.Result | Should -Be 'Succeeded'
        }

        It -Name 'Should have ExitCode 0' -Test {
            $script:result.ExitCode | Should -Be 0
        }

        It -Name 'Should have RebootRequired false' -Test {
            $script:result.RebootRequired | Should -BeFalse
        }

        It -Name 'Should have Timestamp' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}
        }
    }

    Context 'Reboot required after uninstall' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUninstallReboot
            }
        }

        It -Name 'Should return SucceededRebootRequired' -Test {
            $result = Uninstall-WindowsUpdate -KBArticleID 'KB5034441' -Confirm:$false
            $result.Result | Should -Be 'SucceededRebootRequired'
        }

        It -Name 'Should have RebootRequired true' -Test {
            $result = Uninstall-WindowsUpdate -KBArticleID 'KB5034441' -Confirm:$false
            $result.RebootRequired | Should -BeTrue
        }

        It -Name 'Should have ExitCode 3010' -Test {
            $result = Uninstall-WindowsUpdate -KBArticleID 'KB5034441' -Confirm:$false
            $result.ExitCode | Should -Be 3010
        }
    }

    Context 'KB not installed' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockNotInstalled
            }
            $script:result = Uninstall-WindowsUpdate -KBArticleID 'KB9999999' -Confirm:$false
        }

        It -Name 'Should return NotInstalled' -Test {
            $script:result.Result | Should -Be 'NotInstalled'
        }
    }

    Context 'KB not uninstallable' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockNotUninstallable
            }
            $script:result = Uninstall-WindowsUpdate -KBArticleID 'KB5034441' -Confirm:$false
        }

        It -Name 'Should return NotUninstallable' -Test {
            $script:result.Result | Should -Be 'NotUninstallable'
        }

        It -Name 'Should have ExitCode 2359303' -Test {
            $script:result.ExitCode | Should -Be 2359303
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUninstallSuccess
            }
            $script:result = Uninstall-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441' -Confirm:$false
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUninstallSuccess
            }
            $script:results = 'SRV01', 'SRV02' | Uninstall-WindowsUpdate -KBArticleID 'KB5034441' -Confirm:$false
        }

        It -Name 'Should return results for each machine' -Test {
            @($script:results).Count | Should -Be 2
        }
    }

    Context 'WhatIf support' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUninstallSuccess
            }
        }

        It -Name 'Should not call Invoke-RemoteOrLocal with WhatIf' -Test {
            Uninstall-WindowsUpdate -KBArticleID 'KB5034441' -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Per-machine error handling' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                throw 'WinRM failed'
            }
        }

        It -Name 'Should write error for failed machine' -Test {
            { Uninstall-WindowsUpdate -ComputerName 'BADHOST' -KBArticleID 'KB5034441' -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when KBArticleID is empty' -Test {
            { Uninstall-WindowsUpdate -KBArticleID '' } | Should -Throw
        }
    }
}