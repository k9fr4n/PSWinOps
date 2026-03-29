#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    if (-not (Get-Command -Name 'Get-CertificationAuthority' -ErrorAction SilentlyContinue)) {
        function global:Get-CertificationAuthority { param($ComputerName) }
    }
}

Describe 'Get-CertificateAuthorityHealth' {
    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus       = 'Running'
            CAName              = 'Contoso-Root-CA'
            CAType              = 'Enterprise Root CA'
            CACertExpiry        = '01/01/2030 00:00:00'
            CACertDaysRemaining = 1372
            CRLPublishOK        = $true
            CAPingOK            = $true
        }
    }

    Context 'When CA role is unavailable' {
        BeforeAll {
            $script:mockRoleUnavailable = @{
                ServiceStatus = 'NotFound'; CAName = 'Unknown'; CAType = 'Unknown'
                CACertExpiry = 'Unknown'; CACertDaysRemaining = -1
                CRLPublishOK = $false; CAPingOK = $false
            }
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRoleUnavailable }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return RoleUnavailable health status' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It -Name 'Should report NotFound service status' -Test { $script:result.ServiceStatus | Should -Be 'NotFound' }
        It -Name 'Should populate the ComputerName property' -Test { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'When CA is healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Healthy overall health' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return correct CA name' -Test { $script:result.CAName | Should -Be 'Contoso-Root-CA' }
        It -Name 'Should return correct CA type' -Test { $script:result.CAType | Should -Be 'Enterprise Root CA' }
        It -Name 'Should report CRL publish as OK' -Test { $script:result.CRLPublishOK | Should -BeTrue }
        It -Name 'Should report CA ping as OK' -Test { $script:result.CAPingOK | Should -BeTrue }
        It -Name 'Should report positive days remaining' -Test { $script:result.CACertDaysRemaining | Should -BeGreaterThan 0 }
    }

    Context 'When CertSvc service is stopped' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.ServiceStatus = 'Stopped'; return $data
            }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Critical overall health' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should report Stopped service status' -Test { $script:result.ServiceStatus | Should -Be 'Stopped' }
    }

    Context 'When CA certificate has expired' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone()
                $data.CACertDaysRemaining = 0; $data.CACertExpiry = '01/01/2020 00:00:00'
                return $data
            }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Critical overall health' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should report zero or negative days remaining' -Test { $script:result.CACertDaysRemaining | Should -BeLessOrEqual 0 }
    }

    Context 'When CA ping fails' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.CAPingOK = $false; return $data
            }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Critical overall health' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
        It -Name 'Should report CA ping as failed' -Test { $script:result.CAPingOK | Should -BeFalse }
    }

    Context 'When CA certificate is expiring within 30 days' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.CACertDaysRemaining = 20; return $data
            }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Degraded overall health' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
        It -Name 'Should report days remaining below 30' -Test { $script:result.CACertDaysRemaining | Should -BeLessThan 30 }
        It -Name 'Should report days remaining above zero' -Test { $script:result.CACertDaysRemaining | Should -BeGreaterThan 0 }
    }

    Context 'When CRL publish has failed' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $data = $script:mockRemoteData.Clone(); $data.CRLPublishOK = $false; return $data
            }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return Degraded overall health' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
        It -Name 'Should report CRL publish as failed' -Test { $script:result.CRLPublishOK | Should -BeFalse }
    }

    Context 'When executing against a remote computer' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:result = Get-CertificateAuthorityHealth -ComputerName 'SRV01'
        }
        It -Name 'Should return a result with Timestamp' -Test { $script:result.Timestamp | Should -Not -BeNullOrEmpty }
        It -Name 'Should return a populated result object' -Test { $script:result | Should -Not -BeNullOrEmpty }
        It -Name 'Should set the ComputerName property' -Test { $script:result.ComputerName | Should -Be 'SRV01' }
    }

    Context 'When processing pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData }
            $script:pipelineResults = @('SRV01', 'SRV02') | Get-CertificateAuthorityHealth
        }
        It -Name 'Should return a result for each pipeline input' -Test { $script:pipelineResults.Count | Should -Be 2 }
        It -Name 'Should return distinct ComputerName values' -Test {
            $names = @($script:pipelineResults) | Select-Object -ExpandProperty ComputerName -Unique
            @($names).Count | Should -Be 2
        }
    }

    Context 'When remote execution fails' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should throw when ErrorAction is Stop' -Test { { Get-CertificateAuthorityHealth -ComputerName 'SRV01' -ErrorAction 'Stop' } | Should -Throw }
        It -Name 'Should return null when errors are silenced' -Test {
            $failResult = Get-CertificateAuthorityHealth -ComputerName 'SRV01' -ErrorAction 'SilentlyContinue'
            $failResult | Should -BeNullOrEmpty
        }
    }

    Context 'When validating parameters' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-CertificateAuthorityHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-CertificateAuthorityHealth -ComputerName $null } | Should -Throw }
        It -Name 'Should support pipeline input by property name' -Test {
            $pipelineAttr = (Get-Command -Name 'Get-CertificateAuthorityHealth').Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName }
            $pipelineAttr | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Local execution - CA healthy' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'CertSvc'; Status = 'Running' }
            }
            Mock -CommandName 'Get-Command' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'certutil.exe' }
            } -ParameterFilter { $Name -eq 'certutil.exe' }

            $script:localCA = Get-CertificateAuthorityHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return result for local CA' { $script:localCA | Should -Not -BeNullOrEmpty }
        It 'Should have PSTypeName' { $script:localCA.PSObject.TypeNames[0] | Should -Be 'PSWinOps.CertificateAuthorityHealth' }
        It 'Should set ComputerName' { $script:localCA.ComputerName | Should -Be $env:COMPUTERNAME.ToUpper() }
    }

    Context 'Local execution - CertSvc not installed' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'not found' }
            $script:localCAMissing = Get-CertificateAuthorityHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return RoleUnavailable' { $script:localCAMissing.OverallHealth | Should -Be 'RoleUnavailable' }
    }

}
