#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    if (-not (Get-Command -Name 'Get-SmbShare' -ErrorAction SilentlyContinue)) {
        function global:Get-SmbShare {  }
    }
    if (-not (Get-Command -Name 'Get-SmbSession' -ErrorAction SilentlyContinue)) {
        function global:Get-SmbSession {  }
    }
    if (-not (Get-Command -Name 'Get-SmbOpenFile' -ErrorAction SilentlyContinue)) {
        function global:Get-SmbOpenFile {  }
    }
    if (-not (Get-Command -Name 'Get-FsrmQuota' -ErrorAction SilentlyContinue)) {
        function global:Get-FsrmQuota {  }
    }
}

Describe 'Get-FileServerHealth' {
    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus = 'Running'; RoleAvailable = $true; TotalShares = 5
            OpenSessions = 12; OpenFiles = 45; FSRMAvailable = $true
            TotalQuotas = 8; QuotasNearLimit = 0; MinShareDiskFreeGB = 50.0
        }
    }

    Context 'Healthy - all checks pass' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should return Healthy' -Test { $script:result.OverallHealth | Should -Be 'Healthy' }
        It -Name 'Should return Running service' -Test { $script:result.ServiceStatus | Should -Be 'Running' }
        It -Name 'Should return correct share count' -Test { $script:result.TotalShares | Should -Be 5 }
        It -Name 'Should return correct open sessions' -Test { $script:result.OpenSessions | Should -Be 12 }
        It -Name 'Should return zero quotas near limit' -Test { $script:result.QuotasNearLimit | Should -Be 0 }
    }

    Context 'RoleUnavailable' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.RoleAvailable = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should return RoleUnavailable' -Test { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Critical - service stopped' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Critical - disk below 5GB' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.MinShareDiskFreeGB = 3.5
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should return Critical' -Test { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Degraded - quotas near limit' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.QuotasNearLimit = 3
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Degraded - disk below 20GB' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.MinShareDiskFreeGB = 15.0
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should return Degraded' -Test { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'FS01', 'FS02' | Get-FileServerHealth
        }
        It -Name 'Should return two results' -Test { $script:results | Should -HaveCount 2 }
        It -Name 'Should return distinct ComputerName values' -Test {
            $names = @($script:results) | Select-Object -ExpandProperty ComputerName -Unique
            @($names).Count | Should -Be 2
        }
    }

    Context 'Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It -Name 'Should not throw' -Test { { Get-FileServerHealth -ComputerName 'FS01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    Context 'Parameter validation' {
        It -Name 'Should reject empty ComputerName' -Test { { Get-FileServerHealth -ComputerName '' } | Should -Throw }
        It -Name 'Should reject null ComputerName' -Test { { Get-FileServerHealth -ComputerName $null } | Should -Throw }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should have PSTypeName PSWinOps.FileServerHealth' -Test { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.FileServerHealth' }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:propResult = Get-FileServerHealth -ComputerName 'FS01'
        }
        It -Name 'Should have ComputerName property' -Test { $script:propResult.ComputerName | Should -Be 'FS01' }
        It -Name 'Should have ServiceName property' -Test { $script:propResult.ServiceName | Should -Be 'LanmanServer' }
        It -Name 'Should have OpenFiles property' -Test { $script:propResult.OpenFiles | Should -Be 45 }
        It -Name 'Should have FSRMAvailable property' -Test { $script:propResult.FSRMAvailable | Should -BeTrue }
        It -Name 'Should have TotalQuotas property' -Test { $script:propResult.TotalQuotas | Should -Be 8 }
        It -Name 'Should have MinShareDiskFreeGB property' -Test { $script:propResult.MinShareDiskFreeGB | Should -Be 50.0 }
        It -Name 'Should have Timestamp in ISO 8601 format' -Test { $script:propResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
        }
        It -Name 'Should produce verbose messages' -Test {
            $script:verbose = Get-FileServerHealth -ComputerName 'FS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verbose | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should include function name in verbose' -Test {
            $script:verbose = Get-FileServerHealth -ComputerName 'FS01' -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($script:verbose.Message -join ' ') | Should -Match 'Get-FileServerHealth'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmd = Get-Command -Name 'Get-FileServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential as PSCredential type' -Test {
            $script:cmd = Get-Command -Name 'Get-FileServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
    }

    Context 'ComputerName aliases' {
        It -Name 'Should accept CN alias' -Test {
            $script:cmd = Get-Command -Name 'Get-FileServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'CN'
        }
        It -Name 'Should accept Name alias' -Test {
            $script:cmd = Get-Command -Name 'Get-FileServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'Name'
        }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-FileServerHealth -ComputerName 'FS01'
        }
        It 'Should have Timestamp matching ISO 8601 pattern' { $script:hpResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' }
    }

    Context 'Error message content on failure' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should include computer name in error message' {
            Get-FileServerHealth -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'BADHOST'
        }
        It 'Should include function name in error message' {
            Get-FileServerHealth -ComputerName 'BADHOST2' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'Get-FileServerHealth'
        }
    }

    Context 'Additional output properties' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:addPropResult = Get-FileServerHealth -ComputerName 'FS01'
        }
        It 'Should have TotalShares property' { $script:addPropResult.TotalShares | Should -Be 5 }
        It 'Should have OpenSessions property' { $script:addPropResult.OpenSessions | Should -Be 12 }
        It 'Should have QuotasNearLimit property' { $script:addPropResult.QuotasNearLimit | Should -Be 0 }
        It 'Should have ServiceStatus property' { $script:addPropResult.ServiceStatus | Should -Be 'Running' }
    }

    Context 'Credential not mandatory' {
        It 'Should not require Credential as mandatory' {
            $script:cmd = Get-Command -Name 'Get-FileServerHealth' -Module 'PSWinOps'
            $script:isMandatory = $script:cmd.Parameters['Credential'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $script:isMandatory | Should -Be $false
        }
    }

    Context 'DNSHostName alias' {
        It 'Should accept DNSHostName alias for ComputerName' {
            $script:cmd = Get-Command -Name 'Get-FileServerHealth' -Module 'PSWinOps'
            $script:cmd.Parameters['ComputerName'].Aliases | Should -Contain 'DNSHostName'
        }
    }

    Context 'Local execution - file server healthy' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'LanmanServer'; Status = 'Running' }
            }
            Mock -CommandName 'Get-SmbShare' -ModuleName 'PSWinOps' -MockWith {
                @(
                    [PSCustomObject]@{ Name = 'Data'; Special = $false; Path = 'D:\Data' },
                    [PSCustomObject]@{ Name = 'ADMIN$'; Special = $true; Path = 'C:\Windows' }
                )
            }
            Mock -CommandName 'Get-SmbSession' -ModuleName 'PSWinOps' -MockWith { @(1,2,3) }
            Mock -CommandName 'Get-SmbOpenFile' -ModuleName 'PSWinOps' -MockWith { @(1,2) }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith { $null } -ParameterFilter { $Name -eq 'FileServerResourceManager' }
            Mock -CommandName 'Get-CimInstance' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ DeviceID = 'D:'; FreeSpace = 53687091200 })
            } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }

            $script:localFS = Get-FileServerHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return result for local file server' { $script:localFS | Should -Not -BeNullOrEmpty }
        It 'Should count non-admin shares' { $script:localFS.TotalShares | Should -Be 1 }
        It 'Should count sessions' { $script:localFS.OpenSessions | Should -Be 3 }
        It 'Should count open files' { $script:localFS.OpenFiles | Should -Be 2 }
        It 'Should have PSTypeName' { $script:localFS.PSObject.TypeNames[0] | Should -Be 'PSWinOps.FileServerHealth' }
        It 'Should report Healthy' { $script:localFS.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local execution - LanmanServer service missing' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'not found' }
            $script:localNoFS = Get-FileServerHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should return RoleUnavailable' { $script:localNoFS.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Local execution - FSRM available with quotas near limit' {

        BeforeAll {
            Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'LanmanServer'; Status = 'Running' }
            }
            Mock -CommandName 'Get-SmbShare' -ModuleName 'PSWinOps' -MockWith { @() }
            Mock -CommandName 'Get-SmbSession' -ModuleName 'PSWinOps' -MockWith { @() }
            Mock -CommandName 'Get-SmbOpenFile' -ModuleName 'PSWinOps' -MockWith { @() }
            Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Name = 'FileServerResourceManager' }
            } -ParameterFilter { $Name -eq 'FileServerResourceManager' }
            Mock -CommandName 'Import-Module' -ModuleName 'PSWinOps' -MockWith { }
            Mock -CommandName 'Get-FsrmQuota' -ModuleName 'PSWinOps' -MockWith {
                @([PSCustomObject]@{ Size = 1073741824; Usage = 1000000000 })
            }

            $script:localFSRM = Get-FileServerHealth -ComputerName $env:COMPUTERNAME
        }

        It 'Should detect FSRM available' { $script:localFSRM.FSRMAvailable | Should -BeTrue }
        It 'Should count quotas near limit' { $script:localFSRM.QuotasNearLimit | Should -BeGreaterThan 0 }
    }

}
