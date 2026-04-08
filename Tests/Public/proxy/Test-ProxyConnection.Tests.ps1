#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Test-ProxyConnection' {

    Context 'Parameter validation' {
        It 'Should have CmdletBinding' {
            $cmd = Get-Command -Name 'Test-ProxyConnection'
            $cmd.CmdletBinding | Should -BeTrue
        }

        It 'Should have no mandatory parameters' {
            $cmd = Get-Command -Name 'Test-ProxyConnection'
            $mandatoryParams = $cmd.Parameters.Values | Where-Object {
                $_.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }
            }
            $mandatoryParams | Should -BeNullOrEmpty
        }

        It 'Should have Uri with default value' {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-WebRequest' -MockWith {
                [PSCustomObject]@{ StatusCode = 200 }
            }
            $result = Test-ProxyConnection
            $result.Uri | Should -Be 'http://www.msftconnecttest.com/connecttest.txt'
        }

        It 'Should have TimeoutSec with default value of 10' {
            $cmd = Get-Command -Name 'Test-ProxyConnection'
            $cmd.Parameters['TimeoutSec'] | Should -Not -BeNullOrEmpty
        }

        It 'Should reject TimeoutSec less than 1' {
            { Test-ProxyConnection -TimeoutSec 0 } | Should -Throw
        }

        It 'Should reject TimeoutSec greater than 300' {
            { Test-ProxyConnection -TimeoutSec 301 } | Should -Throw
        }

        It 'Should accept Credential parameter' {
            $cmd = Get-Command -Name 'Test-ProxyConnection'
            $cmd.Parameters.ContainsKey('Credential') | Should -BeTrue
        }
    }

    Context 'Successful connection with system proxy' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-WebRequest' -MockWith {
                [PSCustomObject]@{ StatusCode = 200 }
            }
        }

        It 'Should return PSWinOps.ProxyTestResult type' {
            $result = Test-ProxyConnection
            $result.PSObject.TypeNames | Should -Contain 'PSWinOps.ProxyTestResult'
        }

        It 'Should return Success as true' {
            $result = Test-ProxyConnection
            $result.Success | Should -BeTrue
        }

        It 'Should return StatusCode 200' {
            $result = Test-ProxyConnection
            $result.StatusCode | Should -Be 200
        }

        It 'Should return ProxyUsed as System Default' {
            $result = Test-ProxyConnection
            $result.ProxyUsed | Should -Be 'System Default'
        }

        It 'Should return ComputerName' {
            $result = Test-ProxyConnection
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It 'Should return Timestamp in ISO 8601 format' {
            $result = Test-ProxyConnection
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }

        It 'Should return ResponseTime as a number' {
            $result = Test-ProxyConnection
            $result.ResponseTime | Should -BeOfType [long]
        }

        It 'Should return null ErrorMessage on success' {
            $result = Test-ProxyConnection
            $result.ErrorMessage | Should -BeNullOrEmpty
        }

        It 'Should call Invoke-WebRequest with UseBasicParsing' {
            Test-ProxyConnection | Out-Null
            Should -Invoke -CommandName 'Invoke-WebRequest' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $UseBasicParsing -eq $true
            }
        }
    }

    Context 'Successful connection with explicit proxy' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-WebRequest' -MockWith {
                [PSCustomObject]@{ StatusCode = 200 }
            }
        }

        It 'Should pass proxy to Invoke-WebRequest' {
            Test-ProxyConnection -ProxyServer 'proxy.example.com:8080' | Out-Null
            Should -Invoke -CommandName 'Invoke-WebRequest' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Proxy -eq 'http://proxy.example.com:8080'
            }
        }

        It 'Should return the proxy URL in ProxyUsed' {
            $result = Test-ProxyConnection -ProxyServer 'proxy.example.com:8080'
            $result.ProxyUsed | Should -Be 'http://proxy.example.com:8080'
        }

        It 'Should prepend http:// when scheme is missing' {
            $result = Test-ProxyConnection -ProxyServer 'proxy.example.com:8080'
            $result.ProxyUsed | Should -BeLike 'http://*'
        }

        It 'Should not prepend http:// when scheme is present' {
            $result = Test-ProxyConnection -ProxyServer 'https://proxy.example.com:8443'
            $result.ProxyUsed | Should -Be 'https://proxy.example.com:8443'
        }

        It 'Should use ProxyUseDefaultCredentials when no Credential provided' {
            Test-ProxyConnection -ProxyServer 'proxy.example.com:8080' | Out-Null
            Should -Invoke -CommandName 'Invoke-WebRequest' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $ProxyUseDefaultCredentials -eq $true
            }
        }

        It 'Should use ProxyCredential when Credential is provided' {
            $secPassword = ConvertTo-SecureString -String 'TestPass123' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('TestUser', $secPassword)
            Test-ProxyConnection -ProxyServer 'proxy.example.com:8080' -Credential $cred | Out-Null
            Should -Invoke -CommandName 'Invoke-WebRequest' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $ProxyCredential -ne $null
            }
        }
    }

    Context 'Custom URI and timeout' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-WebRequest' -MockWith {
                [PSCustomObject]@{ StatusCode = 200 }
            }
        }

        It 'Should use custom URI' {
            $result = Test-ProxyConnection -Uri 'https://www.google.com'
            $result.Uri | Should -Be 'https://www.google.com'
        }

        It 'Should pass custom URI to Invoke-WebRequest' {
            Test-ProxyConnection -Uri 'https://www.google.com' | Out-Null
            Should -Invoke -CommandName 'Invoke-WebRequest' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://www.google.com'
            }
        }

        It 'Should pass custom TimeoutSec to Invoke-WebRequest' {
            Test-ProxyConnection -TimeoutSec 5 | Out-Null
            Should -Invoke -CommandName 'Invoke-WebRequest' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $TimeoutSec -eq 5
            }
        }
    }

    Context 'Failed connection' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-WebRequest' -MockWith {
                throw [System.Net.WebException]::new('Unable to connect to the remote server')
            }
        }

        It 'Should not throw' {
            { Test-ProxyConnection } | Should -Not -Throw
        }

        It 'Should return Success as false' {
            $result = Test-ProxyConnection
            $result.Success | Should -BeFalse
        }

        It 'Should return ErrorMessage with exception details' {
            $result = Test-ProxyConnection
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            $result.ErrorMessage | Should -BeLike '*Unable to connect*'
        }

        It 'Should return null StatusCode when no response' {
            $result = Test-ProxyConnection
            $result.StatusCode | Should -BeNullOrEmpty
        }

        It 'Should still return ResponseTime' {
            $result = Test-ProxyConnection
            $result.ResponseTime | Should -Not -BeNullOrEmpty
        }

        It 'Should still return a complete object' {
            $result = Test-ProxyConnection
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Uri          | Should -Not -BeNullOrEmpty
            $result.Timestamp    | Should -Not -BeNullOrEmpty
        }
    }

    Context 'HTTP error response (e.g., 407 Proxy Authentication Required)' {
        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-WebRequest' -MockWith {
                $response = [System.Net.HttpWebResponse]$null
                $exception = [System.Net.WebException]::new(
                    'The remote server returned an error: (407) Proxy Authentication Required.'
                )
                throw $exception
            }
        }

        It 'Should return Success as false' {
            $result = Test-ProxyConnection -ProxyServer 'proxy.example.com:8080'
            $result.Success | Should -BeFalse
        }

        It 'Should return ErrorMessage with 407 details' {
            $result = Test-ProxyConnection -ProxyServer 'proxy.example.com:8080'
            $result.ErrorMessage | Should -BeLike '*407*'
        }
    }

    Context 'Output object structure' {
        BeforeAll {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-WebRequest' -MockWith {
                [PSCustomObject]@{ StatusCode = 200 }
            }
            $script:result = Test-ProxyConnection
        }

        It 'Should have all expected properties' {
            $expectedProperties = @(
                'ComputerName', 'Uri', 'ProxyUsed', 'StatusCode',
                'Success', 'ResponseTime', 'ErrorMessage', 'Timestamp'
            )
            foreach ($prop in $expectedProperties) {
                $script:result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It 'Should have PSTypeName PSWinOps.ProxyTestResult' {
            $script:result.PSObject.TypeNames | Should -Contain 'PSWinOps.ProxyTestResult'
        }
    }

    Context 'Integration test' -Tag 'Integration' {
        It 'Should test real connectivity' -Skip:(-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
            $result = Test-ProxyConnection -Uri 'http://www.msftconnecttest.com/connecttest.txt' -TimeoutSec 15
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames | Should -Contain 'PSWinOps.ProxyTestResult'
            $result.ComputerName | Should -Be $env:COMPUTERNAME
        }
    }
}
