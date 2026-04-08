BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockShowSuccess = @(
        [PSCustomObject]@{ KBArticle = 'KB5034441'; Title = 'Cumulative Update (KB5034441)'; Result = 'Shown' }
    )
    $script:mockNotFound = @(
        [PSCustomObject]@{ KBArticle = 'KB9999999'; Title = $null; Result = 'NotFound' }
    )
}

Describe -Name 'Show-WindowsUpdate' -Tag 'Unit' -Fixture {

    Context 'Function metadata' {

        It -Name 'Should be an exported function' -Test {
            Get-Command -Name 'Show-WindowsUpdate' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should support ShouldProcess' -Test {
            (Get-Command -Name 'Show-WindowsUpdate').Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }

        It -Name 'Should require KBArticleID' -Test {
            (Get-Command -Name 'Show-WindowsUpdate').Parameters['KBArticleID'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Happy path - show update' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockShowSuccess
            }
            $script:result = Show-WindowsUpdate -KBArticleID 'KB5034441'
        }

        It -Name 'Should return a result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have PSTypeName PSWinOps.WindowsUpdateShowResult' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateShowResult'
        }

        It -Name 'Should have Result Shown' -Test {
            $script:result.Result | Should -Be 'Shown'
        }

        It -Name 'Should have ComputerName' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should have Timestamp' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}
        }
    }

    Context 'KB not found in hidden updates' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockNotFound
            }
            $script:result = Show-WindowsUpdate -KBArticleID 'KB9999999'
        }

        It -Name 'Should return NotFound' -Test {
            $script:result.Result | Should -Be 'NotFound'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockShowSuccess
            }
            $script:result = Show-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockShowSuccess
            }
            $script:results = 'SRV01', 'SRV02' | Show-WindowsUpdate -KBArticleID 'KB5034441'
        }

        It -Name 'Should return results for each machine' -Test {
            @($script:results).Count | Should -Be 2
        }
    }

    Context 'WhatIf support' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockShowSuccess
            }
        }

        It -Name 'Should not call Invoke-RemoteOrLocal with WhatIf' -Test {
            Show-WindowsUpdate -KBArticleID 'KB5034441' -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Per-machine error handling' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                throw 'Access denied'
            }
        }

        It -Name 'Should write error for failed machine' -Test {
            { Show-WindowsUpdate -ComputerName 'BADHOST' -KBArticleID 'KB5034441' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when KBArticleID is empty' -Test {
            { Show-WindowsUpdate -KBArticleID '' } | Should -Throw
        }
    }
}