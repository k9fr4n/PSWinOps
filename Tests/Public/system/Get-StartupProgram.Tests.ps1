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

        It -Name 'Should return results for each machine' -Test {
            @($script:results).Count | Should -BeGreaterOrEqual 2
        }

        It -Name 'Should return distinct ComputerName per machine' -Test {
            $computerNames = $script:results | Select-Object -ExpandProperty ComputerName -Unique
            $computerNames | Should -Contain 'SRV01'
            $computerNames | Should -Contain 'SRV02'
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

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStartupEntries }
            $script:typeResults = Get-StartupProgram -ComputerName 'SRV01'
        }
        It -Name 'Should have PSTypeName PSWinOps.StartupProgram on all results' -Test {
            $script:typeResults | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'PSWinOps.StartupProgram' }
        }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStartupEntries }
            $script:propResults = Get-StartupProgram -ComputerName 'SRV01'
        }
        It -Name 'Should contain all 8 expected properties' -Test {
            $script:propertyNames = $script:propResults[0].PSObject.Properties.Name
            $script:expectedProps = @('PSTypeName', 'ComputerName', 'ProgramName', 'Command', 'Location', 'Scope', 'Source', 'Timestamp')
            foreach ($script:prop in $script:expectedProps) {
                $script:propertyNames | Should -Contain $script:prop
            }
        }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStartupEntries }
            $script:tsResults = Get-StartupProgram -ComputerName 'SRV01'
        }
        It -Name 'Should have Timestamp matching ISO 8601 pattern' -Test {
            $script:tsResults | ForEach-Object { $_.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
        }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockStartupEntries }
        }
        It -Name 'Should emit verbose messages containing Get-StartupProgram' -Test {
            $script:verboseOutput = Get-StartupProgram -ComputerName 'SRV01' -Verbose 4>&1
            $script:verboseMessages = @($script:verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $script:verboseMessages.Count | Should -BeGreaterOrEqual 1
            $script:verboseText = $script:verboseMessages | ForEach-Object { $_.Message }
            $script:verboseText -join ' ' | Should -Match 'Get-StartupProgram'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-StartupProgram'
            $script:cmdInfo.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential of type PSCredential' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-StartupProgram'
            $script:cmdInfo.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
        It -Name 'Should not require Credential as mandatory' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-StartupProgram'
            $script:isMandatory = $script:cmdInfo.Parameters['Credential'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $script:isMandatory | Should -Be $false
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should support CN alias' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-StartupProgram'
            $script:cmdInfo.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should support Name alias' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-StartupProgram'
            $script:cmdInfo.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }
}
