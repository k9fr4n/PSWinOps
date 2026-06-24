BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # ---------------------------------------------------------------------------
    # Stub declarations for every command we mock (parameters must be explicit)
    # ---------------------------------------------------------------------------
    function global:Get-Service    { param($Name, $ErrorAction) }
    function global:Stop-Service   { param($Name, $Force, $ErrorAction) }
    function global:Start-Service  { param($Name, $ErrorAction) }
    function global:Remove-Item    { param($LiteralPath, $Path, $Force, $Recurse, $ErrorAction) }
    function global:Rename-Item    { param($LiteralPath, $NewName, $ErrorAction) }
    function global:Test-Path      { param($Path, $LiteralPath, $PathType) }

    # ---------------------------------------------------------------------------
    # Shared mock return objects
    # ---------------------------------------------------------------------------
    $script:mockSuccessResult = [PSCustomObject]@{
        Status                     = 'Succeeded'
        ServicesStopped            = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
        ServicesStarted            = @('cryptsvc', 'appidsvc', 'wuauserv', 'BITS')
        SoftwareDistributionBackup = 'C:\Windows\SoftwareDistribution.bak'
        Catroot2Backup             = 'C:\Windows\System32\Catroot2.bak'
        QmgrFilesDeleted           = 2
        DllsReregistered           = 36
        DllsFailed                 = 0
        NetworkResetPerformed      = $false
        RebootRequired             = $false
        Failures                   = @()
        Notes                      = @()
    }

    $script:mockPartialResult = [PSCustomObject]@{
        Status                     = 'PartialSuccess'
        ServicesStopped            = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
        ServicesStarted            = @('cryptsvc', 'appidsvc', 'wuauserv', 'BITS')
        SoftwareDistributionBackup = 'C:\Windows\SoftwareDistribution.bak'
        Catroot2Backup             = 'C:\Windows\System32\Catroot2.bak'
        QmgrFilesDeleted           = 0
        DllsReregistered           = 32
        DllsFailed                 = 4
        NetworkResetPerformed      = $false
        RebootRequired             = $false
        Failures                   = @(
            'DLL not found (non-fatal): C:\Windows\System32\wuaueng1.dll'
            'regsvr32 failed for msxml.dll (exit 5): access denied'
        )
        Notes                      = @()
    }

    $script:mockNetworkResetResult = [PSCustomObject]@{
        Status                     = 'Succeeded'
        ServicesStopped            = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
        ServicesStarted            = @('cryptsvc', 'appidsvc', 'wuauserv', 'BITS')
        SoftwareDistributionBackup = 'C:\Windows\SoftwareDistribution.bak'
        Catroot2Backup             = 'C:\Windows\System32\Catroot2.bak'
        QmgrFilesDeleted           = 2
        DllsReregistered           = 36
        DllsFailed                 = 0
        NetworkResetPerformed      = $true
        RebootRequired             = $true
        Failures                   = @()
        Notes                      = @()
    }

    $script:mockUsoclientFallbackResult = [PSCustomObject]@{
        Status                     = 'Succeeded'
        ServicesStopped            = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
        ServicesStarted            = @('cryptsvc', 'appidsvc', 'wuauserv', 'BITS')
        SoftwareDistributionBackup = 'C:\Windows\SoftwareDistribution.bak'
        Catroot2Backup             = 'C:\Windows\System32\Catroot2.bak'
        QmgrFilesDeleted           = 0
        DllsReregistered           = 36
        DllsFailed                 = 0
        NetworkResetPerformed      = $false
        RebootRequired             = $false
        Failures                   = @()
        Notes                      = @(
            'wuauclt.exe not found on this OS build; falling back to usoclient StartScan.'
            'Detection triggered via usoclient StartScan.'
        )
    }
}

Describe -Name 'Reset-WindowsUpdateComponent' -Tag 'Unit' -Fixture {

    # ==========================================================================
    Context 'Function metadata' {
    # ==========================================================================

        It -Name 'Should be an exported function of PSWinOps' -Test {
            Get-Command -Name 'Reset-WindowsUpdateComponent' -Module 'PSWinOps' |
                Should -Not -BeNullOrEmpty
        }

        It -Name 'Should support ShouldProcess (WhatIf parameter present)' -Test {
            (Get-Command -Name 'Reset-WindowsUpdateComponent').Parameters.ContainsKey('WhatIf') |
                Should -BeTrue
        }

        It -Name 'Should have ConfirmImpact High' -Test {
            $attr = (Get-Command -Name 'Reset-WindowsUpdateComponent').ScriptBlock.Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.ConfirmImpact | Should -Be 'High'
        }

        It -Name 'Should declare OutputType PSWinOps.WindowsUpdateResetResult' -Test {
            $outputType = (Get-Command -Name 'Reset-WindowsUpdateComponent').OutputType
            $outputType.Name | Should -Contain 'PSWinOps.WindowsUpdateResetResult'
        }

        It -Name 'Should declare ComputerName accepting pipeline by value' -Test {
            $param = (Get-Command -Name 'Reset-WindowsUpdateComponent').Parameters['ComputerName']
            $param | Should -Not -BeNullOrEmpty
            ($param.Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty ValueFromPipeline
            ) | Should -Contain $true
        }

        It -Name 'Should declare ComputerName with CN and DNSHostName aliases' -Test {
            $aliases = (Get-Command -Name 'Reset-WindowsUpdateComponent').Parameters['ComputerName'].Aliases
            $aliases | Should -Contain 'CN'
            $aliases | Should -Contain 'DNSHostName'
        }

        It -Name 'Should declare IncludeNetworkReset switch parameter' -Test {
            (Get-Command -Name 'Reset-WindowsUpdateComponent').Parameters.ContainsKey('IncludeNetworkReset') |
                Should -BeTrue
        }

        It -Name 'Should declare Credential parameter' -Test {
            (Get-Command -Name 'Reset-WindowsUpdateComponent').Parameters.ContainsKey('Credential') |
                Should -BeTrue
        }
    }

    # ==========================================================================
    Context 'Local happy path - $env:COMPUTERNAME' {
    # ==========================================================================

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            $script:localResult = Reset-WindowsUpdateComponent -Confirm:$false
        }

        It -Name 'Should return a non-null result object' -Test {
            $script:localResult | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have PSTypeName PSWinOps.WindowsUpdateResetResult' -Test {
            $script:localResult.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateResetResult'
        }

        It -Name 'Should have ComputerName matching the local host' -Test {
            $script:localResult.ComputerName | Should -Be $env:COMPUTERNAME
        }

        It -Name 'Should have Status Succeeded' -Test {
            $script:localResult.Status | Should -Be 'Succeeded'
        }

        It -Name 'Should report ServicesStopped' -Test {
            $script:localResult.ServicesStopped | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should report ServicesStarted' -Test {
            $script:localResult.ServicesStarted | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have all 14 mandatory output properties' -Test {
            $expected = @(
                'ComputerName', 'Status', 'ServicesStopped', 'ServicesStarted',
                'SoftwareDistributionBackup', 'Catroot2Backup', 'QmgrFilesDeleted',
                'DllsReregistered', 'DllsFailed', 'NetworkResetPerformed', 'RebootRequired',
                'Failures', 'Notes', 'Timestamp'
            )
            foreach ($prop in $expected) {
                $script:localResult.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It -Name 'Should have Timestamp formatted as yyyy-MM-dd HH:mm:ss' -Test {
            $script:localResult.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It -Name 'Should call Invoke-RemoteOrLocal exactly once for local execution' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            Reset-WindowsUpdateComponent -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    # ==========================================================================
    Context 'Explicit remote machine - SRV01' {
    # ==========================================================================

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            $script:remoteResult = Reset-WindowsUpdateComponent -ComputerName 'SRV01' -Confirm:$false
        }

        It -Name 'Should return exactly one result object' -Test {
            @($script:remoteResult).Count | Should -Be 1
        }

        It -Name 'Should have ComputerName SRV01' -Test {
            $script:remoteResult.ComputerName | Should -Be 'SRV01'
        }

        It -Name 'Should have PSTypeName PSWinOps.WindowsUpdateResetResult' -Test {
            $script:remoteResult.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateResetResult'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once with ComputerName SRV01' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            Reset-WindowsUpdateComponent -ComputerName 'SRV01' -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ComputerName -eq 'SRV01' }
        }
    }

    # ==========================================================================
    Context 'Pipeline - multiple machine names SRV01 and SRV02' {
    # ==========================================================================

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            $script:pipelineResults = 'SRV01', 'SRV02' | Reset-WindowsUpdateComponent -Confirm:$false
        }

        It -Name 'Should return two result objects' -Test {
            @($script:pipelineResults).Count | Should -Be 2
        }

        It -Name 'Should include ComputerName SRV01 in results' -Test {
            ($script:pipelineResults | Select-Object -ExpandProperty ComputerName) | Should -Contain 'SRV01'
        }

        It -Name 'Should include ComputerName SRV02 in results' -Test {
            ($script:pipelineResults | Select-Object -ExpandProperty ComputerName) | Should -Contain 'SRV02'
        }

        It -Name 'Should call Invoke-RemoteOrLocal once per machine (twice total)' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            'SRV01', 'SRV02' | Reset-WindowsUpdateComponent -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }
    }

    # ==========================================================================
    Context 'Per-machine failure - continues processing remaining machines' {
    # ==========================================================================

        It -Name 'Should write error for failing machine and still succeed on remaining one' -Test {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'SRV01') {
                    throw 'Simulated WinRM failure on SRV01'
                }
                return $script:mockSuccessResult
            }
            $allOutput = 'SRV01', 'SRV02' |
                Reset-WindowsUpdateComponent -Confirm:$false 2>&1
            $errors    = @($allOutput | Where-Object -FilterScript {
                $_ -is [System.Management.Automation.ErrorRecord]
            })
            $successes = @($allOutput | Where-Object -FilterScript {
                $_ -isnot [System.Management.Automation.ErrorRecord]
            })
            $errors.Count    | Should -BeGreaterThan 0
            $successes.Count | Should -Be 1
            $successes[0].ComputerName | Should -Be 'SRV02'
        }
    }

    # ==========================================================================
    Context 'DllsFailed - missing DLL yields PartialSuccess without aborting' {
    # ==========================================================================

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockPartialResult
            }
            $script:partialResult = Reset-WindowsUpdateComponent -Confirm:$false
        }

        It -Name 'Should have Status PartialSuccess' -Test {
            $script:partialResult.Status | Should -Be 'PartialSuccess'
        }

        It -Name 'Should have DllsFailed greater than zero' -Test {
            $script:partialResult.DllsFailed | Should -BeGreaterThan 0
        }

        It -Name 'Should have Failures list populated' -Test {
            $script:partialResult.Failures | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should not abort - DllsReregistered is still positive' -Test {
            $script:partialResult.DllsReregistered | Should -BeGreaterThan 0
        }

        It -Name 'Should still carry PSTypeName PSWinOps.WindowsUpdateResetResult' -Test {
            $script:partialResult.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateResetResult'
        }
    }

    # ==========================================================================
    Context 'IncludeNetworkReset - network reset gates executed' {
    # ==========================================================================

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockNetworkResetResult
            }
            $script:networkResult = Reset-WindowsUpdateComponent -IncludeNetworkReset -Confirm:$false
        }

        It -Name 'Should have NetworkResetPerformed true' -Test {
            $script:networkResult.NetworkResetPerformed | Should -BeTrue
        }

        It -Name 'Should have RebootRequired true' -Test {
            $script:networkResult.RebootRequired | Should -BeTrue
        }

        It -Name 'Should pass DoNetworkReset = true in ArgumentList to Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockNetworkResetResult
            }
            Reset-WindowsUpdateComponent -IncludeNetworkReset -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[0] -eq $true }
        }
    }

    # ==========================================================================
    Context 'Without IncludeNetworkReset - network reset gates skipped' {
    # ==========================================================================

        It -Name 'Should pass DoNetworkReset = false in ArgumentList to Invoke-RemoteOrLocal' -Test {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            Reset-WindowsUpdateComponent -Confirm:$false
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[0] -eq $false }
        }

        It -Name 'Should have NetworkResetPerformed false in result' -Test {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            $result = Reset-WindowsUpdateComponent -Confirm:$false
            $result.NetworkResetPerformed | Should -BeFalse
        }
    }

    # ==========================================================================
    Context 'Not elevated - Test-IsAdministrator returns false' {
    # ==========================================================================

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $false
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            $script:notElevatedResult = Reset-WindowsUpdateComponent -Confirm:$false -ErrorAction SilentlyContinue
        }

        It -Name 'Should return a result with Status Failed' -Test {
            $script:notElevatedResult.Status | Should -Be 'Failed'
        }

        It -Name 'Should carry PSTypeName PSWinOps.WindowsUpdateResetResult even on elevation failure' -Test {
            $script:notElevatedResult.PSObject.TypeNames | Should -Contain 'PSWinOps.WindowsUpdateResetResult'
        }

        It -Name 'Should not call Invoke-RemoteOrLocal when elevation check fails' -Test {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $false
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            Reset-WindowsUpdateComponent -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }
    }

    # ==========================================================================
    Context 'wuauclt not present - usoclient fallback recorded in Notes' {
    # ==========================================================================

        BeforeAll {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockUsoclientFallbackResult
            }
            $script:fallbackResult = Reset-WindowsUpdateComponent -Confirm:$false
        }

        It -Name 'Should have Status Succeeded despite wuauclt absence' -Test {
            $script:fallbackResult.Status | Should -Be 'Succeeded'
        }

        It -Name 'Should have a Notes entry mentioning wuauclt not found' -Test {
            ($script:fallbackResult.Notes -join ' ') | Should -Match 'wuauclt'
        }

        It -Name 'Should have a Notes entry mentioning usoclient fallback' -Test {
            ($script:fallbackResult.Notes -join ' ') | Should -Match 'usoclient'
        }
    }

    # ==========================================================================
    Context 'Parameter validation - invalid ComputerName values' {
    # ==========================================================================

        It -Name 'Should throw on empty string ComputerName' -Test {
            { Reset-WindowsUpdateComponent -ComputerName '' -Confirm:$false } | Should -Throw
        }

        It -Name 'Should throw on null ComputerName' -Test {
            { Reset-WindowsUpdateComponent -ComputerName $null -Confirm:$false } | Should -Throw
        }

        It -Name 'Should throw on empty array ComputerName' -Test {
            { Reset-WindowsUpdateComponent -ComputerName @() -Confirm:$false } | Should -Throw
        }
    }

    # ==========================================================================
    Context 'WhatIf - no destructive operations performed' {
    # ==========================================================================

        It -Name 'Should not call Invoke-RemoteOrLocal when -WhatIf is specified' -Test {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            Reset-WindowsUpdateComponent -WhatIf
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 0 -Exactly
        }

        It -Name 'Should not call Stop-Service when -WhatIf is specified' -Test {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            Mock -CommandName 'Stop-Service' -MockWith {}
            Reset-WindowsUpdateComponent -WhatIf
            Should -Invoke -CommandName 'Stop-Service' -Times 0 -Exactly
        }

        It -Name 'Should not call Rename-Item when -WhatIf is specified' -Test {
            Mock -CommandName 'Test-IsAdministrator' -ModuleName 'PSWinOps' -MockWith {
                return $true
            }
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                return $script:mockSuccessResult
            }
            Mock -CommandName 'Rename-Item' -MockWith {}
            Reset-WindowsUpdateComponent -WhatIf
            Should -Invoke -CommandName 'Rename-Item' -Times 0 -Exactly
        }
    }
}
