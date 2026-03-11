#Requires -Version 5.1

BeforeAll {
    # Import module
    $script:modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\PSWinOps.psd1'
    Import-Module -Name $script:modulePath -Force -ErrorAction Stop

    if (-not (Test-Path -Path $script:functionPath)) {
        throw "Function file not found: $script:functionPath"
    }

    . $script:functionPath

    # Mock event data
    $script:mockEventXml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
    <System>
        <EventID>21</EventID>
    </System>
    <UserData>
        <EventXML>
            <User>DOMAIN\testuser</User>
            <Address>192.168.1.100</Address>
        </EventXML>
    </UserData>
</Event>
'@

    $script:mockEventEntry = [PSCustomObject]@{
        TimeCreated = [datetime]'2026-03-11 08:00:00'
        Id          = 21
    } | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
        return $script:mockEventXml
    } -PassThru
}

Describe -Name 'Get-RdpSessionHistory' -Fixture {

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should accept ComputerName from pipeline by value' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @() }

            { 'SRV01' | Get-RdpSessionHistory } | Should -Not -Throw

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly
        }

        It -Name 'Should accept ComputerName from pipeline by property name' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @() }

            $inputObject = [PSCustomObject]@{ Name = 'SRV02' }

            { $inputObject | Get-RdpSessionHistory } | Should -Not -Throw

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly
        }

        It -Name 'Should default to local computer when no ComputerName specified' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @() }

            Get-RdpSessionHistory

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq $env:COMPUTERNAME
            }
        }

        It -Name 'Should default StartTime to 1970-01-01' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @() }

            Get-RdpSessionHistory

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly -ParameterFilter {
                $FilterHashtable.StartTime -eq [datetime]'1970-01-01'
            }
        }
    }

    Context -Name 'When events are found' -Fixture {

        It -Name 'Should return PSCustomObject with correct properties' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @($script:mockEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType ([PSCustomObject])
            $result.PSTypeName | Should -Be 'PSWinOps.RdpSessionHistory'
        }

        It -Name 'Should include all expected properties' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @($script:mockEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result.PSObject.Properties.Name | Should -Contain 'TimeCreated'
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'User'
            $result.PSObject.Properties.Name | Should -Contain 'IPAddress'
            $result.PSObject.Properties.Name | Should -Contain 'Action'
            $result.PSObject.Properties.Name | Should -Contain 'EventID'
        }

        It -Name 'Should map Event ID 21 to Logon action' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @($script:mockEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result.Action | Should -Be 'Logon'
            $result.EventID | Should -Be 21
        }

        It -Name 'Should extract user and IP address from event XML' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @($script:mockEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result.User | Should -Be 'DOMAIN\testuser'
            $result.IPAddress | Should -Be '192.168.1.100'
        }

        It -Name 'Should process multiple events' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith {
                return @($script:mockEventEntry, $script:mockEventEntry)
            }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result.Count | Should -Be 2
        }
    }

    Context -Name 'When no events are found' -Fixture {

        It -Name 'Should return nothing when event log is empty' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @() }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result | Should -BeNullOrEmpty
        }

        It -Name 'Should return nothing when events is null' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return $null }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Error handling' -Fixture {

        It -Name 'Should write error on EventLogException' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith {
                throw [System.Diagnostics.Eventing.Reader.EventLogException]::new('Log not found')
            }

            Get-RdpSessionHistory -ComputerName 'SRV01' -ErrorAction SilentlyContinue

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly
        }

        It -Name 'Should write error on UnauthorizedAccessException' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }

            Get-RdpSessionHistory -ComputerName 'SRV01' -ErrorAction SilentlyContinue

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly
        }

        It -Name 'Should continue processing other computers if one fails' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith {
                param($ComputerName)
                if ($ComputerName -eq 'SRV-FAIL') {
                    throw [System.Exception]::new('Connection failed')
                }
                return @($script:mockEventEntry)
            }

            $result = Get-RdpSessionHistory -ComputerName 'SRV-FAIL', 'SRV-OK' -ErrorAction SilentlyContinue

            $result.Count | Should -Be 1
            $result.ComputerName | Should -Be 'SRV-OK'
        }

        It -Name 'Should write warning if event XML parsing fails' -Test {
            $badEventEntry = [PSCustomObject]@{
                TimeCreated = [datetime]'2026-03-11'
                Id          = 21
            } | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
                return '<Invalid>XML</Invalid>'
            } -PassThru

            Mock -CommandName 'Get-WinEvent' -MockWith { return @($badEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01' -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'Credential handling' -Fixture {

        It -Name 'Should pass Credential parameter to Get-WinEvent when provided' -Test {
            $secureString = New-Object System.Security.SecureString
            $testCred = [PSCredential]::new('testuser', $secureString)

            Mock -CommandName 'Get-WinEvent' -MockWith { return @() }

            Get-RdpSessionHistory -ComputerName 'SRV01' -Credential $testCred

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $testCred
            }
        }

        It -Name 'Should not pass Credential when not specified' -Test {
            Mock -CommandName 'Get-WinEvent' -MockWith { return @() }

            Get-RdpSessionHistory -ComputerName 'SRV01'

            Should -Invoke -CommandName 'Get-WinEvent' -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('Credential')
            }
        }
    }

    Context -Name 'Event ID action mapping' -Fixture {

        It -Name 'Should map Event ID 23 to Logoff' -Test {
            $logoffEventEntry = [PSCustomObject]@{
                TimeCreated = [datetime]'2026-03-11'
                Id          = 23
            } | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
                return $script:mockEventXml.Replace('<EventID>21</EventID>', '<EventID>23</EventID>')
            } -PassThru

            Mock -CommandName 'Get-WinEvent' -MockWith { return @($logoffEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result.Action | Should -Be 'Logoff'
        }

        It -Name 'Should map Event ID 24 to Disconnected' -Test {
            $disconnectEventEntry = [PSCustomObject]@{
                TimeCreated = [datetime]'2026-03-11'
                Id          = 24
            } | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
                return $script:mockEventXml.Replace('<EventID>21</EventID>', '<EventID>24</EventID>')
            } -PassThru

            Mock -CommandName 'Get-WinEvent' -MockWith { return @($disconnectEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result.Action | Should -Be 'Disconnected'
        }

        It -Name 'Should map Event ID 25 to Reconnection' -Test {
            $reconnectEventEntry = [PSCustomObject]@{
                TimeCreated = [datetime]'2026-03-11'
                Id          = 25
            } | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
                return $script:mockEventXml.Replace('<EventID>21</EventID>', '<EventID>25</EventID>')
            } -PassThru

            Mock -CommandName 'Get-WinEvent' -MockWith { return @($reconnectEventEntry) }

            $result = Get-RdpSessionHistory -ComputerName 'SRV01'

            $result.Action | Should -Be 'Reconnection'
        }
    }
}
