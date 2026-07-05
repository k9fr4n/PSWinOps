#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Get-AuditPolicy function

.DESCRIPTION
    Comprehensive test coverage for Get-AuditPolicy, including:
    - Local happy path parsing of auditpol /r CSV output
    - Setting derivation (No Auditing / Success / Failure / Success and Failure)
    - Subcategory GUID -> Category mapping (known and unmapped GUIDs)
    - -Category filtering
    - Remote single-machine execution via Invoke-Command
    - Credential propagation to Invoke-Command
    - Pipeline fan-out across multiple machines
    - Per-machine error isolation (exit-code failure, malformed CSV, mock throws)
    - Parameter validation

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-07-05
    Requires:      Pester 5.x, PowerShell 5.1+
    Permissions:   None required (all external commands are mocked)
#>

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    #region Mock CSV data (mirrors auditpol.exe /get /category:* /r output)
    $script:mockCsvLines = @(
        '"Machine Name","Policy Target","Subcategory","Subcategory GUID","Inclusion Setting","Exclusion Setting"'
        '"HOSTNAME","System","Logon","{0CCE9215-69AE-11D9-BED3-505054503030}","Success and Failure","No Auditing"'
        '"HOSTNAME","System","Logoff","{0CCE9216-69AE-11D9-BED3-505054503030}","Success","No Auditing"'
        '"HOSTNAME","System","Special Logon","{0CCE9243-69AE-11D9-BED3-505054503030}","No Auditing","No Auditing"'
        '"HOSTNAME","System","File System","{0CCE921D-69AE-11D9-BED3-505054503030}","Failure","No Auditing"'
        '"HOSTNAME","System","Unmapped Subcategory","{0CCE9999-69AE-11D9-BED3-505054503030}","No Auditing","No Auditing"'
    )
    #endregion
}

Describe -Name 'Get-AuditPolicy' -Fixture {

    Context -Name 'Local happy path - mixed audit settings' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Output = ($script:mockCsvLines -join "`r`n"); ExitCode = 0 }
            }
        }

        It -Name 'Should return one row per subcategory' -Test {
            $result = Get-AuditPolicy
            $result.Count | Should -Be 5
        }

        It -Name 'Should return a PSWinOps.AuditPolicy typed object' -Test {
            $result = Get-AuditPolicy
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.AuditPolicy'
        }

        It -Name 'Should return all required output properties' -Test {
            $result = Get-AuditPolicy
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'ComputerName'
            $props | Should -Contain 'Category'
            $props | Should -Contain 'Subcategory'
            $props | Should -Contain 'SubcategoryGuid'
            $props | Should -Contain 'AuditSuccess'
            $props | Should -Contain 'AuditFailure'
            $props | Should -Contain 'Setting'
            $props | Should -Contain 'Timestamp'
        }

        It -Name 'Should set ComputerName to the local machine' -Test {
            $result = Get-AuditPolicy
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should format Timestamp as yyyy-MM-dd HH:mm:ss' -Test {
            $result = Get-AuditPolicy
            $result[0].Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It -Name 'Should derive Setting "Success and Failure" for the Logon row' -Test {
            $result = Get-AuditPolicy
            $row = $result | Where-Object { $_.Subcategory -eq 'Logon' }
            $row.AuditSuccess | Should -Be $true
            $row.AuditFailure | Should -Be $true
            $row.Setting | Should -Be 'Success and Failure'
        }

        It -Name 'Should derive Setting "Success" for the Logoff row' -Test {
            $result = Get-AuditPolicy
            $row = $result | Where-Object { $_.Subcategory -eq 'Logoff' }
            $row.AuditSuccess | Should -Be $true
            $row.AuditFailure | Should -Be $false
            $row.Setting | Should -Be 'Success'
        }

        It -Name 'Should derive Setting "No Auditing" for the Special Logon row' -Test {
            $result = Get-AuditPolicy
            $row = $result | Where-Object { $_.Subcategory -eq 'Special Logon' }
            $row.AuditSuccess | Should -Be $false
            $row.AuditFailure | Should -Be $false
            $row.Setting | Should -Be 'No Auditing'
        }

        It -Name 'Should derive Setting "Failure" for the File System row' -Test {
            $result = Get-AuditPolicy
            $row = $result | Where-Object { $_.Subcategory -eq 'File System' }
            $row.AuditSuccess | Should -Be $false
            $row.AuditFailure | Should -Be $true
            $row.Setting | Should -Be 'Failure'
        }

        It -Name 'Should map known GUIDs to their Category via the static GUID map' -Test {
            $result = Get-AuditPolicy
            $result | Where-Object { $_.Subcategory -eq 'Logon' } | Select-Object -ExpandProperty Category | Should -Be 'Logon/Logoff'
            $result | Where-Object { $_.Subcategory -eq 'File System' } | Select-Object -ExpandProperty Category | Should -Be 'Object Access'
        }

        It -Name 'Should map an unmapped Subcategory GUID to Category Unknown' -Test {
            $result = Get-AuditPolicy
            $row = $result | Where-Object { $_.Subcategory -eq 'Unmapped Subcategory' }
            $row.Category | Should -Be 'Unknown'
        }

        It -Name 'Should strip braces and upper-case the SubcategoryGuid' -Test {
            $result = Get-AuditPolicy
            $row = $result | Where-Object { $_.Subcategory -eq 'Logon' }
            $row.SubcategoryGuid | Should -Be '0CCE9215-69AE-11D9-BED3-505054503030'
        }
    }

    Context -Name '-Category filter' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Output = ($script:mockCsvLines -join "`r`n"); ExitCode = 0 }
            }
        }

        It -Name 'Should return only subcategories belonging to the requested Category' -Test {
            $result = @(Get-AuditPolicy -Category 'Logon/Logoff')
            $result.Count | Should -Be 3
            $result.Category | Should -Not -Contain 'Object Access'
        }

        It -Name 'Should return nothing without error when Category has no match' -Test {
            $result = @(Get-AuditPolicy -Category 'NoSuchCategory' -ErrorAction Stop)
            $result.Count | Should -Be 0
        }
    }

    Context -Name 'Explicit remote machine' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $script:mockCsvLines
            }
        }

        It -Name 'Should dispatch via Invoke-Command for a remote machine' -Test {
            $result = Get-AuditPolicy -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly
            $result[0].ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should propagate Credential to Invoke-Command' -Test {
            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd123!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\svc', $securePwd)
            Get-AuditPolicy -ComputerName 'SRV01' -Credential $cred
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $cred
            }
        }
    }

    Context -Name 'Pipeline of multiple machine names' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                $script:mockCsvLines
            }
        }

        It -Name 'Should call Invoke-Command once per machine and return rows for each' -Test {
            $result = 'SRV01', 'SRV02' | Get-AuditPolicy
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 2 -Exactly
            ($result | Select-Object -ExpandProperty ComputerName -Unique) | Should -Contain 'SRV01'
            ($result | Select-Object -ExpandProperty ComputerName -Unique) | Should -Contain 'SRV02'
        }
    }

    Context -Name 'Per-machine failure - continues processing remaining machines' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated WinRM failure on SRV01'
                }
                $script:mockCsvLines
            }
            $script:perMachineOutput = 'SRV01', 'SRV02' |
                Get-AuditPolicy -ErrorAction Continue 2>&1
            $script:perMachineErrors = @($script:perMachineOutput | Where-Object {
                $_ -is [System.Management.Automation.ErrorRecord]
            })
            $script:perMachineSuccesses = @($script:perMachineOutput | Where-Object {
                $_ -isnot [System.Management.Automation.ErrorRecord]
            })
        }

        It -Name 'Should write an error for the failing machine' -Test {
            $script:perMachineErrors.Count | Should -BeGreaterThan 0
        }

        It -Name 'Should still return results for the succeeding machine' -Test {
            $script:perMachineSuccesses.Count | Should -Be 5
            ($script:perMachineSuccesses | Select-Object -ExpandProperty ComputerName -Unique) | Should -Be 'SRV02'
        }
    }

    Context -Name 'Local exit-code failure from auditpol.exe' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Output = 'ERROR: Access is denied.'; ExitCode = 1 }
            }
        }

        It -Name 'Should write an error and not throw a terminating exception' -Test {
            { Get-AuditPolicy -ErrorAction Continue } | Should -Not -Throw
        }

        It -Name 'Should write an error record when auditpol exits non-zero' -Test {
            $output = Get-AuditPolicy -ErrorAction SilentlyContinue -ErrorVariable auditErrors
            $output | Should -BeNullOrEmpty
            $auditErrors.Count | Should -BeGreaterThan 0
        }
    }

    Context -Name 'Empty or malformed CSV output' -Fixture {

        BeforeEach {
            Mock -CommandName 'Invoke-NativeCommand' -ModuleName 'PSWinOps' -MockWith {
                [PSCustomObject]@{ Output = ''; ExitCode = 0 }
            }
        }

        It -Name 'Should write an error and return nothing for that machine' -Test {
            $output = Get-AuditPolicy -ErrorAction SilentlyContinue -ErrorVariable auditErrors
            $output | Should -BeNullOrEmpty
            $auditErrors.Count | Should -BeGreaterThan 0
        }
    }

    Context -Name 'Parameter validation' -Fixture {

        It -Name 'Should throw when ComputerName is an empty string' -Test {
            { Get-AuditPolicy -ComputerName '' } | Should -Throw
        }

        It -Name 'Should throw when ComputerName is null' -Test {
            { Get-AuditPolicy -ComputerName $null } | Should -Throw
        }

        It -Name 'Should expose ComputerName with pipeline support by value and by property name' -Test {
            $cmd = Get-Command -Name 'Get-AuditPolicy'
            $attr = $cmd.Parameters['ComputerName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] })[0]
            $attr.ValueFromPipeline | Should -Be $true
            $attr.ValueFromPipelineByPropertyName | Should -Be $true
        }

        It -Name 'Should expose ComputerName aliases CN, Name and DNSHostName' -Test {
            $cmd = Get-Command -Name 'Get-AuditPolicy'
            $aliases = $cmd.Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'Name'
            $aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should not support ShouldProcess (read-only function)' -Test {
            $cmd = Get-Command -Name 'Get-AuditPolicy'
            $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $false
        }
    }
}
