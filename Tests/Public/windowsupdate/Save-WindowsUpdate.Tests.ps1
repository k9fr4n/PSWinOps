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

    $script:mockUpdate2 = [PSCustomObject]@{
        PSTypeName      = 'PSWinOps.WindowsUpdate'
        ComputerName    = $env:COMPUTERNAME
        Title           = 'Definition Update for Windows Defender (KB2267602)'
        KBArticle       = 'KB2267602'
        Classification  = 'Definition Updates'
        Products        = @('Windows Defender')
        Description     = 'Definition update'
        ReleaseNotes    = ''
        MsrcSeverity    = ''
        CveIDs          = @()
        IsDownloaded    = $false
        IsHidden        = $false
        IsInstalled     = $false
        IsMandatory     = $false
        IsUninstallable = $false
        EulaAccepted    = $true
        Deadline        = $null
        RebootRequired  = $false
        SizeMB          = 2.0
        UpdateId        = 'd4e5f6a7-b8c9-0123-defa-234567890123'
        RevisionNumber  = 1
        Timestamp       = '2026-04-08 21:00:00'
    }

    $script:mockDownloadSuccess = [PSCustomObject]@{
        ResultCode        = 2
        HResult           = 0
        AlreadyDownloaded = $false
    }

    $script:mockAlreadyDownloaded = [PSCustomObject]@{
        ResultCode        = 2
        HResult           = 0
        AlreadyDownloaded = $true
    }

    $script:mockDownloadFailed = [PSCustomObject]@{
        ResultCode        = 4
        HResult           = -2145124329
        AlreadyDownloaded = $false
    }
}

Describe -Name 'Save-WindowsUpdate' -Tag 'Unit' -Fixture {

    Context 'Function metadata' {

        It -Name 'Should be an exported function' -Test {
            Get-Command -Name 'Save-WindowsUpdate' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have alias Download-WindowsUpdate' -Test {
            $alias = Get-Alias -Name 'Download-WindowsUpdate' -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.ResolvedCommand.Name | Should -Be 'Save-WindowsUpdate'
        }

        It -Name 'Should support ShouldProcess' -Test {
            $cmdInfo = Get-Command -Name 'Save-WindowsUpdate'
            $cmdInfo.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $cmdInfo.Parameters.ContainsKey('Confirm') | Should -BeTrue
        }
    }

    Context 'Happy path - local download' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDownloadSuccess
            }

            $script:result = Save-WindowsUpdate -AcceptEula
        }

        It -Name 'Should return a result object' -Test {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have PSTypeName PSWinOps.WindowsUpdateDownloadResult' -Test {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateDownloadResult'
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

        It -Name 'Should preserve KBArticle' -Test {
            $script:result.KBArticle | Should -Be 'KB5034441'
        }

        It -Name 'Should preserve SizeMB' -Test {
            $script:result.SizeMB | Should -Be 45.12
        }

        It -Name 'Should have HResult 0x00000000' -Test {
            $script:result.HResult | Should -Be '0x00000000'
        }

        It -Name 'Should have Timestamp' -Test {
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}
        }
    }

    Context 'Already downloaded update' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockAlreadyDownloaded
            }

            $script:result = Save-WindowsUpdate
        }

        It -Name 'Should return AlreadyDownloaded result' -Test {
            $script:result.Result | Should -Be 'AlreadyDownloaded'
        }
    }

    Context 'Download failure' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDownloadFailed
            }

            $script:result = Save-WindowsUpdate
        }

        It -Name 'Should return Failed result' -Test {
            $script:result.Result | Should -Be 'Failed'
        }

        It -Name 'Should show HResult in hex' -Test {
            $script:result.HResult | Should -Be '0x80240017'
        }
    }

    Context 'No updates available' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should return nothing when no updates are available' -Test {
            $result = Save-WindowsUpdate
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Multiple updates' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate, $script:mockUpdate2)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDownloadSuccess
            }

            $script:results = Save-WindowsUpdate -AcceptEula
        }

        It -Name 'Should return one result per update' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per update' -Test {
            Save-WindowsUpdate -AcceptEula
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDownloadSuccess
            }

            $script:result = Save-WindowsUpdate -ComputerName 'SRV01'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should pass ComputerName to Get-WindowsUpdate' -Test {
            Save-WindowsUpdate -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -ParameterFilter {
                $ComputerName -eq 'SRV01'
            }
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDownloadSuccess
            }

            $script:results = 'SRV01', 'SRV02' | Save-WindowsUpdate
        }

        It -Name 'Should return results for each machine' -Test {
            @($script:results).Count | Should -Be 2
        }

        It -Name 'Should set correct ComputerName for each result' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
            $script:results[1].ComputerName | Should -Be 'SRV02'
        }
    }

    Context 'WhatIf support' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockUpdate)
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockDownloadSuccess
            }
        }

        It -Name 'Should not call Invoke-RemoteOrLocal with WhatIf' -Test {
            Save-WindowsUpdate -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    Context 'Filter passthrough' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should pass MicrosoftUpdate to Get-WindowsUpdate' -Test {
            Save-WindowsUpdate -MicrosoftUpdate
            Should -Invoke -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -ParameterFilter {
                $MicrosoftUpdate -eq $true
            }
        }

        It -Name 'Should pass KBArticleID to Get-WindowsUpdate' -Test {
            Save-WindowsUpdate -KBArticleID 'KB5034441'
            Should -Invoke -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -ParameterFilter {
                $KBArticleID -eq 'KB5034441'
            }
        }

        It -Name 'Should pass Classification to Get-WindowsUpdate' -Test {
            Save-WindowsUpdate -Classification 'Security Updates'
            Should -Invoke -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -ParameterFilter {
                $Classification -eq 'Security Updates'
            }
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Save-WindowsUpdate -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when KBArticleID is empty string' -Test {
            { Save-WindowsUpdate -KBArticleID '' } | Should -Throw
        }

        It -Name 'Should throw when Classification is empty string' -Test {
            { Save-WindowsUpdate -Classification '' } | Should -Throw
        }

        It -Name 'Should throw when Product is empty string' -Test {
            { Save-WindowsUpdate -Product '' } | Should -Throw
        }
    }

    Context 'Per-machine error handling' {

        BeforeAll {
            Mock -CommandName 'Get-WindowsUpdate' -ModuleName 'PSWinOps' -MockWith {
                throw 'WinRM connection failed'
            }
        }

        It -Name 'Should continue processing after per-machine failure' -Test {
            $results = 'BADHOST', $env:COMPUTERNAME | Save-WindowsUpdate -ErrorAction SilentlyContinue
            # Should not throw — errors are written, not thrown
        }

        It -Name 'Should write error for failed machine with ErrorAction Stop' -Test {
            { Save-WindowsUpdate -ComputerName 'BADHOST' -ErrorAction Stop } | Should -Throw -ExpectedMessage '*BADHOST*'
        }
    }
}