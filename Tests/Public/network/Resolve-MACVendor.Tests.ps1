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
    }
}
