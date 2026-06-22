#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables are assigned in mocks and asserted across separate scopes'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only -- not a real credential'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingComputerNameHardcoded', '',
    Justification = 'Fake target names used exclusively in test fixtures -- no real machines are contacted'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'Stub parameters are declared to satisfy the Pester mock engine (PR #42) but have no body'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    # PSWinOps is Windows-only. On Linux/macOS the module guard throws, so we
    # conditionally import here and skip all tests via -Skip on the Describe block.
    if ($IsWindows -or $PSEdition -eq 'Desktop') {
        Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    }
    $script:ModuleName = 'PSWinOps'

    # ── Stubs for commands referenced only inside the remote scriptblock ──────────
    # Declared with explicit parameters so the Pester mock engine binds correctly
    # (PR #42). Get-IISAppPool (IISAdministration) and Import-Module never run on
    # this host because Invoke-RemoteOrLocal is fully mocked, but the mocks are
    # mandated by the spec, so we stub + mock them defensively.
    if (-not (Get-Command -Name 'Get-IISAppPool' -CommandType Function, Cmdlet, Alias -ErrorAction SilentlyContinue)) {
        function global:Get-IISAppPool {
            param(
                [string]$Name,
                [string]$ErrorAction
            )
        }
    }

    # ── Row factory: builds a hashtable mirroring the shape the scriptblock emits ──
    # (the public function reads each row by key, e.g. $row['Name']).
    function script:New-PoolRow {
        param(
            [string]   $Name = 'DefaultAppPool',
            [string]   $State = 'Started',
            [string]   $ManagedRuntimeVersion = 'v4.0',
            [string]   $ManagedPipelineMode = 'Integrated',
            [string]   $IdentityType = 'ApplicationPoolIdentity',
            [string]   $Username = '',
            [bool]     $AutoStart = $true,
            [string]   $StartMode = 'OnDemand',
            [int]      $QueueLength = 1000,
            [int]      $IdleTimeoutMinutes = 20,
            [int]      $RecyclingPeriodicMinutes = 1740,
            [string[]] $RecyclingScheduledTimes = @(),
            [long]     $RecyclingMemoryLimitKB = [long]0,
            [long]     $RecyclingPrivateMemoryKB = [long]0,
            [int]      $CpuLimitPercent = 0,
            [string]   $CpuLimitAction = 'NoAction'
        )
        return @{
            Name                     = $Name
            State                    = $State
            ManagedRuntimeVersion    = $ManagedRuntimeVersion
            ManagedPipelineMode      = $ManagedPipelineMode
            IdentityType             = $IdentityType
            Username                 = $Username
            AutoStart                = $AutoStart
            StartMode                = $StartMode
            QueueLength              = $QueueLength
            IdleTimeoutMinutes       = $IdleTimeoutMinutes
            RecyclingPeriodicMinutes = $RecyclingPeriodicMinutes
            RecyclingScheduledTimes  = $RecyclingScheduledTimes
            RecyclingMemoryLimitKB   = $RecyclingMemoryLimitKB
            RecyclingPrivateMemoryKB = $RecyclingPrivateMemoryKB
            CpuLimitPercent          = $CpuLimitPercent
            CpuLimitAction           = $CpuLimitAction
        }
    }

    $script:mockDefaultPool = script:New-PoolRow

    $script:mockSpecificUserPool = script:New-PoolRow -Name 'SvcPool' -IdentityType 'SpecificUser' `
        -Username 'CONTOSO\svc-web' -ManagedRuntimeVersion '' -ManagedPipelineMode 'Classic' `
        -State 'Stopped' -AutoStart $false -StartMode 'AlwaysRunning' -QueueLength 2000 `
        -IdleTimeoutMinutes 0 -RecyclingPeriodicMinutes 0 `
        -RecyclingScheduledTimes @('02:00', '14:00') `
        -RecyclingMemoryLimitKB ([long]1048576) -RecyclingPrivateMemoryKB ([long]524288) `
        -CpuLimitPercent 80 -CpuLimitAction 'KillW3wp'

    # Three pools for -Name wildcard / fan-out coverage.
    $script:mockMultiplePools = @(
        (script:New-PoolRow -Name 'api-prod' -State 'Started'),
        (script:New-PoolRow -Name 'api-stage' -State 'Stopped'),
        (script:New-PoolRow -Name 'web-legacy' -State 'Started')
    )
}

Describe 'Get-IISAppPool' -Skip:(-not ($IsWindows -or $PSEdition -eq 'Desktop')) {

    # ─────────────────────────────────────────────────────────────────────────
    # Context 1 -- Local happy path: typed object + all mandatory properties
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Local happy path against $env:COMPUTERNAME' {

        It 'Should return PSWinOps.IISAppPool typed objects for the local computer' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = Get-IISAppPool
            @($result).Count              | Should -Be 1
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISAppPool'
            $result.ComputerName          | Should -Be $env:COMPUTERNAME
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate every output property from the row hashtable' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = Get-IISAppPool
            $result.Name                     | Should -Be 'DefaultAppPool'
            $result.State                    | Should -Be 'Started'
            $result.ManagedRuntimeVersion    | Should -Be 'v4.0'
            $result.ManagedPipelineMode      | Should -Be 'Integrated'
            $result.IdentityType             | Should -Be 'ApplicationPoolIdentity'
            $result.AutoStart                | Should -BeTrue
            $result.StartMode                | Should -Be 'OnDemand'
            $result.QueueLength              | Should -Be 1000
            $result.IdleTimeoutMinutes       | Should -Be 20
            $result.RecyclingPeriodicMinutes | Should -Be 1740
            $result.CpuLimitPercent          | Should -Be 0
            $result.CpuLimitAction           | Should -Be 'NoAction'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit a Timestamp string matching yyyy-MM-dd HH:mm:ss format' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = Get-IISAppPool
            $result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should surface an empty ManagedRuntimeVersion as-is (No Managed Code) for a SpecificUser pool' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockSpecificUserPool
            }
            $result = Get-IISAppPool
            $result.ManagedRuntimeVersion | Should -BeExactly ''
            $result.IdentityType          | Should -Be 'SpecificUser'
            $result.Username              | Should -Be 'CONTOSO\svc-web'
            $result.RecyclingMemoryLimitKB   | Should -Be ([long]1048576)
            $result.RecyclingPrivateMemoryKB | Should -Be ([long]524288)
            $result.CpuLimitPercent       | Should -Be 80
            $result.CpuLimitAction        | Should -Be 'KillW3wp'
            $result.RecyclingScheduledTimes | Should -Contain '02:00'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 2 -- State enum values are passed through verbatim
    # ─────────────────────────────────────────────────────────────────────────
    Context 'State enum values are surfaced verbatim' {

        It 'Should surface State <State>' -TestCases @(
            @{ State = 'Started' }
            @{ State = 'Stopped' }
            @{ State = 'Starting' }
            @{ State = 'Stopping' }
            @{ State = 'Unknown' }
        ) {
            param($State)
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return (script:New-PoolRow -State $State)
            }
            $result = Get-IISAppPool
            $result.State | Should -Be $State
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 3 -- Explicit remote machine via -ComputerName
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Explicit remote machine via -ComputerName' {

        It 'Should stamp ComputerName with the requested target' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = Get-IISAppPool -ComputerName 'WEB01'
            $result.ComputerName | Should -Be 'WEB01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept the CN/Server/MachineName aliases for -ComputerName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = Get-IISAppPool -Server 'WEB42'
            $result.ComputerName | Should -Be 'WEB42'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 4 -- Pipeline of multiple machine names + ComputerName fan-out
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Pipeline and ComputerName fan-out' {

        It 'Should query every machine supplied through the pipeline by value' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = 'WEB01', 'WEB02', 'WEB03' | Get-IISAppPool
            @($result).Count             | Should -Be 3
            ($result.ComputerName | Sort-Object) | Should -Be @('WEB01', 'WEB02', 'WEB03')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 3 -Exactly
        }

        It 'Should fan out across multiple -ComputerName values' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = Get-IISAppPool -ComputerName 'WEB01', 'WEB02'
            @($result).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should accept ComputerName from the pipeline by property name' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockDefaultPool
            }
            $result = [PSCustomObject]@{ ComputerName = 'WEB07' } | Get-IISAppPool
            $result.ComputerName | Should -Be 'WEB07'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should emit one object per pool when a target hosts several pools' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                return $script:mockMultiplePools
            }
            $result = Get-IISAppPool -ComputerName 'WEB01'
            @($result).Count | Should -Be 3
            ($result.Name | Sort-Object) | Should -Be @('api-prod', 'api-stage', 'web-legacy')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 5 -- -Name wildcard filter forwarded via ArgumentList[0]
    # ─────────────────────────────────────────────────────────────────────────
    Context '-Name wildcard filter forwarded into the remote ArgumentList' {

        It 'Should forward -Name patterns to ArgumentList[0]' {
            $script:capturedNameArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedNameArgs = $ArgumentList[0]
                return @()
            }
            $null = Get-IISAppPool -ComputerName 'WEB01' -Name 'api-*'
            $script:capturedNameArgs | Should -Contain 'api-*'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept the AppPoolName alias for -Name' {
            $script:capturedAliasArgs = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedAliasArgs = $ArgumentList[0]
                return @()
            }
            $null = Get-IISAppPool -ComputerName 'WEB01' -AppPoolName 'web-*'
            $script:capturedAliasArgs | Should -Contain 'web-*'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 6 -- Credential propagation to Invoke-RemoteOrLocal
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Credential propagation' {

        It 'Should forward -Credential to Invoke-RemoteOrLocal when supplied' {
            $script:capturedCredential = $null
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedCredential = $Credential
                return $script:mockDefaultPool
            }
            $securePass = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\admin', $securePass)
            $null = Get-IISAppPool -ComputerName 'WEB01' -Credential $cred
            $script:capturedCredential                | Should -Not -BeNullOrEmpty
            $script:capturedCredential.UserName       | Should -Be 'CONTOSO\admin'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should not pass a Credential when none is supplied' {
            $script:capturedNoCred = 'sentinel'
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:capturedNoCred = $Credential
                return $script:mockDefaultPool
            }
            $null = Get-IISAppPool -ComputerName 'WEB01'
            $script:capturedNoCred | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 7 -- Per-machine error isolation (Rule 12)
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Per-machine error isolation' {

        It 'Should write a non-terminating error and continue when a target throws' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $target = $ComputerName
                if ($target -eq 'BROKEN') { throw 'WinRM connection failed' }
                return $script:mockDefaultPool
            }
            $errors = $null
            $result = Get-IISAppPool -ComputerName 'BROKEN', 'WEB02' -ErrorVariable errors -ErrorAction SilentlyContinue
            @($result).Count       | Should -Be 1
            $result.ComputerName   | Should -Be 'WEB02'
            @($errors).Count       | Should -BeGreaterThan 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should write a per-machine error (not throw) when the IIS role is absent' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                throw "IIS is not available on 'WEB01' (no IISAdministration / WebAdministration module and no appcmd.exe)."
            }
            $errors = $null
            { Get-IISAppPool -ComputerName 'WEB01' -ErrorVariable errors -ErrorAction SilentlyContinue } |
                Should -Not -Throw
            @($errors).Count | Should -BeGreaterThan 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Context 8 -- Parameter validation
    # ─────────────────────────────────────────────────────────────────────────
    Context 'Parameter validation' {

        It 'Should reject an empty ComputerName (ValidateNotNullOrEmpty)' {
            { Get-IISAppPool -ComputerName '' } | Should -Throw
        }

        It 'Should reject a null ComputerName (ValidateNotNullOrEmpty)' {
            { Get-IISAppPool -ComputerName $null } | Should -Throw
        }

        It 'Should reject an array containing an empty ComputerName entry' {
            { Get-IISAppPool -ComputerName @('WEB01', '') } | Should -Throw
        }
    }
}
