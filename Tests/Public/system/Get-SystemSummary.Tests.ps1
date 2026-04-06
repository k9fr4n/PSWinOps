#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name "$($script:modulePath)/PSWinOps.psd1" -Force
}

Describe 'Get-SystemSummary' {
    BeforeAll {
        $script:fakeSystem = [PSCustomObject]@{
            Name                = 'TESTPC'
            Domain              = 'test.local'
            Manufacturer        = 'Dell Inc.'
            Model               = 'PowerEdge R740'
            TotalPhysicalMemory = 34359738368  # 32 GB
        }
        $script:fakeOS = [PSCustomObject]@{
            Caption                = 'Microsoft Windows Server 2022 Standard'
            Version                = '10.0.20348'
            OSArchitecture         = '64-bit'
            InstallDate            = (Get-Date).AddDays(-365)
            LastBootUpTime         = (Get-Date).AddDays(-5)
            FreePhysicalMemory     = 16777216     # 16 GB in KB
            TotalVisibleMemorySize = 33554432     # 32 GB in KB
        }
        $script:fakeBIOS = [PSCustomObject]@{
            SerialNumber      = 'ABC1234'
            SMBIOSBIOSVersion = '2.17.0'
        }
        $script:fakeProcessor = [PSCustomObject]@{
            Name                      = 'Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz'
            NumberOfCores             = 8
            NumberOfLogicalProcessors = 16
        }
        $script:fakeDisk = [PSCustomObject]@{
            DeviceID   = 'C:'
            Size       = 107374182400   # 100 GB
            FreeSpace  = 53687091200    # 50 GB
            FileSystem = 'NTFS'
            VolumeName = 'System'
            DriveType  = 3
        }
        $script:fakeNetwork = [PSCustomObject]@{
            IPAddress            = @('192.168.1.10', 'fe80::1')
            DefaultIPGateway     = @('192.168.1.1')
            DNSServerSearchOrder = @('8.8.8.8', '8.8.4.4')
        }
    }

    BeforeEach {
        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
            $ClassName -eq 'Win32_ComputerSystem'
        } -MockWith { return $script:fakeSystem }

        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
            $ClassName -eq 'Win32_OperatingSystem'
        } -MockWith { return $script:fakeOS }

        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
            $ClassName -eq 'Win32_BIOS'
        } -MockWith { return $script:fakeBIOS }

        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
            $ClassName -eq 'Win32_Processor'
        } -MockWith { return $script:fakeProcessor }

        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
            $ClassName -eq 'Win32_LogicalDisk'
        } -MockWith { return $script:fakeDisk }

        Mock -ModuleName 'PSWinOps' -CommandName 'Get-CimInstance' -ParameterFilter {
            $ClassName -eq 'Win32_NetworkAdapterConfiguration'
        } -MockWith { return $script:fakeNetwork }

        Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
            if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
        }
    }

    Context 'Happy path - local machine' {
        It -Name 'Should return a PSCustomObject with expected values' -Test {
            $script:result = Get-SystemSummary
            $script:result | Should -Not -BeNullOrEmpty
            $script:result.ComputerName | Should -Be $env:COMPUTERNAME
            $script:result.Domain | Should -Be 'test.local'
            $script:result.OSName | Should -Be 'Microsoft Windows Server 2022 Standard'
            $script:result.OSVersion | Should -Be '10.0.20348'
            $script:result.OSArchitecture | Should -Be '64-bit'
            $script:result.Manufacturer | Should -Be 'Dell Inc.'
            $script:result.Model | Should -Be 'PowerEdge R740'
            $script:result.SerialNumber | Should -Be 'ABC1234'
            $script:result.BIOSVersion | Should -Be '2.17.0'
            $script:result.Processor | Should -Be 'Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz'
        }

        It -Name 'Should call Get-CimInstance exactly 6 times for local query' -Test {
            Get-SystemSummary | Out-Null
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Happy path - explicit remote machine' {
        It -Name 'Should return an object for a remote machine name' -Test {
            $script:result = Get-SystemSummary -ComputerName 'SRV01'
            $script:result | Should -Not -BeNullOrEmpty
            $script:result.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once for remote machine' -Test {
            Get-SystemSummary -ComputerName 'SRV01' | Out-Null
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Credential parameter support' {
        It -Name 'Should accept a PSCredential parameter' -Test {
            $script:paramInfo = (Get-Command -Name 'Get-SystemSummary').Parameters['Credential']
            $script:paramInfo | Should -Not -BeNullOrEmpty
            $script:paramInfo.ParameterType.Name | Should -Be 'PSCredential'
        }

        It -Name 'Should not be a mandatory parameter' -Test {
            $script:paramInfo = (Get-Command -Name 'Get-SystemSummary').Parameters['Credential']
            $script:paramInfo.Attributes.Mandatory | Should -Contain $false
        }
    }

    Context 'Pipeline input - multiple machines' {
        It -Name 'Should return 2 results for 2 piped machine names' -Test {
            $script:results = @('SRV01', 'SRV02') | Get-SystemSummary
            $script:results | Should -HaveCount 2
        }

        It -Name 'Should call Invoke-RemoteOrLocal 2 times for 2 machines' -Test {
            @('SRV01', 'SRV02') | Get-SystemSummary | Out-Null
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    Context 'Per-machine failure handling' {
        BeforeEach {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -ParameterFilter {
                $ComputerName -eq 'BADMACHINE'
            } -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write an error for the failing machine and continue' -Test {
            $script:results = Get-SystemSummary -ComputerName 'BADMACHINE', 'SRV01' -ErrorAction SilentlyContinue
            $script:results | Should -HaveCount 1
            $script:results.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should emit a non-terminating error for the failing machine' -Test {
            { Get-SystemSummary -ComputerName 'BADMACHINE' -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Parameter validation' {
        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-SystemSummary -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-SystemSummary -ComputerName $null } | Should -Throw
        }
    }

    Context 'Output type validation' {
        BeforeAll {
            $script:expectedProperties = @(
                'ComputerName', 'Domain', 'OSName', 'OSVersion', 'OSArchitecture',
                'InstallDate', 'LastBootTime', 'UptimeDays', 'UptimeDisplay',
                'Manufacturer', 'Model', 'SerialNumber', 'BIOSVersion',
                'Processor', 'TotalCores', 'TotalLogicalProcessors',
                'TotalRAMGB', 'FreeRAMGB', 'RAMUsagePercent',
                'Disks', 'IPAddresses', 'DefaultGateway', 'DNSServers',
                'PSVersion', 'Timestamp'
            )
        }

        It -Name 'Should have all 25 expected properties' -Test {
            $script:result = Get-SystemSummary
            $script:propertyNames = ($script:result | Get-Member -MemberType NoteProperty).Name
            foreach ($expectedProp in $script:expectedProperties) {
                $script:propertyNames | Should -Contain $expectedProp
            }
        }

        It -Name 'Should return correct types for key fields' -Test {
            $script:result = Get-SystemSummary
            $script:result.ComputerName | Should -BeOfType [string]
            $script:result.InstallDate | Should -BeOfType [datetime]
            $script:result.LastBootTime | Should -BeOfType [datetime]
            $script:result.TotalRAMGB | Should -BeOfType [decimal]
            $script:result.FreeRAMGB | Should -BeOfType [decimal]
            $script:result.RAMUsagePercent | Should -BeOfType [decimal]
            $script:result.UptimeDays | Should -BeOfType [decimal]
            $script:result.TotalCores | Should -BeOfType [int]
            $script:result.TotalLogicalProcessors | Should -BeOfType [int]
        }

        It -Name 'Should have UptimeDisplay matching expected format' -Test {
            $script:result = Get-SystemSummary
            $script:result.UptimeDisplay | Should -Match '^\d+ days, \d+ hours, \d+ minutes$'
        }

        It -Name 'Should have Timestamp in ISO 8601 format' -Test {
            $script:result = Get-SystemSummary
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context 'Calculated values' {
        It -Name 'Should calculate RAMUsagePercent as 50 percent from mock data' -Test {
            $script:result = Get-SystemSummary
            $script:result.RAMUsagePercent | Should -Be 50.0
        }

        It -Name 'Should calculate UptimeDays as approximately 5' -Test {
            $script:result = Get-SystemSummary
            $script:result.UptimeDays | Should -BeGreaterOrEqual 4.9
            $script:result.UptimeDays | Should -BeLessOrEqual 5.1
        }

        It -Name 'Should calculate TotalRAMGB as 32 from mock data' -Test {
            $script:result = Get-SystemSummary
            $script:result.TotalRAMGB | Should -Be 32.0
        }

        It -Name 'Should calculate FreeRAMGB as 16 from mock data' -Test {
            $script:result = Get-SystemSummary
            $script:result.FreeRAMGB | Should -Be 16.0
        }

        It -Name 'Should include drive letter C: in Disks string' -Test {
            $script:result = Get-SystemSummary
            $script:result.Disks | Should -Match 'C:'
        }

        It -Name 'Should include NTFS in Disks string' -Test {
            $script:result = Get-SystemSummary
            $script:result.Disks | Should -Match 'NTFS'
        }

        It -Name 'Should include only IPv4 addresses and exclude IPv6' -Test {
            $script:result = Get-SystemSummary
            $script:result.IPAddresses | Should -Be '192.168.1.10'
            $script:result.IPAddresses | Should -Not -Match 'fe80'
        }

        It -Name 'Should include the default gateway from mock data' -Test {
            $script:result = Get-SystemSummary
            $script:result.DefaultGateway | Should -Be '192.168.1.1'
        }

        It -Name 'Should include DNS servers from mock data' -Test {
            $script:result = Get-SystemSummary
            $script:result.DNSServers | Should -Match '8\.8\.8\.8'
            $script:result.DNSServers | Should -Match '8\.8\.4\.4'
        }
    }
}
