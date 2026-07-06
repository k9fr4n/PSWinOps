#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function global:Get-CimInstance {
        param($ClassName, $ErrorAction)
    }

    $script:mockServices = @(
        [PSCustomObject]@{
            Name             = 'wuauserv'
            DisplayName      = 'Windows Update'
            StartName        = 'LocalSystem'
            StartMode        = 'Manual'
            DelayedAutoStart = $false
            State            = 'Running'
            PathName         = 'C:\Windows\System32\svchost.exe -k netsvcs -p'
        },
        [PSCustomObject]@{
            Name             = 'MyCustomApp'
            DisplayName      = 'Custom App Service'
            StartName        = 'CONTOSO\svc-app'
            StartMode        = 'Auto'
            DelayedAutoStart = $true
            State            = 'Running'
            PathName         = '"C:\Program Files\App\app.exe" -config "C:\config.xml" --verbose'
        },
        [PSCustomObject]@{
            Name             = 'netsvc'
            DisplayName      = 'Network Service Host'
            StartName        = 'NT AUTHORITY\NetworkService'
            StartMode        = 'Auto'
            DelayedAutoStart = $false
            State            = 'Stopped'
            PathName         = 'C:\Windows\System32\svchost.exe -k netsvcs'
        },
        [PSCustomObject]@{
            Name             = 'localsvc'
            DisplayName      = 'Local Service Host'
            StartName        = 'nt authority\localservice'
            StartMode        = 'Auto'
            DelayedAutoStart = $false
            State            = 'Running'
            PathName         = 'C:\Windows\System32\svchost.exe -k localservice'
        }
    )
}

Describe -Name 'Get-ServiceAccount' -Fixture {

    Context -Name 'Local happy path' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockServices
            }
        }

        It -Name 'Should return a PSWinOps.ServiceAccount typed object for each service' -Test {
            $result = Get-ServiceAccount
            foreach ($item in $result) {
                $item.PSObject.TypeNames[0] | Should -Be 'PSWinOps.ServiceAccount'
            }
        }

        It -Name 'Should return all required output properties' -Test {
            $result = Get-ServiceAccount
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'ComputerName'
            $props | Should -Contain 'ServiceName'
            $props | Should -Contain 'DisplayName'
            $props | Should -Contain 'StartName'
            $props | Should -Contain 'StartMode'
            $props | Should -Contain 'DelayedAutoStart'
            $props | Should -Contain 'State'
            $props | Should -Contain 'PathName'
            $props | Should -Contain 'Timestamp'
        }

        It -Name 'Should set ComputerName to the local machine' -Test {
            $result = Get-ServiceAccount
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should map ServiceName from Win32_Service.Name' -Test {
            $result = Get-ServiceAccount
            ($result | Select-Object -ExpandProperty ServiceName) | Should -Contain 'wuauserv'
            ($result | Select-Object -ExpandProperty ServiceName) | Should -Contain 'MyCustomApp'
        }

        It -Name 'Should format Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-ServiceAccount
            $result[0].Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It -Name 'Should return one object per mocked service when no filter is applied' -Test {
            $result = @(Get-ServiceAccount)
            $result.Count | Should -Be 4
        }
    }

    Context -Name 'Explicit remote machine' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockServices
            }
        }

        It -Name 'Should dispatch via Invoke-Command for a remote machine' -Test {
            $result = Get-ServiceAccount -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $result[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should propagate Credential to Invoke-Command' -Test {
            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\svc', $securePwd)
            Get-ServiceAccount -ComputerName 'SRV01' -Credential $cred | Out-Null
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
        }
    }

    Context -Name 'Pipeline of multiple machine names' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                $script:mockServices | ForEach-Object {
                    [PSCustomObject]@{
                        Name             = $_.Name
                        DisplayName      = $_.DisplayName
                        StartName        = $_.StartName
                        StartMode        = $_.StartMode
                        DelayedAutoStart = $_.DelayedAutoStart
                        State            = $_.State
                        PathName         = $_.PathName
                    }
                }
            }
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine and return results for each' -Test {
            $result = 'SRV01', 'SRV02' | Get-ServiceAccount
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            ($result | Select-Object -ExpandProperty ComputerName -Unique) | Should -Contain 'SRV01'
            ($result | Select-Object -ExpandProperty ComputerName -Unique) | Should -Contain 'SRV02'
        }
    }

    Context -Name 'Per-machine failure continues processing remaining machines' -Fixture {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADHOST') {
                    throw 'Simulated access denied on BADHOST'
                }
                return $script:mockServices
            }
            $script:perMachineOutput    = 'BADHOST', 'SRV02' |
                Get-ServiceAccount -ErrorAction Continue 2>&1
            $script:perMachineErrors    = @($script:perMachineOutput | Where-Object {
                $_ -is [System.Management.Automation.ErrorRecord]
            })
            $script:perMachineSuccesses = @($script:perMachineOutput | Where-Object {
                $_ -isnot [System.Management.Automation.ErrorRecord]
            })
        }

        It -Name 'Should write an error for the failing machine' -Test {
            $script:perMachineErrors.Count | Should -BeGreaterThan 0
        }

        It -Name 'Should still return results for the succeeding machine' -Test {
            $script:perMachineSuccesses.Count | Should -Be 4
            ($script:perMachineSuccesses | Select-Object -ExpandProperty ComputerName -Unique) | Should -Be 'SRV02'
        }
    }

    Context -Name '-Account wildcard filter narrows StartName results' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockServices
            }
        }

        It -Name 'Should return only services whose StartName matches the wildcard' -Test {
            $result = @(Get-ServiceAccount -Account 'CONTOSO\svc-*')
            $result.Count | Should -Be 1
            $result[0].StartName | Should -Be 'CONTOSO\svc-app'
        }

        It -Name 'Should return all services when Account filter is absent' -Test {
            $result = @(Get-ServiceAccount)
            $result.Count | Should -Be 4
        }
    }

    Context -Name '-NonSystemOnly excludes built-in system logon accounts' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockServices
            }
        }

        It -Name 'Should exclude LocalSystem, NetworkService and LocalService case-insensitively' -Test {
            $result = @(Get-ServiceAccount -NonSystemOnly)
            $result.Count | Should -Be 1
            $result[0].StartName | Should -Be 'CONTOSO\svc-app'
        }

        It -Name 'Should exclude a lowercase NT AUTHORITY\LocalService variant' -Test {
            $result = @(Get-ServiceAccount -NonSystemOnly)
            ($result | Select-Object -ExpandProperty StartName) | Should -Not -Contain 'nt authority\localservice'
        }

        It -Name 'Should include all services when NonSystemOnly is not specified' -Test {
            $result = @(Get-ServiceAccount)
            $result.Count | Should -Be 4
        }
    }

    Context -Name 'PathName is preserved verbatim including arguments' -Fixture {

        BeforeAll {
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockServices
            }
        }

        It -Name 'Should preserve quoted path and arguments exactly' -Test {
            $result = @(Get-ServiceAccount -Account 'CONTOSO\svc-*')
            $result[0].PathName | Should -Be '"C:\Program Files\App\app.exe" -config "C:\config.xml" --verbose'
        }

        It -Name 'Should preserve service host arguments exactly' -Test {
            $result = @(Get-ServiceAccount -Account 'LocalSystem')
            $result[0].PathName | Should -Be 'C:\Windows\System32\svchost.exe -k netsvcs -p'
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-ServiceAccount -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-ServiceAccount -ComputerName $null } | Should -Throw
        }

        It -Name 'Should throw when Account is an empty string' -Test {
            { Get-ServiceAccount -Account '' } | Should -Throw
        }

        It -Name 'Should expose ComputerName with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-ServiceAccount'
            $attr = $cmd.Parameters['ComputerName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose ComputerName aliases CN and DNSHostName' -Test {
            $cmd = Get-Command -Name 'Get-ServiceAccount'
            $aliases = $cmd.Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should not support ShouldProcess (read-only auditing function)' -Test {
            $cmd = Get-Command -Name 'Get-ServiceAccount'
            $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $false
        }
    }
}
