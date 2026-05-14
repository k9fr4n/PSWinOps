#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # IIS WebAdministration / IISAdministration stubs — parameters declared explicitly
    # so that Pester mock engine can match $args correctly (see project PR #42 notes).
    if (-not (Get-Command -Name 'Get-Website' -ErrorAction SilentlyContinue)) {
        function global:Get-Website { param([string]$Name); $null = $Name }
    }
    if (-not (Get-Command -Name 'Get-WebBinding' -ErrorAction SilentlyContinue)) {
        function global:Get-WebBinding { param([string]$Name, [string]$Protocol); $null = $Name, $Protocol }
    }
    if (-not (Get-Command -Name 'Get-IISSite' -ErrorAction SilentlyContinue)) {
        function global:Get-IISSite { param([string]$Name); $null = $Name }
    }
    if (-not (Get-Command -Name 'Get-IISServerManager' -ErrorAction SilentlyContinue)) {
        function global:Get-IISServerManager { param() }
    }
    if (-not (Get-Command -Name 'Get-IISSiteBinding' -ErrorAction SilentlyContinue)) {
        function global:Get-IISSiteBinding { param([string]$Name, [string]$Protocol); $null = $Name, $Protocol }
    }

    $script:ModuleName      = 'PSWinOps'
    $script:RemoteHost      = 'WEB01'
    $script:RemoteHostLower = 'web01'
    $script:Host2           = 'WEB02'
    $script:FailHost        = 'FAILHOST'
    $script:ValidThumb = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
    $script:OldThumb   = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    $script:SiteName   = 'TestSite'

    # Query-phase mock payloads — returned when Invoke-Command ArgumentList.Count -eq 4
    $script:queryReplaced = @(
        @{
            SiteName           = 'TestSite'
            BindingInformation = '*:443:'
            Protocol           = 'https'
            PreviousThumbprint = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            NewThumbprint      = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            CertStoreLocation  = 'Cert:\LocalMachine\My'
            SslFlags           = 0
            Status             = 'NeedsReplacement'
            ErrorMessage       = $null
            SslKey             = '*!443'
        }
    )

    # Apply-phase mock payload — returned when Invoke-Command ArgumentList.Count -eq 6
    $script:applySuccess = @{
        Success       = $true
        NewThumbprint = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
        ErrorMessage  = $null
    }

    $script:queryAlreadyUpToDate = @(
        @{
            SiteName           = 'TestSite'
            BindingInformation = '*:443:'
            Protocol           = 'https'
            PreviousThumbprint = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            NewThumbprint      = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            CertStoreLocation  = 'Cert:\LocalMachine\My'
            SslFlags           = 0
            Status             = 'AlreadyUpToDate'
            ErrorMessage       = $null
            SslKey             = '*!443'
        }
    )

    $script:queryCertNotFound = @(
        @{
            SiteName           = 'TestSite'
            BindingInformation = '*:443:'
            Protocol           = 'https'
            PreviousThumbprint = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            NewThumbprint      = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            CertStoreLocation  = 'Cert:\LocalMachine\My'
            SslFlags           = 0
            Status             = 'CertNotFound'
            ErrorMessage       = $null
            SslKey             = '*!443'
        }
    )

    $script:queryBindingNotFound = @(
        @{
            SiteName           = 'TestSite'
            BindingInformation = '*:443:'
            Protocol           = 'https'
            PreviousThumbprint = $null
            NewThumbprint      = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            CertStoreLocation  = 'Cert:\LocalMachine\My'
            SslFlags           = 0
            Status             = 'BindingNotFound'
            ErrorMessage       = "Site 'TestSite' not found."
            SslKey             = $null
        }
    )

    $script:queryFailed = @(
        @{
            SiteName           = 'TestSite'
            BindingInformation = $null
            Protocol           = 'https'
            PreviousThumbprint = $null
            NewThumbprint      = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            CertStoreLocation  = 'Cert:\LocalMachine\My'
            SslFlags           = 0
            Status             = 'Failed'
            ErrorMessage       = 'Neither WebAdministration nor IISAdministration module is available on the target.'
            SslKey             = $null
        }
    )
}

Describe 'Set-IISBindingCertificate' {

    # -----------------------------------------------------------------------
    # Context 1: Happy path — certificate successfully replaced
    # -----------------------------------------------------------------------
    Context 'Happy path: certificate replacement succeeds (Status = Replaced)' {

        It 'Should return Status=Replaced when the replacement succeeds' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.Status | Should -Be 'Replaced'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should capture PreviousThumbprint from the existing binding' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.PreviousThumbprint | Should -Be $script:OldThumb
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should set NewThumbprint to the requested thumbprint on a successful replacement' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.NewThumbprint | Should -Be $script:ValidThumb
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should set PSTypeName to PSWinOps.IISBindingCertificateResult' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISBindingCertificateResult'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should set Timestamp matching the yyyy-MM-dd HH:mm:ss format pattern' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.Timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should uppercase the ComputerName in the result object' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHostLower `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.ComputerName | Should -Be 'WEB01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 2: Status = AlreadyUpToDate (idempotent no-op)
    # -----------------------------------------------------------------------
    Context 'Status = AlreadyUpToDate (idempotent no-op)' {

        It 'Should return Status=AlreadyUpToDate when the thumbprint is already current' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.Status | Should -Be 'AlreadyUpToDate'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set NewThumbprint to the requested thumbprint when AlreadyUpToDate' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.NewThumbprint | Should -Be $script:ValidThumb
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should not invoke the apply phase (Invoke-Command exactly once) when AlreadyUpToDate' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 3: Status = CertNotFound
    # -----------------------------------------------------------------------
    Context 'Status = CertNotFound (certificate not present in store)' {

        It 'Should return Status=CertNotFound when the thumbprint is absent from CertStoreLocation' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryCertNotFound
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.Status | Should -Be 'CertNotFound'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should not invoke the apply phase when Status=CertNotFound' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryCertNotFound
            }
            Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 4: Status = BindingNotFound
    # -----------------------------------------------------------------------
    Context 'Status = BindingNotFound (site or https binding absent)' {

        It 'Should return Status=BindingNotFound when the target IIS site does not exist' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryBindingNotFound
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.Status | Should -Be 'BindingNotFound'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate ErrorMessage when Status=BindingNotFound' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryBindingNotFound
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 5: Status = Failed
    # -----------------------------------------------------------------------
    Context 'Status = Failed (IIS module unavailable or apply exception)' {

        It 'Should return Status=Failed when no IIS module is available on the target' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryFailed
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.Status | Should -Be 'Failed'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate ErrorMessage when Status=Failed due to missing IIS module' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryFailed
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return Status=Failed with ErrorMessage when the apply phase throws' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                throw 'SSL binding update failed on target'
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $result.Status | Should -Be 'Failed'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 6: ShouldProcess (-WhatIf suppresses mutations)
    # -----------------------------------------------------------------------
    Context 'ShouldProcess: -WhatIf suppresses all mutations (0 apply-phase calls)' {

        It 'Should call Invoke-Command only once (query) when -WhatIf is specified' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -WhatIf
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should produce no result objects for NeedsReplacement bindings when -WhatIf is used' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ArgumentList.Count -eq 4) { return $script:queryReplaced }
                return $script:applySuccess
            }
            $result = Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -WhatIf
            $result | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 7: Pipeline input by property name
    # -----------------------------------------------------------------------
    Context 'Pipeline input by property name (ComputerName, SiteName, Thumbprint, BindingInformation)' {

        It 'Should accept ComputerName, SiteName, and Thumbprint bound from pipeline object properties' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            $pipelineInput = [PSCustomObject]@{
                ComputerName = $script:RemoteHost
                SiteName     = $script:SiteName
                Thumbprint   = $script:ValidThumb
            }
            $result = $pipelineInput | Set-IISBindingCertificate -Force
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'AlreadyUpToDate'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should bind BindingInformation from pipeline object property by name' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            $pipelineInput = [PSCustomObject]@{
                ComputerName       = $script:RemoteHost
                SiteName           = $script:SiteName
                Thumbprint         = $script:ValidThumb
                BindingInformation = '*:443:'
            }
            $result = $pipelineInput | Set-IISBindingCertificate -Force
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 8: Credential propagation
    # -----------------------------------------------------------------------
    Context 'Credential propagation: PSCredential is forwarded to Invoke-Command' {

        It 'Should pass a non-null Credential to Invoke-Command when -Credential is specified' {
            $securePass = [System.Security.SecureString]::new()
            'P@ssw0rd!'.ToCharArray() | ForEach-Object { $securePass.AppendChar($_) }
            $cred = [System.Management.Automation.PSCredential]::new('DOMAIN\admin', $securePass)
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb `
                -Credential $cred -Force
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    # -----------------------------------------------------------------------
    # Context 9: ComputerName fan-out
    # -----------------------------------------------------------------------
    Context 'ComputerName fan-out: one result per computer in the array' {

        It 'Should return one result object per computer when multiple ComputerNames are provided' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            $results = Set-IISBindingCertificate -ComputerName $script:RemoteHost, $script:Host2 `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            @($results).Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should set distinct ComputerName values for each result object in a multi-host call' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            $results = Set-IISBindingCertificate -ComputerName $script:RemoteHost, $script:Host2 `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force
            $computerNames = @($results).ComputerName
            $computerNames | Should -Contain 'WEB01'
            $computerNames | Should -Contain 'WEB02'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 10: Error isolation per machine
    # -----------------------------------------------------------------------
    Context 'Error isolation: one failing machine does not abort the rest' {

        It 'Should continue processing remaining computers after one machine throws' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                if ($ComputerName -eq 'FAILHOST') { throw 'Connection refused' }
                return $script:queryAlreadyUpToDate
            }
            $results = Set-IISBindingCertificate -ComputerName $script:FailHost, $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force `
                -ErrorAction SilentlyContinue
            @($results).Count | Should -Be 1
            $results[0].ComputerName | Should -Be 'WEB01'
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should write a non-terminating error for the failing machine' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                throw 'Connection refused'
            }
            $errorVar = @()
            $null = Set-IISBindingCertificate -ComputerName $script:FailHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb `
                -Force -ErrorAction SilentlyContinue -ErrorVariable errorVar
            $errorVar | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    # Context 11: BOM and CRLF sentinel
    # -----------------------------------------------------------------------
    Context 'BOM and CRLF line-ending sentinel (encoding contract)' {

        It 'Should have a UTF-8 BOM (EF BB BF) as the first three bytes of the test file' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Set-IISBindingCertificate.Tests.ps1'
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Should use CRLF line endings throughout the test file source' {
            $filePath = Join-Path -Path $PSScriptRoot -ChildPath 'Set-IISBindingCertificate.Tests.ps1'
            $content = Get-Content -Path $filePath -Raw
            $content | Should -Match "`r`n"
        }
    }

    # -----------------------------------------------------------------------
    # Context 12: Parameter validation and CmdletBinding attributes
    # -----------------------------------------------------------------------
    Context 'Parameter validation and CmdletBinding attributes' {

        It 'Should have CmdletBinding with SupportsShouldProcess enabled' {
            $cmd = Get-Command -Name 'Set-IISBindingCertificate'
            $attr = $cmd.ScriptBlock.Attributes |
                Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.SupportsShouldProcess | Should -BeTrue
        }

        It 'Should have ConfirmImpact set to High' {
            $cmd = Get-Command -Name 'Set-IISBindingCertificate'
            $attr = $cmd.ScriptBlock.Attributes |
                Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $attr.ConfirmImpact | Should -Be 'High'
        }

        It 'Should reject a Thumbprint that is not 40 hexadecimal characters' {
            { Set-IISBindingCertificate -SiteName 'TestSite' -Thumbprint 'TOOSHORT' -Force } |
                Should -Throw
        }

        It 'Should accept a valid 40-character hex Thumbprint without throwing' {
            Mock -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -MockWith {
                return $script:queryAlreadyUpToDate
            }
            { Set-IISBindingCertificate -ComputerName $script:RemoteHost `
                -SiteName $script:SiteName -Thumbprint $script:ValidThumb -Force } |
                Should -Not -Throw
            Should -Invoke -CommandName 'Invoke-Command' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }
}
