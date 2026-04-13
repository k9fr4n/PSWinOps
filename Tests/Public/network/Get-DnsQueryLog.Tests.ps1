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

    # Build a mock XML event resembling DNS Client Event ID 3008
    $script:mockEventXml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <Provider Name="Microsoft-Windows-DNS-Client" />
    <EventID>3008</EventID>
    <TimeCreated SystemTime="2026-04-13T10:00:00.000Z" />
    <Execution ProcessID="1234" ThreadID="5678" />
  </System>
  <EventData>
    <Data Name="QueryName">www.example.com.</Data>
    <Data Name="QueryType">1</Data>
    <Data Name="QueryResults">93.184.216.34;</Data>
    <Data Name="QueryStatus">0</Data>
  </EventData>
</Event>
'@

    $script:mockEvent = [PSCustomObject]@{
        Id          = 3008
        TimeCreated = [datetime]'2026-04-13T10:00:00Z'
        Message     = 'DNS query completed'
    }
    $script:mockEvent | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
        return $script:mockEventXml
    }
}

Describe 'Get-DnsQueryLog' {

    Context 'Parameter validation' {
        BeforeAll {
            $script:commandInfo = Get-Command -Name 'Get-DnsQueryLog' -Module $script:ModuleName
        }

        It -Name 'Should have CmdletBinding' -Test {
            $script:commandInfo.CmdletBinding | Should -BeTrue
        }

        It -Name 'Should have OutputType PSWinOps.DnsQueryLog' -Test {
            $script:commandInfo.OutputType.Name | Should -Contain 'PSWinOps.DnsQueryLog'
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

        It -Name 'Should have MaxEvents with ValidateRange 1-10000' -Test {
            $param = $script:commandInfo.Parameters['MaxEvents']
            $param | Should -Not -BeNullOrEmpty
            $range = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $range.MinRange | Should -Be 1
            $range.MaxRange | Should -Be 10000
        }

        It -Name 'Should have DomainFilter parameter' -Test {
            $script:commandInfo.Parameters['DomainFilter'] | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have QueryType with ValidateSet' -Test {
            $param = $script:commandInfo.Parameters['QueryType']
            $param | Should -Not -BeNullOrEmpty
            $vs = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $vs.ValidValues | Should -Contain 'A'
            $vs.ValidValues | Should -Contain 'AAAA'
        }

        It -Name 'Should have Since datetime parameter' -Test {
            $param = $script:commandInfo.Parameters['Since']
            $param | Should -Not -BeNullOrEmpty
            $param.ParameterType.Name | Should -Be 'DateTime'
        }

        It -Name 'Should have EnableLog switch' -Test {
            $param = $script:commandInfo.Parameters['EnableLog']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -BeTrue
        }

        It -Name 'Should have Credential parameter' -Test {
            $param = $script:commandInfo.Parameters['Credential']
            $param | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should reject MaxEvents of 0' -Test {
            { Get-DnsQueryLog -MaxEvents 0 } | Should -Throw
        }

        It -Name 'Should reject empty ComputerName' -Test {
            { Get-DnsQueryLog -ComputerName '' } | Should -Throw
        }

        It -Name 'Should reject invalid QueryType' -Test {
            { Get-DnsQueryLog -QueryType 'INVALID' } | Should -Throw
        }
    }

    Context 'Comment-based help' {
        BeforeAll {
            $script:helpInfo = Get-Help -Name 'Get-DnsQueryLog' -Full
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

        It -Name 'Should have Author in NOTES' -Test {
            ($script:helpInfo.alertSet | Out-String) | Should -Match 'Franck SALLET'
        }
    }

    Context 'Happy path - local execution' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @(
                    @{
                        TimeCreated  = '2026-04-13T10:00:00.0000000+00:00'
                        EventId      = 3008
                        QueryName    = 'www.example.com.'
                        QueryType    = 1
                        QueryResults = '93.184.216.34;'
                        QueryStatus  = 0
                        ProcessId    = 1234
                        ProcessName  = 'chrome'
                    },
                    @{
                        TimeCreated  = '2026-04-13T10:00:01.0000000+00:00'
                        EventId      = 3008
                        QueryName    = 'api.github.com.'
                        QueryType    = 28
                        QueryResults = '2606:50c0:8000::64;'
                        QueryStatus  = 0
                        ProcessId    = 5678
                        ProcessName  = 'git'
                    }
                )
            }
            $script:results = @(Get-DnsQueryLog)
        }

        It -Name 'Should return results' -Test {
            $script:results.Count | Should -Be 2
        }

        It -Name 'Should have PSTypeName PSWinOps.DnsQueryLog' -Test {
            $script:results[0].PSTypeNames[0] | Should -Be 'PSWinOps.DnsQueryLog'
        }

        It -Name 'Should have ComputerName' -Test {
            $script:results[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should have Timestamp in ISO 8601' -Test {
            $script:results[0].Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }

        It -Name 'Should map QueryType 1 to A' -Test {
            $script:results[0].QueryType | Should -Be 'A'
        }

        It -Name 'Should map QueryType 28 to AAAA' -Test {
            $script:results[1].QueryType | Should -Be 'AAAA'
        }

        It -Name 'Should strip trailing dot from QueryName' -Test {
            $script:results[0].QueryName | Should -Be 'www.example.com'
        }

        It -Name 'Should parse QueryResults' -Test {
            $script:results[0].Result | Should -Be '93.184.216.34'
        }

        It -Name 'Should have Status Success' -Test {
            $script:results[0].Status | Should -Be 'Success'
        }

        It -Name 'Should include ProcessName' -Test {
            $script:results[0].ProcessName | Should -Be 'chrome'
        }

        It -Name 'Should include ProcessId' -Test {
            $script:results[0].ProcessId | Should -Be 1234
        }

        It -Name 'Should include all expected properties' -Test {
            $props = $script:results[0].PSObject.Properties.Name
            foreach ($p in @('ComputerName', 'TimeCreated', 'QueryName', 'QueryType', 'Result', 'Status', 'ProcessName', 'ProcessId', 'EventId', 'Timestamp')) {
                $props | Should -Contain $p
            }
        }
    }

    Context 'Remote single machine' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @(
                    @{
                        TimeCreated  = '2026-04-13T10:00:00.0000000+00:00'
                        EventId      = 3008
                        QueryName    = 'dns.google.'
                        QueryType    = 1
                        QueryResults = '8.8.8.8;'
                        QueryStatus  = 0
                        ProcessId    = 100
                        ProcessName  = 'svchost'
                    }
                )
            }
            $script:results = @(Get-DnsQueryLog -ComputerName 'SRV01')
        }

        It -Name 'Should target remote machine' -Test {
            $script:results[0].ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Pipeline - multiple machines' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @(
                    @{
                        TimeCreated  = '2026-04-13T10:00:00.0000000+00:00'
                        EventId      = 3008
                        QueryName    = 'test.local.'
                        QueryType    = 1
                        QueryResults = '10.0.0.1;'
                        QueryStatus  = 0
                        ProcessId    = 1
                        ProcessName  = 'dns'
                    }
                )
            }
            $script:results = @('SRV01', 'SRV02' | Get-DnsQueryLog)
        }

        It -Name 'Should process both machines' -Test {
            $machines = $script:results | Select-Object -ExpandProperty ComputerName -Unique
            $machines | Should -Contain 'SRV01'
            $machines | Should -Contain 'SRV02'
        }
    }

    Context 'DomainFilter' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @(
                    @{
                        TimeCreated = '2026-04-13T10:00:00.0000000+00:00'; EventId = 3008
                        QueryName = 'www.google.com.'; QueryType = 1; QueryResults = '1.2.3.4;'
                        QueryStatus = 0; ProcessId = 1; ProcessName = 'chrome'
                    },
                    @{
                        TimeCreated = '2026-04-13T10:00:01.0000000+00:00'; EventId = 3008
                        QueryName = 'api.github.com.'; QueryType = 1; QueryResults = '5.6.7.8;'
                        QueryStatus = 0; ProcessId = 2; ProcessName = 'git'
                    }
                )
            }
        }

        It -Name 'Should filter by domain wildcard' -Test {
            $results = @(Get-DnsQueryLog -DomainFilter '*.google.com')
            $results.Count | Should -Be 1
            $results[0].QueryName | Should -Be 'www.google.com'
        }
    }

    Context 'QueryType filter' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @(
                    @{
                        TimeCreated = '2026-04-13T10:00:00.0000000+00:00'; EventId = 3008
                        QueryName = 'test.com.'; QueryType = 1; QueryResults = '1.2.3.4;'
                        QueryStatus = 0; ProcessId = 1; ProcessName = 'test'
                    },
                    @{
                        TimeCreated = '2026-04-13T10:00:01.0000000+00:00'; EventId = 3008
                        QueryName = 'test.com.'; QueryType = 28; QueryResults = '::1;'
                        QueryStatus = 0; ProcessId = 1; ProcessName = 'test'
                    }
                )
            }
        }

        It -Name 'Should filter by QueryType A' -Test {
            $results = @(Get-DnsQueryLog -QueryType 'A')
            $results.Count | Should -Be 1
            $results[0].QueryType | Should -Be 'A'
        }

        It -Name 'Should filter by QueryType AAAA' -Test {
            $results = @(Get-DnsQueryLog -QueryType 'AAAA')
            $results.Count | Should -Be 1
            $results[0].QueryType | Should -Be 'AAAA'
        }
    }

    Context 'Status mapping' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                @(
                    @{
                        TimeCreated = '2026-04-13T10:00:00.0000000+00:00'; EventId = 3008
                        QueryName = 'nx.test.'; QueryType = 1; QueryResults = ''
                        QueryStatus = 9003; ProcessId = 1; ProcessName = 'test'
                    },
                    @{
                        TimeCreated = '2026-04-13T10:00:01.0000000+00:00'; EventId = 3008
                        QueryName = 'timeout.test.'; QueryType = 1; QueryResults = ''
                        QueryStatus = 9501; ProcessId = 1; ProcessName = 'test'
                    }
                )
            }
        }

        It -Name 'Should map 9003 to NameNotFound' -Test {
            $results = @(Get-DnsQueryLog)
            ($results | Where-Object QueryName -eq 'nx.test').Status | Should -Be 'NameNotFound'
        }

        It -Name 'Should map 9501 to Timeout' -Test {
            $results = @(Get-DnsQueryLog)
            ($results | Where-Object QueryName -eq 'timeout.test').Status | Should -Be 'Timeout'
        }
    }

    Context 'Per-machine error isolation' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                if ($ComputerName -eq 'BADHOST') {
                    throw 'Connection refused'
                }
                @(
                    @{
                        TimeCreated = '2026-04-13T10:00:00.0000000+00:00'; EventId = 3008
                        QueryName = 'ok.test.'; QueryType = 1; QueryResults = '1.1.1.1;'
                        QueryStatus = 0; ProcessId = 1; ProcessName = 'test'
                    }
                )
            }
        }

        It -Name 'Should continue after machine failure' -Test {
            $results = @('BADHOST', 'GOODHOST' | Get-DnsQueryLog -ErrorAction SilentlyContinue)
            $results | Where-Object ComputerName -eq 'GOODHOST' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith { @() }
        }

        It -Name 'Should produce verbose messages' -Test {
            $verbose = Get-DnsQueryLog -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $verbose | Should -Not -BeNullOrEmpty
        }
    }
}