#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-StartupProgram' {

    BeforeAll {
        $script:mockStartupEntries = @(
            [PSCustomObject]@{ ProgramName = 'SecurityHealth'; Command = 'C:\Windows\System32\SecurityHealthSystray.exe'; Location = 'HKLM\...\Run'; Scope = 'Machine'; Source = 'Registry' },
            [PSCustomObject]@{ ProgramName = 'OneDrive'; Command = 'C:\Users\admin\AppData\Local\Microsoft\OneDrive\OneDrive.exe'; Location = 'HKCU\...\Run'; Scope = 'User'; Source = 'Registry' },
            [PSCustomObject]@{ ProgramName = 'MyApp'; Command = 'C:\MyApp\app.exe'; Location = 'Common Startup Folder'; Scope = 'Machine'; Source = 'StartupFolder' }
        )
    }

    Context 'Remote - happy path' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStartupEntries }
            $script:results = Get-StartupProgram -ComputerName 'SRV01'
        }

        It -Name 'Should return PSWinOps.StartupProgram type' -Test {
            $script:results[0].PSObject.TypeNames | Should -Contain 'PSWinOps.StartupProgram'
        }

        It -Name 'Should return 3 startup entries' -Test {
            $script:results | Should -HaveCount 3
        }

        It -Name 'Should set ComputerName to SRV01 on each result' -Test {
            $script:results | ForEach-Object -Process {
                $_.ComputerName | Should -Be 'SRV01'
            }
        }
    }

    Context 'Remote - verify properties' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStartupEntries }
            $script:results = Get-StartupProgram -ComputerName 'SRV01'
        }

        It -Name 'Should have correct ProgramName for SecurityHealth' -Test {
            ($script:results | Where-Object -FilterScript { $_.ProgramName -eq 'SecurityHealth' }).ProgramName | Should -Be 'SecurityHealth'
        }

        It -Name 'Should have correct Command for SecurityHealth' -Test {
            ($script:results | Where-Object -FilterScript { $_.ProgramName -eq 'SecurityHealth' }).Command | Should -Be 'C:\Windows\System32\SecurityHealthSystray.exe'
        }

        It -Name 'Should have Scope Machine for SecurityHealth' -Test {
            ($script:results | Where-Object -FilterScript { $_.ProgramName -eq 'SecurityHealth' }).Scope | Should -Be 'Machine'
        }

        It -Name 'Should have Source Registry for SecurityHealth' -Test {
            ($script:results | Where-Object -FilterScript { $_.ProgramName -eq 'SecurityHealth' }).Source | Should -Be 'Registry'
        }

        It -Name 'Should have Scope User for OneDrive' -Test {
            ($script:results | Where-Object -FilterScript { $_.ProgramName -eq 'OneDrive' }).Scope | Should -Be 'User'
        }

        It -Name 'Should have Source StartupFolder for MyApp' -Test {
            ($script:results | Where-Object -FilterScript { $_.ProgramName -eq 'MyApp' }).Source | Should -Be 'StartupFolder'
        }

        It -Name 'Should include Timestamp on each result' -Test {
            $script:results | ForEach-Object -Process {
                $_.Timestamp | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStartupEntries }
            $script:results = 'SRV01', 'SRV02' | Get-StartupProgram
        }

        It -Name 'Should call Invoke-Command twice' -Test {
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-StartupProgram -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-StartupProgram -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-StartupProgram -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-StartupProgram -ComputerName $null } | Should -Throw
        }
    }
}
