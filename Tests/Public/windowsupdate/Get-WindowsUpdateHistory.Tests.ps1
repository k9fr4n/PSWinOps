#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    $script:mockHistoryEntries = @(
        [PSCustomObject]@{
            Title          = '2026-03 Cumulative Update for Windows Server 2022 (KB5034441)'
            Operation      = 1
            ResultCode     = 2
            Date           = [datetime]'2026-03-15 10:30:00'
            Description    = 'A security update for Windows Server 2022'
            SupportUrl     = 'https://support.microsoft.com/kb/5034441'
            UpdateIdentity = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        },
        [PSCustomObject]@{
            Title          = '2026-02 Security Update for Windows Server 2022 (KB5035432)'
            Operation      = 1
            ResultCode     = 4
            Date           = [datetime]'2026-02-20 14:15:00'
            Description    = 'A critical security update'
            SupportUrl     = 'https://support.microsoft.com/kb/5035432'
            UpdateIdentity = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
        },
        [PSCustomObject]@{
            Title          = 'Malicious Software Removal Tool - March 2026'
            Operation      = 1
            ResultCode     = 2
            Date           = [datetime]'2026-03-10 08:00:00'
            Description    = 'This tool checks for malicious software'
            SupportUrl     = ''
            UpdateIdentity = 'c3d4e5f6-a7b8-9012-cdef-123456789012'
        },
        [PSCustomObject]@{
            Title          = 'Update for Windows Defender Antivirus (KB2267602)'
            Operation      = 2
            ResultCode     = 2
            Date           = [datetime]'2026-03-01 06:00:00'
            Description    = 'Definition update for Windows Defender'
            SupportUrl     = ''
            UpdateIdentity = 'd4e5f6a7-b8c9-0123-defa-234567890123'
        }
    )
}

Describe 'Get-WindowsUpdateHistory' {

    Context 'Happy path - local machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockHistoryEntries
            }

            $script:results = Get-WindowsUpdateHistory
        }

        It -Name 'Should return results' -Test {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should return all 4 mock entries' -Test {
            @($script:results).Count | Should -Be 4
        }

        It -Name 'Should set correct PSTypeName on each object' -Test {
            foreach ($item in $script:results) {
                $item.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateHistory'
            }
        }

        It -Name 'Should set ComputerName to local machine' -Test {
            foreach ($item in $script:results) {
                $item.ComputerName | Should -Be $env:COMPUTERNAME
            }
        }

        It -Name 'Should sort results by Date descending' -Test {
            $script:results[0].Date | Should -BeGreaterThan $script:results[1].Date
            $script:results[1].Date | Should -BeGreaterThan $script:results[2].Date
        }

        It -Name 'Should include Timestamp in ISO 8601 format' -Test {
            foreach ($item in $script:results) {
                $item.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
            }
        }
    }

    Context 'KB article extraction' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockHistoryEntries
            }

            $script:results = Get-WindowsUpdateHistory
        }

        It -Name 'Should extract KB number from title containing KB' -Test {
            $kbEntry = $script:results | Where-Object -Property 'Title' -Like '*KB5034441*'
            $kbEntry.KBArticle | Should -Be 'KB5034441'
        }

        It -Name 'Should return empty string when title has no KB number' -Test {
            $noKbEntry = $script:results | Where-Object -Property 'Title' -Like '*Malicious*'
            $noKbEntry.KBArticle | Should -Be ''
        }
    }

    Context 'Operation mapping' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockHistoryEntries
            }

            $script:results = Get-WindowsUpdateHistory
        }

        It -Name 'Should map Operation 1 to Installation' -Test {
            $installEntry = $script:results | Where-Object -Property 'Title' -Like '*KB5034441*'
            $installEntry.Operation | Should -Be 'Installation'
        }

        It -Name 'Should map Operation 2 to Uninstallation' -Test {
            $uninstallEntry = $script:results | Where-Object -Property 'Title' -Like '*Defender*'
            $uninstallEntry.Operation | Should -Be 'Uninstallation'
        }
    }

    Context 'Result code mapping' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockHistoryEntries
            }

            $script:results = Get-WindowsUpdateHistory
        }

        It -Name 'Should map ResultCode 2 to Succeeded' -Test {
            $succeededEntry = $script:results | Where-Object -Property 'Title' -Like '*KB5034441*'
            $succeededEntry.Result | Should -Be 'Succeeded'
        }

        It -Name 'Should map ResultCode 4 to Failed' -Test {
            $failedEntry = $script:results | Where-Object -Property 'Title' -Like '*KB5035432*'
            $failedEntry.Result | Should -Be 'Failed'
        }

        It -Name 'Should map unknown ResultCode to Unknown' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @([PSCustomObject]@{
                    Title          = 'Unknown Update'
                    Operation      = 99
                    ResultCode     = 99
                    Date           = [datetime]'2026-01-01'
                    Description    = ''
                    SupportUrl     = ''
                    UpdateIdentity = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                })
            }

            $unknownResult = Get-WindowsUpdateHistory
            $unknownResult.Result | Should -Be 'Unknown'
            $unknownResult.Operation | Should -Be 'Unknown'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockHistoryEntries
            }

            $script:remoteResults = Get-WindowsUpdateHistory -ComputerName 'SRV01'
        }

        It -Name 'Should return results for remote machine' -Test {
            $script:remoteResults | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            foreach ($item in $script:remoteResults) {
                $item.ComputerName | Should -Be 'SRV01'
            }
        }

        It -Name 'Should call Invoke-RemoteOrLocal with correct ComputerName' -Test {
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ComputerName -eq 'SRV01'
            }
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockHistoryEntries[0])
            }

            $script:pipelineResults = 'SRV01', 'SRV02' | Get-WindowsUpdateHistory
        }

        It -Name 'Should process each machine from pipeline' -Test {
            @($script:pipelineResults).Count | Should -Be 2
        }

        It -Name 'Should set correct ComputerName for each result' -Test {
            $script:pipelineResults[0].ComputerName | Should -Be 'SRV01'
            $script:pipelineResults[1].ComputerName | Should -Be 'SRV02'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine' -Test {
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'MaxResults parameter' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockHistoryEntries[0])
            }
        }

        It -Name 'Should pass MaxResults to Invoke-RemoteOrLocal as ArgumentList' -Test {
            Get-WindowsUpdateHistory -MaxResults 10
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ArgumentList[0] -eq 10
            }
        }

        It -Name 'Should default MaxResults to 50' -Test {
            Get-WindowsUpdateHistory
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ArgumentList[0] -eq 50
            }
        }
    }

    Context 'Empty history' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @()
            }
        }

        It -Name 'Should return nothing when history is empty' -Test {
            $emptyResult = Get-WindowsUpdateHistory
            $emptyResult | Should -BeNullOrEmpty
        }

        It -Name 'Should not throw when history is empty' -Test {
            { Get-WindowsUpdateHistory } | Should -Not -Throw
        }
    }

    Context 'Per-machine failure continues' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                throw 'WinRM connection failed'
            }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-WindowsUpdateHistory -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should not throw with default ErrorAction' -Test {
            { Get-WindowsUpdateHistory -ComputerName 'BADHOST' -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It -Name 'Should return no output for failed machine' -Test {
            $failResult = Get-WindowsUpdateHistory -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty string' -Test {
            { Get-WindowsUpdateHistory -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-WindowsUpdateHistory -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when MaxResults is 0' -Test {
            { Get-WindowsUpdateHistory -MaxResults 0 } | Should -Throw
        }

        It -Name 'Should throw when MaxResults exceeds 1000' -Test {
            { Get-WindowsUpdateHistory -MaxResults 1001 } | Should -Throw
        }

        It -Name 'Should accept CN alias for ComputerName' -Test {
            $paramMeta = (Get-Command -Name 'Get-WindowsUpdateHistory').Parameters['ComputerName']
            $paramMeta.Aliases | Should -Contain 'CN'
        }

        It -Name 'Should accept DNSHostName alias for ComputerName' -Test {
            $paramMeta = (Get-Command -Name 'Get-WindowsUpdateHistory').Parameters['ComputerName']
            $paramMeta.Aliases | Should -Contain 'DNSHostName'
        }
    }

    Context 'Output object properties' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return @($script:mockHistoryEntries[0])
            }

            $script:singleResult = Get-WindowsUpdateHistory
        }

        It -Name 'Should have all expected properties' -Test {
            $expectedProperties = @(
                'ComputerName', 'Title', 'KBArticle', 'Operation', 'Result',
                'Date', 'Description', 'SupportUrl', 'UpdateIdentity', 'Timestamp'
            )
            foreach ($prop in $expectedProperties) {
                $script:singleResult.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should preserve Date as datetime' -Test {
            $script:singleResult.Date | Should -BeOfType [datetime]
        }

        It -Name 'Should preserve UpdateIdentity GUID' -Test {
            $script:singleResult.UpdateIdentity | Should -Be 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        }

        It -Name 'Should preserve SupportUrl' -Test {
            $script:singleResult.SupportUrl | Should -Be 'https://support.microsoft.com/kb/5034441'
        }
    }
}