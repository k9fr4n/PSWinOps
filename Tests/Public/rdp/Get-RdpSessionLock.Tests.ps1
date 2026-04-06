#Requires -Version 5.1

BeforeAll {
    # Import module
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force

    # Mock event XML for locked session
    $script:mockLockEventXml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <EventID>4800</EventID>
  </System>
  <EventData>
    <Data Name="TargetUserSid">S-1-5-21-123456789-1234567890-123456789-1001</Data>
    <Data Name="TargetUserName">testuser</Data>
    <Data Name="TargetDomainName">TESTDOMAIN</Data>
    <Data Name="SessionName">RDP-Tcp#2</Data>
  </EventData>
</Event>
'@

    # Helper function to create properly mocked event objects with ToXml() method
    function script:New-MockEventObject {
        param(
            [Parameter(Mandatory = $true)]
            [int]$EventId,
            [Parameter(Mandatory = $true)]
            [string]$XmlContent
        )

        $mockEvent = [PSCustomObject]@{
            Id          = $EventId
            TimeCreated = Get-Date
        }

        # Add ToXml() as a proper ScriptMethod
        $mockEvent | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
            return $XmlContent
        }.GetNewClosure() -Force

        return $mockEvent
    }

    # Create the mock lock event using the helper
    $script:mockLockEvent = New-MockEventObject -EventId 4800 -XmlContent $script:mockLockEventXml
}

Describe -Name 'Get-RdpSessionLock' -Fixture {

    Context -Name 'When querying lock events successfully' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-WinEvent' -ModuleName PSWinOps -MockWith {
                return $script:mockLockEvent
            }
        }

        It -Name 'Should return PSCustomObject with correct type name' -Test {
            $result = Get-RdpSessionLock
            $result.PSObject.TypeNames | Should -Contain 'PSWinOps.RdpSessionLock'
        }

        It -Name 'Should include all required properties' -Test {
            $result = Get-RdpSessionLock
            $result.PSObject.Properties.Name | Should -Contain 'TimeCreated'
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'UserName'
            $result.PSObject.Properties.Name | Should -Contain 'Action'
            $result.PSObject.Properties.Name | Should -Contain 'EventID'
        }

        It -Name 'Should map event ID 4800 to Locked action' -Test {
            $result = Get-RdpSessionLock
            $result.Action | Should -Be 'Locked'
        }

        It -Name 'Should format username as DOMAIN\User' -Test {
            $result = Get-RdpSessionLock
            $result.UserName | Should -Be 'TESTDOMAIN\testuser'
        }

        It -Name 'Should invoke Get-WinEvent exactly once' -Test {
            Get-RdpSessionLock
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName PSWinOps -Times 1 -Exactly
        }
    }

    Context -Name 'When no events are found' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-WinEvent' -ModuleName PSWinOps -MockWith {
                return $null
            }
        }

        It -Name 'Should return no output' -Test {
            $result = Get-RdpSessionLock
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When access is denied to Security log' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-WinEvent' -ModuleName PSWinOps -MockWith {
                throw [System.UnauthorizedAccessException]::new('Access denied')
            }
        }

        It -Name 'Should write error and not throw' -Test {
            { Get-RdpSessionLock -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It -Name 'Should return no output' -Test {
            $result = Get-RdpSessionLock -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context -Name 'When querying multiple computers via pipeline' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-WinEvent' -ModuleName PSWinOps -MockWith {
                return $script:mockLockEvent
            }
        }

        It -Name 'Should process all computers' -Test {
            $result = @('SRV01', 'SRV02') | Get-RdpSessionLock
            $result.Count | Should -Be 2
        }

        It -Name 'Should invoke Get-WinEvent once per computer' -Test {
            @('SRV01', 'SRV02', 'SRV03') | Get-RdpSessionLock
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName PSWinOps -Times 3 -Exactly
        }
    }

    Context -Name 'When custom StartTime is provided' -Fixture {

        BeforeEach {
            Mock -CommandName 'Get-WinEvent' -ModuleName PSWinOps -MockWith {
                return $script:mockLockEvent
            }
        }

        It -Name 'Should accept custom StartTime parameter' -Test {
            $customStart = (Get-Date).AddDays(-30)
            { Get-RdpSessionLock -StartTime $customStart } | Should -Not -Throw
        }
    }
}
