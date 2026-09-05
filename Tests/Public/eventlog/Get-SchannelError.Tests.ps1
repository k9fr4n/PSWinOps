#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    function New-MockSchannelEvent {
        param(
            [Parameter(Mandatory = $true)]
            [int]$EventId,
            [Parameter(Mandatory = $true)]
            [datetime]$TimeCreated,
            [Parameter(Mandatory = $true)]
            [string]$XmlContent,
            [string]$Message = 'Localized Schannel event message',
            [string]$LevelDisplayName = 'Error',
            [int]$Level = 2
        )

        $mockEvent = [PSCustomObject]@{
            Id                = $EventId
            TimeCreated       = $TimeCreated
            Message           = $Message
            LevelDisplayName  = $LevelDisplayName
            Level             = $Level
        }

        $mockEvent | Add-Member -MemberType ScriptMethod -Name 'ToXml' -Value {
            return $XmlContent
        }.GetNewClosure() -Force

        return $mockEvent
    }

    function New-SchannelXml {
        param(
            [string]$Protocol = '',
            [string]$AlertDescription = '',
            [string]$ErrorState = '',
            [string]$Role = '',
            [string]$RemoteHost = '',
            [string]$CertificateSubject = '',
            [string]$CipherSuite = '',
            [switch]$IncludeSecretField
        )

        $data = @(
            if ($Protocol) { "    <Data Name=`"Protocol`">$Protocol</Data>" }
            if ($AlertDescription) { "    <Data Name=`"AlertDescription`">$AlertDescription</Data>" }
            if ($ErrorState) { "    <Data Name=`"ErrorState`">$ErrorState</Data>" }
            if ($Role) { "    <Data Name=`"Role`">$Role</Data>" }
            if ($RemoteHost) { "    <Data Name=`"RemoteHost`">$RemoteHost</Data>" }
            if ($CertificateSubject) { "    <Data Name=`"CertificateSubject`">$CertificateSubject</Data>" }
            if ($CipherSuite) { "    <Data Name=`"CipherSuite`">$CipherSuite</Data>" }
            if ($IncludeSecretField) { '    <Data Name="PrivateKey">PRIVATE-KEY-MUST-NOT-APPEAR</Data>' }
        ) -join "`n"

        @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <EventData>
$data
  </EventData>
</Event>
"@
    }
}

Describe -Name 'Get-SchannelError' -Fixture {
    Context -Name 'Local XML parsing and classification' -Fixture {
        BeforeAll {
            $script:alertXml = New-SchannelXml -Protocol 'TLS 1.2' -AlertDescription '40' `
                -ErrorState '1203' -Role 'Client' -RemoteHost 'api.example.com'
            $script:alertEvent = New-MockSchannelEvent -EventId 36874 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') -XmlContent $script:alertXml `
                -Message 'TLS alert from api.example.com'
            $script:alertEvent2 = New-MockSchannelEvent -EventId 36874 `
                -TimeCreated (Get-Date '2026-09-04 09:00:00') -XmlContent $script:alertXml
            $script:certificateEvent = New-MockSchannelEvent -EventId 36870 `
                -TimeCreated (Get-Date '2026-09-04 08:00:00') `
                -XmlContent (New-SchannelXml -ErrorState '10013' -CertificateSubject 'CN=server.example.com' -IncludeSecretField)
            $script:cipherEvent = New-MockSchannelEvent -EventId 36888 `
                -TimeCreated (Get-Date '2026-09-04 07:00:00') `
                -XmlContent (New-SchannelXml -CipherSuite 'TLS_AES_256_GCM_SHA384')
            $script:unknownEvent = New-MockSchannelEvent -EventId 36888 `
                -TimeCreated (Get-Date '2026-09-04 06:00:00') `
                -XmlContent '<Event><EventData>' `
                -Message 'private key=TOPSECRET token=TOKENVALUE'

            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:unknownEvent, $script:cipherEvent, $script:certificateEvent, $script:alertEvent2, $script:alertEvent)
            }
        }

        It -Name 'Should parse fields, classify events, aggregate equivalents, and sort newest first' -Test {
            $result = @(Get-SchannelError)

            $result.Count | Should -Be 5
            $result[0].EventId | Should -Be 36874
            $result[0].ErrorType | Should -Be 'Alert'
            $result[0].Protocol | Should -Be 'TLS 1.2'
            $result[0].AlertDescription | Should -Be '40'
            $result[0].Role | Should -Be 'Client'
            $result[0].RemoteHost | Should -Be 'api.example.com'
            $result[0].FailureCount | Should -Be 2
            ($result | Where-Object ErrorType -eq 'Certificate').Count | Should -Be 1
            ($result | Where-Object ErrorType -eq 'Cipher').Count | Should -Be 1
            ($result | Where-Object ErrorType -eq 'Unknown').Count | Should -Be 1
            $result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.SchannelError'
        }

        It -Name 'Should preserve missing optional fields and redact sensitive message content' -Test {
            $result = @(Get-SchannelError)
            $certificate = $result | Where-Object EventId -eq 36870
            $unknown = $result | Where-Object ErrorType -eq 'Unknown'

            $certificate.Protocol | Should -Be ''
            $certificate.AlertDescription | Should -Be ''
            $certificate.RemoteHost | Should -Be ''
            $certificate.CertificateSubject | Should -Be 'CN=server.example.com'
            $unknown.Message | Should -Not -Match 'TOPSECRET|TOKENVALUE'
            $result | ConvertTo-Json -Depth 5 | Should -Not -Match 'PRIVATE-KEY-MUST-NOT-APPEAR|TOPSECRET|TOKENVALUE'
        }

        It -Name 'Should classify protocol-only XML as Protocol' -Test {
            $protocolEvent = New-MockSchannelEvent -EventId 9999 `
                -TimeCreated (Get-Date '2026-09-04 11:00:00') `
                -XmlContent (New-SchannelXml -Protocol 'TLS 1.3')
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $protocolEvent }

            $result = @(Get-SchannelError -EventId 9999)

            $result.ErrorType | Should -Be 'Protocol'
            $result.Protocol | Should -Be 'TLS 1.3'
            Should -Invoke -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $FilterHashtable.Id -contains 9999
            }
        }

        It -Name 'Should filter by remote host after XML extraction' -Test {
            $otherEvent = New-MockSchannelEvent -EventId 36874 `
                -TimeCreated (Get-Date '2026-09-04 10:30:00') `
                -XmlContent (New-SchannelXml -RemoteHost 'other.example.com')
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith {
                @($script:alertEvent, $otherEvent)
            }

            $result = @(Get-SchannelError -RemoteHost 'API.EXAMPLE.COM')

            $result.Count | Should -Be 1
            $result.RemoteHost | Should -Be 'api.example.com'
        }
    }

    Context -Name 'Remote, credentials, pipeline, and error isolation' -Fixture {
        BeforeEach {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated WinRM failure on SRV01'
                }

                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.SchannelError'
                    ComputerName       = $ComputerName
                    EventTime          = '2026-09-04T10:00:00.0000000'
                    EventId            = 36888
                    ErrorType          = 'Alert'
                    Severity           = 'Error'
                    Role               = 'Server'
                    Protocol           = 'TLS 1.2'
                    AlertDescription   = '40'
                    ErrorState         = '1203'
                    RemoteHost         = 'api.example.com'
                    CertificateSubject = ''
                    FailureCount       = 1
                    Message            = ''
                    Timestamp          = '2026-09-04T10:00:00.0000000'
                }
            }
        }

        It -Name 'Should query a remote machine and propagate credentials' -Test {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', $securePassword)
            $result = @(Get-SchannelError -ComputerName 'SRV02' -Credential $credential)

            $result.ComputerName | Should -Be 'SRV02'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $ComputerName -eq 'SRV02' -and $Credential -eq $credential
            }
        }

        It -Name 'Should continue after a per-machine failure in pipeline input' -Test {
            $output = 'SRV01', 'SRV02' | Get-SchannelError -ErrorAction Continue 2>&1

            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
            @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -BeGreaterThan 0
            @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 1
            ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).ComputerName | Should -Be 'SRV02'
        }
    }

    Context -Name 'Parameter validation and metadata' -Fixture {
        It -Name 'Should reject invalid ComputerName, Days, MaxEvents, and EventId' -Test {
            { Get-SchannelError -ComputerName '' } | Should -Throw
            { Get-SchannelError -ComputerName $null } | Should -Throw
            { Get-SchannelError -Days 0 } | Should -Throw
            { Get-SchannelError -Days 3651 } | Should -Throw
            { Get-SchannelError -MaxEvents 0 } | Should -Throw
            { Get-SchannelError -MaxEvents 10001 } | Should -Throw
            { Get-SchannelError -EventId @() } | Should -Throw
        }

        It -Name 'Should expose pipeline support and aliases on ComputerName' -Test {
            $command = Get-Command -Name 'Get-SchannelError'
            $parameterAttribute = $command.Parameters['ComputerName'].Attributes.Where({
                $_ -is [System.Management.Automation.ParameterAttribute]
            })[0]

            $parameterAttribute.ValueFromPipeline | Should -Be $true
            $parameterAttribute.ValueFromPipelineByPropertyName | Should -Be $true
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
            $command.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should expose the required output properties' -Test {
            $event = New-MockSchannelEvent -EventId 36874 `
                -TimeCreated (Get-Date '2026-09-04 10:00:00') `
                -XmlContent (New-SchannelXml -AlertDescription '40')
            Mock -CommandName 'Get-WinEvent' -ModuleName 'PSWinOps' -MockWith { $event }

            $result = @(Get-SchannelError)
            foreach ($property in @(
                'ComputerName', 'EventTime', 'EventId', 'ErrorType', 'Severity', 'Role',
                'Protocol', 'AlertDescription', 'ErrorState', 'RemoteHost',
                'CertificateSubject', 'FailureCount', 'Message', 'Timestamp'
            )) {
                $result[0].PSObject.Properties.Name | Should -Contain $property
            }
        }
    }
}
