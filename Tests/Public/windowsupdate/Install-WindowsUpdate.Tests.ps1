BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockUpdate = [PSCustomObject]@{
        PSTypeName      = 'PSWinOps.WindowsUpdate'
        ComputerName    = $env:COMPUTERNAME
        Title           = '2026-03 Cumulative Update for Windows Server 2022 (KB5034441)'
        KBArticle       = 'KB5034441'
        Classification  = 'Security Updates'
        Products        = @('Windows Server 2022')
        Description     = 'A cumulative security update'
        ReleaseNotes    = ''
        MsrcSeverity    = 'Critical'
        CveIDs          = @()
        IsDownloaded    = $false
        IsHidden        = $false
        IsInstalled     = $false
        IsMandatory     = $true
        IsUninstallable = $true
        EulaAccepted    = $true
        Deadline        = $null
        RebootRequired  = $true
        SizeMB          = 45.12
        UpdateId        = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        RevisionNumber  = 201
        Timestamp       = '2026-04-08 21:00:00'
    }

    $script:mockInstallSuccess = [PSCustomObject]@{
        ResultCode     = 2
        HResult        = 0
        RebootRequired = $false
    }

    $script:mockInstallSuccessReboot = [PSCustomObject]@{
        ResultCode     = 2
        HResult        = 0
        RebootRequired = $true
    }

    $script:mockInstallFailed = [PSCustomObject]@{
        ResultCode     = 4
        HResult        = -2145124329
        RebootRequired = $false
    }
}

Describe -Name 'Install-WindowsUpdate' -Tag 'Unit' -Fixture {

    Context 'Function metadata' {

        It -Name 'Should be an exported function' -Test {
            Get-Command -Name 'Install-WindowsUpdate' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should support ShouldProcess' -Test {
            $cmdInfo = Get-Command -Name 'Install-WindowsUpdate'
            $cmdInfo.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $cmdInfo.Parameters.ContainsKey('Confirm') | Should -BeTrue
        }

        It -Name 'Should have ConfirmImpact High' -Test {
            $cmdletAttr = (Get-Command -Name 'Install-WindowsUpdate').ScriptBlock.Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $cmdletAttr.ConfirmImpact | Should -Be 'High'
        }
    }

    Context 'Happy path - local install' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockInstallSuccess
            }

            $script:result = Install-WindowsUpdate -AcceptEula -Confirm:$false
        }

        It -Name 'Should return a result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have PSTypeName PSWinOps.WindowsUpdateInstallResult' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateInstallResult'
        }

        It -Name 'Should have ComputerName set to local machine' -Test {
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should have Result Succeeded' -Test {
            $script:result.Result | Should -Be 'Succeeded'
        }

        It -Name 'Should preserve Title' -Test {
            $script:result.Title | Should -BeLike '*KB5034441*'
        }

        It -Name 'Should have HResult 0x00000000' -Test {
            $script:result.HResult | Should -Be '0x00000000'
        }

        It -Name 'Should have RebootRequired property' -Test {
            $script:result.RebootRequired | Should -BeFalse
        }

        It -Name 'Should have Timestamp' -Test {
            $script:result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }

    Context 'Install failure' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockInstallFailed
            }

            $script:result = Install-WindowsUpdate -AcceptEula -Confirm:$false
        }

        It -Name 'Should return Failed result' -Test {
            $script:result.Result | Should -Be 'Failed'
        }

        It -Name 'Should show HResult in hex' -Test {
            $script:result.HResult | Should -Be '0x80240017'
        }
    }

    Context 'Reboot required without AutoReboot' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockInstallSuccessReboot
            }
        }

        It -Name 'Should set RebootRequired to true' -Test {
            $result = Install-WindowsUpdate -AcceptEula -Confirm:$false
            $result.RebootRequired | Should -BeTrue
        }

        It -Name 'Should warn about reboot needed' -Test {
            $result = Install-WindowsUpdate -AcceptEula -Confirm:$false 3>&1
            $warnings = $result | Where-Object -FilterScript { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Reboot required with AutoReboot' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockInstallSuccessReboot
            }
        }

        It -Name 'Should call Invoke-RemoteOrLocal for reboot with AutoReboot' -Test {
            Install-WindowsUpdate -AcceptEula -AutoReboot -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2
        }
    }

    Context 'No updates available' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should return nothing when no updates are available' -Test {
            $result = Install-WindowsUpdate -AcceptEula -Confirm:$false
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'WhatIf support' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockInstallSuccess
            }
        }

        It -Name 'Should not call Invoke-RemoteOrLocal with WhatIf' -Test {
            Install-WindowsUpdate -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockInstallSuccess
            }
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $result = Install-WindowsUpdate -ComputerName 'SRV01' -AcceptEula -Confirm:$false
            $result.ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockInstallSuccess
            }

            $script:results = 'SRV01', 'SRV02' | Install-WindowsUpdate -AcceptEula -Confirm:$false
        }

        It -Name 'Should return results for each machine' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should set correct ComputerName for each result' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'Filter passthrough' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should pass MicrosoftUpdate to Get-WindowsUpdate' -Test {
            Install-WindowsUpdate -MicrosoftUpdate -AcceptEula -Confirm:$false
            Should -Invoke -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -ParameterFilter {
                $MicrosoftUpdate -eq $true
            }
        }

        It -Name 'Should pass KBArticleID to Get-WindowsUpdate' -Test {
            Install-WindowsUpdate -KBArticleID 'KB5034441' -AcceptEula -Confirm:$false
            Should -Invoke -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -ParameterFilter {
                $KBArticleID -eq 'KB5034441'
            }
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Install-WindowsUpdate -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when KBArticleID is empty string' -Test {
            { Install-WindowsUpdate -KBArticleID '' } | Should -Throw
        }
    }

    Context 'Per-machine error handling' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                throw 'WinRM connection failed'
            }
        }

        It -Name 'Should write error for failed machine with ErrorAction Stop' -Test {
            { Install-WindowsUpdate -ComputerName 'BADHOST' -AcceptEula -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }
}