BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Resolve-MACVendor' {

    Context 'Built-in database lookup' {

        It 'Should resolve VMware MAC' {
            $result = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $result.Vendor | Should -Be 'VMware'
            $result.Source | Should -Be 'BuiltIn'
        }

        It 'Should resolve Intel MAC' {
            $result = Resolve-MACVendor -MACAddress 'A4:4C:C8:12:34:56'
            $result.Vendor | Should -Be 'Intel'
        }

        It 'Should resolve Cisco MAC with dash format' {
            $result = Resolve-MACVendor -MACAddress '00-06-D7-AA-BB-CC'
            $result.Vendor | Should -Be 'Cisco'
        }

        It 'Should resolve MAC without separators' {
            $result = Resolve-MACVendor -MACAddress '005056C00008'
            $result.Vendor | Should -Be 'VMware'
        }

        It 'Should include PSTypeName PSWinOps.MACVendor' {
            $result = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.MACVendor'
        }

        It 'Should format MAC with colons' {
            $result = Resolve-MACVendor -MACAddress '005056C00008'
            $result.MACAddress | Should -Be '00:50:56:C0:00:08'
        }

        It 'Should include OUI prefix' {
            $result = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $result.OUI | Should -Be '005056'
        }

        It 'Should include Timestamp' {
            $result = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Unknown MAC' {

        It 'Should return Unknown for unrecognized OUI' {
            $result = Resolve-MACVendor -MACAddress 'FF:FF:FF:00:00:01'
            $result.Vendor | Should -Be 'Unknown'
            $result.Source | Should -Be 'NotFound'
        }
    }

    Context 'Online fallback' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RestMethod' -MockWith {
                return 'Acme Corp'
            }
        }

        It 'Should query API when -Online and not in built-in DB' {
            $result = Resolve-MACVendor -MACAddress 'FF:FF:FF:00:00:01' -Online
            $result.Vendor | Should -Be 'Acme Corp'
            $result.Source | Should -Be 'Online'
            Should -Invoke -CommandName 'Invoke-RestMethod' -ModuleName $script:ModuleName -Times 1
        }

        It 'Should NOT query API for known MACs even with -Online' {
            $result = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08' -Online
            $result.Vendor | Should -Be 'VMware'
            $result.Source | Should -Be 'BuiltIn'
            Should -Invoke -CommandName 'Invoke-RestMethod' -ModuleName $script:ModuleName -Times 0
        }
    }

    Context 'Multiple MACs and pipeline' {

        It 'Should resolve multiple MACs' {
            $result = Resolve-MACVendor -MACAddress '00:50:56:AA:BB:CC', '00:06:D7:11:22:33'
            $result.Count | Should -Be 2
            $result[0].Vendor | Should -Be 'VMware'
            $result[1].Vendor | Should -Be 'Cisco'
        }

        It 'Should accept pipeline input' {
            $result = '00:50:56:AA:BB:CC', '00:06:D7:11:22:33' | Resolve-MACVendor
            $result.Count | Should -Be 2
        }
    }

    Context 'Error handling' {

        It 'Should error on MAC too short' {
            Resolve-MACVendor -MACAddress 'AB:CD' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It 'Should reject empty MACAddress' {
            { Resolve-MACVendor -MACAddress '' } | Should -Throw
        }

        It 'Should reject null MACAddress' {
            { Resolve-MACVendor -MACAddress $null } | Should -Throw
        }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'API failure graceful handling' {

        BeforeEach {
            Mock -ModuleName $script:ModuleName -CommandName 'Invoke-RestMethod' -MockWith {
                throw 'API unavailable'
            }
        }

        It 'Should return Unknown vendor when API throws with -Online' {
            $script:result = Resolve-MACVendor -MACAddress 'FF:FF:FF:00:00:01' -Online
            $script:result.Vendor | Should -Be 'Unknown'
            $script:result.Source | Should -Be 'NotFound'
        }

        It 'Should not throw when API fails with -Online' {
            { Resolve-MACVendor -MACAddress 'FF:FF:FF:00:00:01' -Online } | Should -Not -Throw
        }

        It 'Should still invoke API even when it fails' {
            Resolve-MACVendor -MACAddress 'FF:FF:FF:00:00:01' -Online
            Should -Invoke -CommandName 'Invoke-RestMethod' -ModuleName $script:ModuleName -Times 1
        }
    }

    Context 'Lowercase MAC normalization' {

        It 'Should normalize lowercase MAC to uppercase in MACAddress property' {
            $script:result = Resolve-MACVendor -MACAddress 'aa:bb:cc:dd:ee:ff'
            $script:result.MACAddress | Should -Be 'AA:BB:CC:DD:EE:FF'
        }

        It 'Should normalize lowercase OUI to uppercase' {
            $script:result = Resolve-MACVendor -MACAddress 'aa:bb:cc:dd:ee:ff'
            $script:result.OUI | Should -Be 'AABBCC'
        }

        It 'Should resolve lowercase known MAC correctly' {
            $script:result = Resolve-MACVendor -MACAddress '00:50:56:c0:00:08'
            $script:result.Vendor | Should -Be 'VMware'
            $script:result.Source | Should -Be 'BuiltIn'
        }
    }

    Context 'Output property completeness' {

        BeforeAll {
            $script:fullResult = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $script:propertyNames = $script:fullResult.PSObject.Properties.Name
        }

        It 'Should have PSTypeName PSWinOps.MACVendor' {
            $script:fullResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.MACVendor'
        }

        It 'Should have MACAddress property' {
            $script:propertyNames | Should -Contain 'MACAddress'
            $script:fullResult.MACAddress | Should -Not -BeNullOrEmpty
        }

        It 'Should have OUI property' {
            $script:propertyNames | Should -Contain 'OUI'
            $script:fullResult.OUI | Should -Not -BeNullOrEmpty
        }

        It 'Should have Vendor property' {
            $script:propertyNames | Should -Contain 'Vendor'
            $script:fullResult.Vendor | Should -Not -BeNullOrEmpty
        }

        It 'Should have Source property' {
            $script:propertyNames | Should -Contain 'Source'
            $script:fullResult.Source | Should -Not -BeNullOrEmpty
        }

        It 'Should have Timestamp property' {
            $script:propertyNames | Should -Contain 'Timestamp'
            $script:fullResult.Timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Timestamp ISO 8601 format' {

        It 'Should return Timestamp in ISO 8601 format' {
            $script:result = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $script:result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context 'Mixed separator formats' {

        It 'Should resolve MAC without separators' {
            $script:result = Resolve-MACVendor -MACAddress '005056C00008'
            $script:result.Vendor | Should -Be 'VMware'
        }

        It 'Should resolve MAC with colon separators' {
            $script:result = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $script:result.Vendor | Should -Be 'VMware'
        }

        It 'Should resolve MAC with dash separators' {
            $script:result = Resolve-MACVendor -MACAddress '00-50-56-C0-00-08'
            $script:result.Vendor | Should -Be 'VMware'
        }

        It 'Should produce identical formatted MACAddress for all separator styles' {
            $script:resultNoSep = Resolve-MACVendor -MACAddress '005056C00008'
            $script:resultColon = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08'
            $script:resultDash = Resolve-MACVendor -MACAddress '00-50-56-C0-00-08'
            $script:resultNoSep.MACAddress | Should -Be $script:resultColon.MACAddress
            $script:resultColon.MACAddress | Should -Be $script:resultDash.MACAddress
        }
    }

    Context 'Verbose output' {

        It 'Should produce verbose messages with -Verbose' {
            $script:verboseOutput = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08' -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:verboseOutput | Should -Not -BeNullOrEmpty
        }

        It 'Should include Starting verbose message' {
            $script:verboseOutput = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08' -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:startMsg = $script:verboseOutput | Where-Object { $_.Message -like '*Starting*' }
            $script:startMsg | Should -Not -BeNullOrEmpty
        }

        It 'Should include Completed verbose message' {
            $script:verboseOutput = Resolve-MACVendor -MACAddress '00:50:56:C0:00:08' -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $script:endMsg = $script:verboseOutput | Where-Object { $_.Message -like '*Completed*' }
            $script:endMsg | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Pipeline from objects with LinkLayerAddress' {

        It 'Should accept objects with LinkLayerAddress property via pipeline' {
            $script:arpEntry = [PSCustomObject]@{ LinkLayerAddress = '00:50:56:C0:00:08' }
            $script:result = $script:arpEntry | Resolve-MACVendor
            $script:result.Vendor | Should -Be 'VMware'
        }

        It 'Should accept multiple ARP-like objects via pipeline' {
            $script:arpEntries = @(
                [PSCustomObject]@{ LinkLayerAddress = '00:50:56:C0:00:08' }
                [PSCustomObject]@{ LinkLayerAddress = '00:06:D7:11:22:33' }
            )
            $script:result = $script:arpEntries | Resolve-MACVendor
            $script:result.Count | Should -Be 2
            $script:result[0].Vendor | Should -Be 'VMware'
            $script:result[1].Vendor | Should -Be 'Cisco'
        }
    }

    Context 'Multiple vendors in single call' {

        It 'Should resolve Dell, Apple, and Microsoft MACs' {
            $script:macs = @('00:18:8B:11:22:33', '00:14:51:44:55:66', '00:50:F2:77:88:99')
            $script:result = Resolve-MACVendor -MACAddress $script:macs
            $script:result.Count | Should -Be 3
        }

        It 'Should resolve Dell vendor correctly' {
            $script:result = Resolve-MACVendor -MACAddress '00:18:8B:11:22:33'
            $script:result.Vendor | Should -Be 'Dell'
        }

        It 'Should resolve Apple vendor correctly' {
            $script:result = Resolve-MACVendor -MACAddress '00:14:51:44:55:66'
            $script:result.Vendor | Should -Be 'Apple'
        }

        It 'Should resolve Microsoft vendor correctly' {
            $script:result = Resolve-MACVendor -MACAddress '00:50:F2:77:88:99'
            $script:result.Vendor | Should -Be 'Microsoft'
        }
    }
}
