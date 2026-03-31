#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'Get-EnvironmentVariable' {

    BeforeAll {
        $script:mockRemoteEntries = @(
            [PSCustomObject]@{ Name = 'COMPUTERNAME'; Value = 'SRV01'; Scope = 'Machine' },
            [PSCustomObject]@{ Name = 'PATH'; Value = 'C:\Windows'; Scope = 'Machine' },
            [PSCustomObject]@{ Name = 'TEMP'; Value = 'C:\Windows\Temp'; Scope = 'Machine' }
        )
    }

    Context 'Remote - all scopes' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:results = Get-EnvironmentVariable -ComputerName 'SRV01'
        }

        It -Name 'Should return PSWinOps.EnvironmentVariable type' -Test {
            $script:results[0].PSObject.TypeNames | Should -Contain 'PSWinOps.EnvironmentVariable'
        }

        It -Name 'Should set ComputerName to SRV01' -Test {
            $script:results | ForEach-Object -Process {
                $_.ComputerName | Should -Be 'SRV01'
            }
        }

        It -Name 'Should return results sorted by Name' -Test {
            $script:names = $script:results | Select-Object -ExpandProperty Name
            $script:expected = $script:names | Sort-Object
            $script:names | Should -Be $script:expected
        }
    }

    Context 'Remote - VariableName filter' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:results = Get-EnvironmentVariable -ComputerName 'SRV01' -VariableName 'PATH'
        }

        It -Name 'Should return only the PATH variable' -Test {
            $script:results | Should -HaveCount 1
            $script:results.Name | Should -Be 'PATH'
        }
    }

    Context 'Remote - Scope Machine only' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:scopeResults = Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'Machine'
        }

        It -Name 'Should return results from the remote machine' -Test {
            $script:scopeResults | Should -Not -BeNullOrEmpty
            $script:scopeResults[0].ComputerName | Should -Be 'SRV01'
        }
    }

    Context 'Process scope remote warning' {

        BeforeAll {
            $script:processResult = Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'Process' -WarningVariable warnVar 3>$null
            $script:warningMessages = $warnVar
        }

        It -Name 'Should write a warning about Process scope on remote' -Test {
            $script:warningMessages | Should -Not -BeNullOrEmpty
            "$($script:warningMessages[0])" | Should -BeLike '*Process scope*'
        }

        It -Name 'Should not return any results' -Test {
            $script:processResult | Should -BeNullOrEmpty
        }
    }

    Context 'Pipeline multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:results = 'SRV01', 'SRV02' | Get-EnvironmentVariable
        }

        It -Name 'Should return results from multiple machines' -Test {
            @($script:results).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Per-machine failure' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { throw 'Connection failed' }
        }

        It -Name 'Should write error with ErrorAction Stop' -Test {
            { Get-EnvironmentVariable -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should return no output for failed machine' -Test {
            $script:failResult = Get-EnvironmentVariable -ComputerName 'BADHOST' -ErrorAction SilentlyContinue
            $script:failResult | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should throw when ComputerName is empty' -Test {
            { Get-EnvironmentVariable -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when VariableName is empty' -Test {
            { Get-EnvironmentVariable -VariableName '' } | Should -Throw
        }

        It -Name 'Should throw when Scope is invalid' -Test {
            { Get-EnvironmentVariable -Scope 'Invalid' } | Should -Throw
        }
    }

    # ================================================================
    # APPENDED TEST CONTEXTS
    # ================================================================

    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:typeResults = Get-EnvironmentVariable -ComputerName 'SRV01'
        }
        It -Name 'Should have PSTypeName PSWinOps.EnvironmentVariable on all results' -Test {
            $script:typeResults | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'PSWinOps.EnvironmentVariable' }
        }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:propResults = Get-EnvironmentVariable -ComputerName 'SRV01'
        }
        It -Name 'Should contain all expected visible properties' -Test {
            $script:propertyNames = $script:propResults[0].PSObject.Properties.Name
            $script:expectedProps = @('ComputerName', 'Name', 'Value', 'Scope', 'Timestamp')
            foreach ($script:prop in $script:expectedProps) {
                $script:propertyNames | Should -Contain $script:prop
            }
        }

        It -Name 'Should have PSTypeName PSWinOps.EnvironmentVariable' -Test {
            $script:propResults[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.EnvironmentVariable'
        }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
            $script:tsResults = Get-EnvironmentVariable -ComputerName 'SRV01'
        }
        It -Name 'Should have Timestamp matching ISO 8601 pattern' -Test {
            $script:tsResults | ForEach-Object { $_.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
        }
    }

    Context 'Verbose output' {
        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteEntries }
        }
        It -Name 'Should emit verbose messages containing Get-EnvironmentVariable' -Test {
            $script:verboseOutput = Get-EnvironmentVariable -ComputerName 'SRV01' -Verbose 4>&1
            $script:verboseMessages = @($script:verboseOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $script:verboseMessages.Count | Should -BeGreaterOrEqual 1
            $script:verboseText = $script:verboseMessages | ForEach-Object { $_.Message }
            $script:verboseText -join ' ' | Should -Match 'Get-EnvironmentVariable'
        }
    }

    Context 'VariableName wildcard filter' {
        BeforeAll {
            $script:mockWildcardEntries = @(
                [PSCustomObject]@{ Name = 'PATH'; Value = 'C:\Windows'; Scope = 'Machine' },
                [PSCustomObject]@{ Name = 'PATHEXT'; Value = '.COM;.EXE;.BAT'; Scope = 'Machine' },
                [PSCustomObject]@{ Name = 'TEMP'; Value = 'C:\Windows\Temp'; Scope = 'Machine' }
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return $script:mockWildcardEntries }
        }
        It -Name 'Should return only PATH and PATHEXT when filtering with PATH*' -Test {
            $script:wildcardResults = Get-EnvironmentVariable -ComputerName 'SRV01' -VariableName 'PATH*'
            @($script:wildcardResults).Count | Should -Be 2
            $script:returnedNames = $script:wildcardResults | Select-Object -ExpandProperty Name
            $script:returnedNames | Should -Contain 'PATH'
            $script:returnedNames | Should -Contain 'PATHEXT'
        }
        It -Name 'Should not return TEMP when filtering with PATH*' -Test {
            $script:wildcardResults = Get-EnvironmentVariable -ComputerName 'SRV01' -VariableName 'PATH*'
            $script:returnedNames = $script:wildcardResults | Select-Object -ExpandProperty Name
            $script:returnedNames | Should -Not -Contain 'TEMP'
        }
    }

    Context 'Credential parameter' {
        It -Name 'Should have a Credential parameter' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-EnvironmentVariable'
            $script:cmdInfo.Parameters['Credential'] | Should -Not -BeNullOrEmpty
        }
        It -Name 'Should have Credential of type PSCredential' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-EnvironmentVariable'
            $script:cmdInfo.Parameters['Credential'].ParameterType.Name | Should -Be 'PSCredential'
        }
        It -Name 'Should not require Credential as mandatory' -Test {
            $script:cmdInfo = Get-Command -Name 'Get-EnvironmentVariable'
            $script:isMandatory = $script:cmdInfo.Parameters['Credential'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }
            $script:isMandatory | Should -Be $false
        }
    }

    Context 'Scope parameter validation' {
        It -Name 'Should accept Machine as a valid scope' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return @() }
            { Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'Machine' } | Should -Not -Throw
        }
        It -Name 'Should accept User as a valid scope' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return @() }
            { Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'User' } | Should -Not -Throw
        }
        It -Name 'Should accept All as a valid scope' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith { return @() }
            { Get-EnvironmentVariable -ComputerName 'SRV01' -Scope 'All' } | Should -Not -Throw
        }
        It -Name 'Should throw when Scope is Invalid' -Test {
            { Get-EnvironmentVariable -Scope 'Invalid' } | Should -Throw
        }
    }

    Context 'Local execution - all scopes via scriptblock' {

        BeforeAll {
            Mock -CommandName 'Get-Item' -ModuleName 'PSWinOps' -MockWith {
                $mockRegItem = [PSCustomObject]@{}
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValueNames' -Value {
                    return @('COMPUTERNAME', 'PATH')
                }
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValue' -Value {
                    param($valueName, $defaultValue, $options)
                    switch ($valueName) {
                        'COMPUTERNAME' { return 'TESTPC' }
                        'PATH' { return 'C:\Windows;C:\Windows\System32' }
                        default { return '' }
                    }
                }
                return $mockRegItem
            }
            }
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
        }

        It -Name 'Should return results for local machine with All scope' -Test {
            $script:localResults = Get-EnvironmentVariable -ComputerName $env:COMPUTERNAME
            $script:localResults | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should include Process scope for local queries' -Test {
            $script:localResults = Get-EnvironmentVariable -ComputerName $env:COMPUTERNAME -Scope 'All'
            $processEntries = $script:localResults | Where-Object Scope -eq 'Process'
            $processEntries | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should return typed objects for local queries' -Test {
            $script:localResults = Get-EnvironmentVariable -ComputerName $env:COMPUTERNAME
            $script:localResults[0].PSObject.TypeNames | Should -Contain 'PSWinOps.EnvironmentVariable'
        }

        It -Name 'Should set ComputerName to local machine name' -Test {
            $script:localResults = Get-EnvironmentVariable -ComputerName $env:COMPUTERNAME
            $script:localResults[0].ComputerName | Should -Be $env:COMPUTERNAME
        }
    }

    Context 'Local execution - Machine scope only' {

        BeforeAll {
            Mock -CommandName 'Get-Item' -ModuleName 'PSWinOps' -MockWith {
                $mockRegItem = [PSCustomObject]@{}
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValueNames' -Value {
                    return @('OS', 'SystemRoot')
                }
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValue' -Value {
                    param($valueName, $defaultValue, $options)
                    switch ($valueName) {
                        'OS' { return 'Windows_NT' }
                        'SystemRoot' { return 'C:\Windows' }
                        default { return '' }
                    }
                }
                return $mockRegItem
            }
            }
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
        }

        It -Name 'Should return Machine scope results for local Machine query' -Test {
            $script:machineResults = Get-EnvironmentVariable -ComputerName $env:COMPUTERNAME -Scope 'Machine'
            $script:machineResults | Should -Not -BeNullOrEmpty
            $script:machineResults | ForEach-Object { $_.Scope | Should -Be 'Machine' }
        }
    }

    Context 'Local execution - Process scope only' {

        It -Name 'Should return Process scope results for local query' -Test {
            $script:processResults = Get-EnvironmentVariable -ComputerName $env:COMPUTERNAME -Scope 'Process'
            $script:processResults | Should -Not -BeNullOrEmpty
            $script:processResults | ForEach-Object { $_.Scope | Should -Be 'Process' }
        }
    }

    Context 'Local execution - VariableName filter local' {

        BeforeAll {
            Mock -CommandName 'Get-Item' -ModuleName 'PSWinOps' -MockWith {
                $mockRegItem = [PSCustomObject]@{}
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValueNames' -Value {
                    return @('PATH', 'TEMP', 'TMP')
                }
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValue' -Value {
                    param($valueName, $defaultValue, $options)
                    return "value_$valueName"
                }
                return $mockRegItem
            }
            }
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
        }

        It -Name 'Should filter by VariableName with wildcard on local' -Test {
            $script:filtered = Get-EnvironmentVariable -ComputerName $env:COMPUTERNAME -VariableName 'T*' -Scope 'Machine'
            $script:filtered | ForEach-Object { $_.Name | Should -BeLike 'T*' }
        }
    }

    Context 'Local execution - localhost alias' {

        BeforeAll {
            Mock -CommandName 'Get-Item' -ModuleName 'PSWinOps' -MockWith {
                $mockRegItem = [PSCustomObject]@{}
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValueNames' -Value { return @('TEST') }
                $mockRegItem | Add-Member -MemberType ScriptMethod -Name 'GetValue' -Value {
                    param($valueName, $defaultValue, $options)
                    return 'testval'
                }
                return $mockRegItem
            }
            }
                if ($ArgumentList) { & $ScriptBlock @ArgumentList } else { & $ScriptBlock }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
        }

        It -Name 'Should treat localhost as local and use scriptblock' -Test {
            $script:localhostResult = Get-EnvironmentVariable -ComputerName 'localhost' -Scope 'Machine'
            $script:localhostResult | Should -Not -BeNullOrEmpty
            $script:localhostResult[0].ComputerName | Should -Be 'localhost'
        }
    }

}
