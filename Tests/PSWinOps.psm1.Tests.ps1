#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path $PSScriptRoot -Parent

    if (-not (Get-Command -Name 'Get-ADUser' -ErrorAction SilentlyContinue)) {
        function global:Get-ADUser { param($Filter, $Identity, $Properties, $Server, $Credential, $ErrorAction) }
    }
    if (-not (Get-Command -Name 'Get-ADComputer' -ErrorAction SilentlyContinue)) {
        function global:Get-ADComputer { param($Filter, $Name, $Server, $Credential, $ErrorAction) }
    }
    if (-not (Get-Command -Name 'Get-ADGroup' -ErrorAction SilentlyContinue)) {
        function global:Get-ADGroup { param($Filter, $Name, $Server, $Credential, $ErrorAction) }
    }

    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

AfterAll {
    if (Get-Module -Name 'PSWinOps') {
        Remove-Module -Name 'PSWinOps' -Force
    }
}

Describe -Name 'PSWinOps Module Loader' -Fixture {

    Context -Name 'Module loads successfully' -Fixture {

        It -Name 'Should be loaded in the current session' -Test {
            Get-Module -Name 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a valid module version' -Test {
            $mod = Get-Module -Name 'PSWinOps'
            $mod.Version | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should pass Test-ModuleManifest without errors' -Test {
            $manifestPath = Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1'
            { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context -Name 'Module-scoped variables' -Fixture {

        It -Name 'Should set ModuleRoot variable in module scope' -Test {
            $moduleRoot = & (Get-Module -Name 'PSWinOps') { $script:ModuleRoot }
            $moduleRoot | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should set LocalComputerNames with current computer name' -Test {
            $localNames = & (Get-Module -Name 'PSWinOps') { $script:LocalComputerNames }
            $localNames | Should -Contain $env:COMPUTERNAME
        }

        It -Name 'Should include localhost in LocalComputerNames' -Test {
            $localNames = & (Get-Module -Name 'PSWinOps') { $script:LocalComputerNames }
            $localNames | Should -Contain 'localhost'
        }

        It -Name 'Should include dot notation in LocalComputerNames' -Test {
            $localNames = & (Get-Module -Name 'PSWinOps') { $script:LocalComputerNames }
            $localNames | Should -Contain '.'
        }
    }

    Context -Name 'Public function exports' -Fixture {

        BeforeAll {
            $script:exportedFunctions = (Get-Module -Name 'PSWinOps').ExportedFunctions.Keys
        }

        It -Name 'Should export at least one public function' -Test {
            $script:exportedFunctions.Count | Should -BeGreaterThan 0
        }

        It -Name 'Should export Show-SystemMonitor' -Test {
            $script:exportedFunctions | Should -Contain 'Show-SystemMonitor'
        }

        It -Name 'Should export Get-ExchangeServerHealth' -Test {
            $script:exportedFunctions | Should -Contain 'Get-ExchangeServerHealth'
        }

        It -Name 'Should export Get-ADUserGroupInventory' -Test {
            $script:exportedFunctions | Should -Contain 'Get-ADUserGroupInventory'
        }

        It -Name 'Should export Sync-NTPTime' -Test {
            $script:exportedFunctions | Should -Contain 'Sync-NTPTime'
        }
    }

    Context -Name 'Private function isolation' -Fixture {

        BeforeAll {
            $script:exportedFunctions = (Get-Module -Name 'PSWinOps').ExportedFunctions.Keys
        }

        It -Name 'Should not export Invoke-RemoteOrLocal' -Test {
            $script:exportedFunctions | Should -Not -Contain 'Invoke-RemoteOrLocal'
        }

        It -Name 'Should not export Test-IsAdministrator' -Test {
            $script:exportedFunctions | Should -Not -Contain 'Test-IsAdministrator'
        }

        It -Name 'Should not export Invoke-NativeCommand' -Test {
            $script:exportedFunctions | Should -Not -Contain 'Invoke-NativeCommand'
        }

        It -Name 'Should make private functions accessible inside module scope' -Test {
            $canCall = & (Get-Module -Name 'PSWinOps') {
                $null -ne (Get-Command -Name 'Invoke-RemoteOrLocal' -ErrorAction SilentlyContinue)
            }
            $canCall | Should -BeTrue
        }
    }

    Context -Name 'AD User argument completer' -Fixture {

        It -Name 'Should have ADUserCompleter scriptblock defined in module scope' -Test {
            $completer = & (Get-Module -Name 'PSWinOps') { $script:ADUserCompleter }
            $completer | Should -Not -BeNullOrEmpty
            $completer | Should -BeOfType [scriptblock]
        }

        It -Name 'Should return CompletionResult objects when AD returns users' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADUser {
                    param($Filter, $Properties, $Server, $Credential, $ErrorAction)
                    [PSCustomObject]@{ SamAccountName = 'jdoe'; DisplayName = 'John Doe' }
                }
                & $script:ADUserCompleter 'Test-Cmd' 'Identity' 'jd' $null @{}
            }
            $results | Should -Not -BeNullOrEmpty
            $results[0].CompletionText | Should -Be 'jdoe'
        }

        It -Name 'Should return CompletionResult with tooltip including DisplayName' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADUser {
                    param($Filter, $Properties, $Server, $Credential, $ErrorAction)
                    [PSCustomObject]@{ SamAccountName = 'jdoe'; DisplayName = 'John Doe' }
                }
                & $script:ADUserCompleter 'Test-Cmd' 'Identity' 'jd' $null @{}
            }
            $results[0].ToolTip | Should -Match 'John Doe'
        }

        It -Name 'Should return empty when AD module is unavailable' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADUser {
                    param($Filter, $Properties, $Server, $Credential, $ErrorAction)
                    throw 'Module not loaded'
                }
                & $script:ADUserCompleter 'Test-Cmd' 'Identity' 'jd' $null @{}
            }
            $results | Should -BeNullOrEmpty
        }

        It -Name 'Should limit results to maximum 20 entries' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADUser {
                    param($Filter, $Properties, $Server, $Credential, $ErrorAction)
                    1..30 | ForEach-Object {
                        [PSCustomObject]@{ SamAccountName = "user$_"; DisplayName = "User $_" }
                    }
                }
                & $script:ADUserCompleter 'Test-Cmd' 'Identity' 'user' $null @{}
            }
            @($results).Count | Should -BeLessOrEqual 20
        }
    }

    Context -Name 'AD Computer argument completer' -Fixture {

        It -Name 'Should have ADComputerCompleter scriptblock defined' -Test {
            $completer = & (Get-Module -Name 'PSWinOps') { $script:ADComputerCompleter }
            $completer | Should -Not -BeNullOrEmpty
            $completer | Should -BeOfType [scriptblock]
        }

        It -Name 'Should return CompletionResult for computers' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADComputer {
                    param($Filter, $Server, $Credential, $ErrorAction)
                    [PSCustomObject]@{ Name = 'SRV-WEB01'; DistinguishedName = 'CN=SRV-WEB01,OU=Servers,DC=contoso,DC=com' }
                }
                & $script:ADComputerCompleter 'Test-Cmd' 'Identity' 'SRV' $null @{}
            }
            $results | Should -Not -BeNullOrEmpty
            $results[0].CompletionText | Should -Be 'SRV-WEB01'
        }

        It -Name 'Should return empty when AD is unavailable for computers' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADComputer {
                    param($Filter, $Server, $Credential, $ErrorAction)
                    throw 'Module not loaded'
                }
                & $script:ADComputerCompleter 'Test-Cmd' 'Identity' 'SRV' $null @{}
            }
            $results | Should -BeNullOrEmpty
        }
    }

    Context -Name 'AD Group argument completer' -Fixture {

        It -Name 'Should have ADGroupCompleter scriptblock defined' -Test {
            $completer = & (Get-Module -Name 'PSWinOps') { $script:ADGroupCompleter }
            $completer | Should -Not -BeNullOrEmpty
            $completer | Should -BeOfType [scriptblock]
        }

        It -Name 'Should return CompletionResult for groups' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADGroup {
                    param($Filter, $Server, $Credential, $ErrorAction)
                    [PSCustomObject]@{ Name = 'Domain Admins'; GroupScope = 'Global'; GroupCategory = 'Security' }
                }
                & $script:ADGroupCompleter 'Test-Cmd' 'Identity' 'Dom' $null @{}
            }
            $results | Should -Not -BeNullOrEmpty
            $results[0].CompletionText | Should -Be 'Domain Admins'
        }

        It -Name 'Should return empty when AD is unavailable for groups' -Test {
            $results = & (Get-Module -Name 'PSWinOps') {
                function Get-ADGroup {
                    param($Filter, $Server, $Credential, $ErrorAction)
                    throw 'Module not loaded'
                }
                & $script:ADGroupCompleter 'Test-Cmd' 'Identity' 'Dom' $null @{}
            }
            $results | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Help documentation' -Fixture {

        It -Name 'Should have a module description in manifest' -Test {
            $manifestPath = Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1'
            $manifest = Test-ModuleManifest -Path $manifestPath
            $manifest.Description | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have about help file' -Test {
            $helpPath = Join-Path -Path $script:modulePath -ChildPath 'en-US'
            $aboutFile = Get-ChildItem -Path $helpPath -Filter 'about_PSWinOps*' -ErrorAction SilentlyContinue
            $aboutFile | Should -Not -BeNullOrEmpty
        }
    }
}
