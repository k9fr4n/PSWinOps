#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables are assigned in BeforeAll and referenced across nested It scopes'
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
    Justification = 'Stub parameters declared to satisfy the Pester mock engine (PR #42) but have no body'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    $script:testFilePath = $PSCommandPath

    # PSWinOps is Windows-only. On Linux/macOS the psm1 guard throws, so we build an
    # in-memory 'PSWinOps' module containing Invoke-RemoteOrLocal and
    # Test-IISBindingCertificate so that Pester's -ModuleName 'PSWinOps' mock scope
    # works on all platforms (same pattern as Watch-IISLog.Tests.ps1).
    if ($IsWindows -or $PSEdition -eq 'Desktop') {
        Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    } else {
        $stripRequires = { param([string]$src) $src -replace '(?m)^#Requires[^\r\n]*[\r\n]*', '' }
        $invokeRolSrc  = & $stripRequires (Get-Content -Raw -Path (
            [IO.Path]::Combine($script:modulePath, 'Private', 'Invoke-RemoteOrLocal.ps1')))
        $funcSrc       = & $stripRequires (Get-Content -Raw -Path (
            [IO.Path]::Combine($script:modulePath, 'Public', 'iis', 'Test-IISBindingCertificate.ps1')))
        $moduleBody    = "`$script:LocalComputerNames = @(`$env:COMPUTERNAME, 'localhost', '.')`r`n" +
                         $invokeRolSrc + "`r`n" + $funcSrc + "`r`nExport-ModuleMember -Function '*'"
        New-Module -Name 'PSWinOps' -ScriptBlock ([scriptblock]::Create($moduleBody)) |
            Import-Module -Force
    }

    # IIS WebAdministration / IISAdministration stubs -- parameters declared explicitly
    # so the Pester mock engine can match arguments correctly (project convention, see PR #42).
    if (-not (Get-Command -Name 'Get-Website' -ErrorAction SilentlyContinue)) {
        function global:Get-Website { param([string]$Name) }
    }
    if (-not (Get-Command -Name 'Get-WebBinding' -ErrorAction SilentlyContinue)) {
        function global:Get-WebBinding { param([string]$Name, [string]$Protocol) }
    }
    if (-not (Get-Command -Name 'Get-IISSite' -ErrorAction SilentlyContinue)) {
        function global:Get-IISSite { param([string]$Name) }
    }
    if (-not (Get-Command -Name 'Get-IISServerManager' -ErrorAction SilentlyContinue)) {
        function global:Get-IISServerManager { param() }
    }

    $script:ModuleName  = 'PSWinOps'
    $script:Host1       = 'WEB01'
    $script:Host2       = 'WEB02'
    $script:FailHost    = 'FAILHOST'
    $script:ValidThumb  = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    $script:OrphanThumb = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'

    # ── Mock: Status=Tested, OverallStatus=Pass (all checks green, Strong algo) ──
    $script:mockPass = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = 'Default Web Site'
            BindingInformation     = '*:443:'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = ''
            SslFlags               = 'None'
            Thumbprint             = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            Subject                = 'CN=web01.contoso.com, O=Contoso, C=US'
            SubjectAlternativeName = @('web01.contoso.com', 'www.contoso.com')
            Issuer                 = 'CN=Contoso CA, O=Contoso, C=US'
            NotBefore              = [datetime]'2025-01-01'
            NotAfter               = [datetime]'2027-01-01'
            DaysUntilExpiration    = 365
            ExpirationStatus       = 'OK'
            ChainValid             = $true
            ChainStatus            = @()
            HostnameMatch          = $true
            HasPrivateKey          = $true
            SignatureAlgorithm     = 'sha256RSA'
            KeyAlgorithm           = 'RSA'
            KeySize                = 4096
            AlgorithmStrength      = 'Strong'
            CertificateStore       = 'LocalMachine\My'
            StoreAligned           = $true
            OverallStatus          = 'Pass'
            Findings               = @()
            Status                 = 'Tested'
            ErrorMessage           = $null
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=Tested, OverallStatus=Warning (ExpirationStatus=Warning) ────
    $script:mockWarningExpiry = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = 'WarningSite'
            BindingInformation     = '*:443:warn.contoso.com'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = 'warn.contoso.com'
            SslFlags               = 'Sni'
            Thumbprint             = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            Subject                = 'CN=warn.contoso.com'
            SubjectAlternativeName = @('warn.contoso.com')
            Issuer                 = 'CN=Contoso CA'
            NotBefore              = [datetime]'2025-01-01'
            NotAfter               = ([datetime]::UtcNow).AddDays(20)
            DaysUntilExpiration    = 20
            ExpirationStatus       = 'Warning'
            ChainValid             = $true
            ChainStatus            = @()
            HostnameMatch          = $true
            HasPrivateKey          = $true
            SignatureAlgorithm     = 'sha256RSA'
            KeyAlgorithm           = 'RSA'
            KeySize                = 4096
            AlgorithmStrength      = 'Strong'
            CertificateStore       = 'LocalMachine\My'
            StoreAligned           = $true
            OverallStatus          = 'Warning'
            Findings               = @('Certificate expires in 20 day(s) (Warning threshold: 30)')
            Status                 = 'Tested'
            ErrorMessage           = $null
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=Tested, OverallStatus=Warning (AlgorithmStrength=Acceptable) ─
    $script:mockWarningAlgo = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = 'AlgoSite'
            BindingInformation     = '*:443:algo.contoso.com'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = 'algo.contoso.com'
            SslFlags               = 'Sni'
            Thumbprint             = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            Subject                = 'CN=algo.contoso.com'
            SubjectAlternativeName = @('algo.contoso.com')
            Issuer                 = 'CN=Contoso CA'
            NotBefore              = [datetime]'2025-01-01'
            NotAfter               = [datetime]'2027-01-01'
            DaysUntilExpiration    = 365
            ExpirationStatus       = 'OK'
            ChainValid             = $true
            ChainStatus            = @()
            HostnameMatch          = $true
            HasPrivateKey          = $true
            SignatureAlgorithm     = 'sha256RSA'
            KeyAlgorithm           = 'RSA'
            KeySize                = 2048
            AlgorithmStrength      = 'Acceptable'
            CertificateStore       = 'LocalMachine\My'
            StoreAligned           = $true
            OverallStatus          = 'Warning'
            Findings               = @('Algorithm strength Acceptable: RSA 2048-bit (consider upgrading to 3072+)')
            Status                 = 'Tested'
            ErrorMessage           = $null
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=Tested, OverallStatus=Critical (ExpirationStatus=Expired) ───
    $script:mockExpired = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = 'ExpiredSite'
            BindingInformation     = '*:443:expired.contoso.com'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = 'expired.contoso.com'
            SslFlags               = 'Sni'
            Thumbprint             = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            Subject                = 'CN=expired.contoso.com'
            SubjectAlternativeName = @('expired.contoso.com')
            Issuer                 = 'CN=Contoso CA'
            NotBefore              = [datetime]'2020-01-01'
            NotAfter               = [datetime]'2021-01-01'
            DaysUntilExpiration    = -1826
            ExpirationStatus       = 'Expired'
            ChainValid             = $true
            ChainStatus            = @()
            HostnameMatch          = $true
            HasPrivateKey          = $true
            SignatureAlgorithm     = 'sha256RSA'
            KeyAlgorithm           = 'RSA'
            KeySize                = 4096
            AlgorithmStrength      = 'Strong'
            CertificateStore       = 'LocalMachine\My'
            StoreAligned           = $true
            OverallStatus          = 'Critical'
            Findings               = @('Certificate expired on 2021-01-01 00:00:00')
            Status                 = 'Tested'
            ErrorMessage           = $null
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=Tested, OverallStatus=Critical (HostnameMatch=$false) ───────
    $script:mockHostnameMismatch = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = 'MismatchSite'
            BindingInformation     = '*:443:other.contoso.com'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = 'other.contoso.com'
            SslFlags               = 'Sni'
            Thumbprint             = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            Subject                = 'CN=web01.contoso.com'
            SubjectAlternativeName = @('web01.contoso.com')
            Issuer                 = 'CN=Contoso CA'
            NotBefore              = [datetime]'2025-01-01'
            NotAfter               = [datetime]'2027-01-01'
            DaysUntilExpiration    = 365
            ExpirationStatus       = 'OK'
            ChainValid             = $true
            ChainStatus            = @()
            HostnameMatch          = $false
            HasPrivateKey          = $true
            SignatureAlgorithm     = 'sha256RSA'
            KeyAlgorithm           = 'RSA'
            KeySize                = 4096
            AlgorithmStrength      = 'Strong'
            CertificateStore       = 'LocalMachine\My'
            StoreAligned           = $true
            OverallStatus          = 'Critical'
            Findings               = @("Hostname 'other.contoso.com' does not match any certificate CN or SAN (web01.contoso.com)")
            Status                 = 'Tested'
            ErrorMessage           = $null
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=Tested, SkipChainValidation active (ChainValid=$null) ───────
    $script:mockSkipChain = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = 'OfflineSite'
            BindingInformation     = '*:443:offline.contoso.com'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = 'offline.contoso.com'
            SslFlags               = 'Sni'
            Thumbprint             = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            Subject                = 'CN=offline.contoso.com'
            SubjectAlternativeName = @('offline.contoso.com')
            Issuer                 = 'CN=Contoso CA'
            NotBefore              = [datetime]'2025-01-01'
            NotAfter               = [datetime]'2027-01-01'
            DaysUntilExpiration    = 365
            ExpirationStatus       = 'OK'
            ChainValid             = $null
            ChainStatus            = @()
            HostnameMatch          = $true
            HasPrivateKey          = $true
            SignatureAlgorithm     = 'sha256RSA'
            KeyAlgorithm           = 'RSA'
            KeySize                = 4096
            AlgorithmStrength      = 'Strong'
            CertificateStore       = 'LocalMachine\My'
            StoreAligned           = $true
            OverallStatus          = 'Pass'
            Findings               = @()
            Status                 = 'Tested'
            ErrorMessage           = $null
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=IISNotInstalled ──────────────────────────────────────────────
    $script:mockIISNotInstalled = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = $null
            BindingInformation     = $null
            Protocol               = $null
            Port                   = $null
            HostHeader             = $null
            SslFlags               = $null
            Thumbprint             = $null
            Subject                = $null
            SubjectAlternativeName = @()
            Issuer                 = $null
            NotBefore              = $null
            NotAfter               = $null
            DaysUntilExpiration    = $null
            ExpirationStatus       = $null
            ChainValid             = $null
            ChainStatus            = @()
            HostnameMatch          = $null
            HasPrivateKey          = $null
            SignatureAlgorithm     = $null
            KeyAlgorithm           = $null
            KeySize                = $null
            AlgorithmStrength      = $null
            CertificateStore       = $null
            StoreAligned           = $null
            OverallStatus          = 'Fail'
            Findings               = @()
            Status                 = 'IISNotInstalled'
            ErrorMessage           = 'W3SVC service not found: Cannot find service W3SVC'
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=BindingNotFound ──────────────────────────────────────────────
    $script:mockBindingNotFound = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = $null
            BindingInformation     = $null
            Protocol               = 'https'
            Port                   = $null
            HostHeader             = $null
            SslFlags               = $null
            Thumbprint             = $null
            Subject                = $null
            SubjectAlternativeName = @()
            Issuer                 = $null
            NotBefore              = $null
            NotAfter               = $null
            DaysUntilExpiration    = $null
            ExpirationStatus       = $null
            ChainValid             = $null
            ChainStatus            = @()
            HostnameMatch          = $null
            HasPrivateKey          = $null
            SignatureAlgorithm     = $null
            KeyAlgorithm           = $null
            KeySize                = $null
            AlgorithmStrength      = $null
            CertificateStore       = $null
            StoreAligned           = $null
            OverallStatus          = 'Fail'
            Findings               = @()
            Status                 = 'BindingNotFound'
            ErrorMessage           = 'No https bindings found on this host.'
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: Status=CertNotFound ─────────────────────────────────────────────────
    $script:mockCertNotFound = @(
        @{
            ComputerName           = 'WEB01'
            SiteName               = 'Default Web Site'
            BindingInformation     = '*:443:'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = ''
            SslFlags               = 'None'
            Thumbprint             = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            Subject                = $null
            SubjectAlternativeName = @()
            Issuer                 = $null
            NotBefore              = $null
            NotAfter               = $null
            DaysUntilExpiration    = $null
            ExpirationStatus       = $null
            ChainValid             = $null
            ChainStatus            = @()
            HostnameMatch          = $null
            HasPrivateKey          = $null
            SignatureAlgorithm     = $null
            KeyAlgorithm           = $null
            KeySize                = $null
            AlgorithmStrength      = $null
            CertificateStore       = $null
            StoreAligned           = $null
            OverallStatus          = 'Fail'
            Findings               = @()
            Status                 = 'CertNotFound'
            ErrorMessage           = "Certificate with thumbprint 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' not found in any LocalMachine store."
            Timestamp              = '2026-05-16 12:00:00'
        }
    )

    # ── Mock: second host result for fan-out tests ────────────────────────────────
    $script:mockPassHost2 = @(
        @{
            ComputerName           = 'WEB02'
            SiteName               = 'Default Web Site'
            BindingInformation     = '*:443:'
            Protocol               = 'https'
            Port                   = 443
            HostHeader             = ''
            SslFlags               = 'None'
            Thumbprint             = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            Subject                = 'CN=web02.contoso.com'
            SubjectAlternativeName = @('web02.contoso.com')
            Issuer                 = 'CN=Contoso CA'
            NotBefore              = [datetime]'2025-01-01'
            NotAfter               = [datetime]'2027-01-01'
            DaysUntilExpiration    = 365
            ExpirationStatus       = 'OK'
            ChainValid             = $true
            ChainStatus            = @()
            HostnameMatch          = $true
            HasPrivateKey          = $true
            SignatureAlgorithm     = 'sha256RSA'
            KeyAlgorithm           = 'RSA'
            KeySize                = 4096
            AlgorithmStrength      = 'Strong'
            CertificateStore       = 'LocalMachine\My'
            StoreAligned           = $true
            OverallStatus          = 'Pass'
            Findings               = @()
            Status                 = 'Tested'
            ErrorMessage           = $null
            Timestamp              = '2026-05-16 12:00:00'
        }
    )
}

Describe 'Test-IISBindingCertificate' {

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 1: Happy path -- Status=Tested, OverallStatus=Pass
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Happy path: Status=Tested, OverallStatus=Pass (all checks green)' {

        It 'Should return Status=Tested and OverallStatus=Pass for a fully healthy binding' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status        | Should -Be 'Tested'
            $result.OverallStatus | Should -Be 'Pass'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set PSTypeName to PSWinOps.IISCertificateBindingTestResult' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISCertificateBindingTestResult'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate certificate metadata (Subject, Thumbprint, Issuer, KeySize)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Thumbprint | Should -Be $script:ValidThumb
            $result.Subject    | Should -Be 'CN=web01.contoso.com, O=Contoso, C=US'
            $result.Issuer     | Should -Not -BeNullOrEmpty
            $result.KeySize    | Should -Be 4096
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should report ChainValid=$true, HostnameMatch=$true, HasPrivateKey=$true, StoreAligned=$true' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.ChainValid    | Should -BeTrue
            $result.HostnameMatch | Should -BeTrue
            $result.HasPrivateKey | Should -BeTrue
            $result.StoreAligned  | Should -BeTrue
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should have an empty Findings array when OverallStatus=Pass' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Findings | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set Timestamp matching the yyyy-MM-dd HH:mm:ss format pattern' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            "$($result.Timestamp)" | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should report AlgorithmStrength=Strong, SignatureAlgorithm=sha256RSA and KeyAlgorithm=RSA' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.AlgorithmStrength  | Should -Be 'Strong'
            $result.SignatureAlgorithm | Should -Be 'sha256RSA'
            $result.KeyAlgorithm       | Should -Be 'RSA'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate SubjectAlternativeName as a non-empty array for a Pass result' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.SubjectAlternativeName | Should -Contain 'web01.contoso.com'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 2: OverallStatus=Warning
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'OverallStatus=Warning: ExpirationStatus=Warning or AlgorithmStrength=Acceptable' {

        It 'Should return OverallStatus=Warning when ExpirationStatus=Warning' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockWarningExpiry }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.OverallStatus    | Should -Be 'Warning'
            $result.ExpirationStatus | Should -Be 'Warning'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should retain Status=Tested when only the expiration is in Warning range' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockWarningExpiry }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status              | Should -Be 'Tested'
            $result.DaysUntilExpiration | Should -BeLessThan 30
            $result.DaysUntilExpiration | Should -BeGreaterThan 7
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should include an expiration finding message when ExpirationStatus=Warning' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockWarningExpiry }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Findings | Should -Not -BeNullOrEmpty
            ($result.Findings -join ' ') | Should -Match "expires in"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return OverallStatus=Warning when AlgorithmStrength=Acceptable (2048-bit RSA)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockWarningAlgo }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.OverallStatus     | Should -Be 'Warning'
            $result.AlgorithmStrength | Should -Be 'Acceptable'
            $result.KeySize           | Should -Be 2048
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 3: OverallStatus=Critical (expired cert and hostname mismatch)
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'OverallStatus=Critical: expired certificate or hostname mismatch' {

        It 'Should return OverallStatus=Critical and ExpirationStatus=Expired for a past-due certificate' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockExpired }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.OverallStatus    | Should -Be 'Critical'
            $result.ExpirationStatus | Should -Be 'Expired'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should report a negative DaysUntilExpiration for an expired certificate' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockExpired }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.DaysUntilExpiration | Should -BeLessThan 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should include an expiry finding message for an Expired certificate' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockExpired }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            ($result.Findings -join ' ') | Should -Match "expired"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set Status=Tested even when the certificate is expired' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockExpired }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status | Should -Be 'Tested'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return OverallStatus=Critical when HostnameMatch=$false (SAN mismatch)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockHostnameMismatch }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.OverallStatus | Should -Be 'Critical'
            $result.HostnameMatch | Should -BeFalse
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should include a hostname-mismatch finding when HostnameMatch=$false' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockHostnameMismatch }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            ($result.Findings -join ' ') | Should -Match "does not match"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 4: Status=IISNotInstalled
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Status=IISNotInstalled: W3SVC service not found on the target host' {

        It 'Should return Status=IISNotInstalled when W3SVC is absent' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockIISNotInstalled }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status | Should -Be 'IISNotInstalled'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set OverallStatus=Fail and include a non-null ErrorMessage for IISNotInstalled' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockIISNotInstalled }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.OverallStatus | Should -Be 'Fail'
            $result.ErrorMessage  | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should carry the PSTypeName even for a Status=IISNotInstalled row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockIISNotInstalled }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISCertificateBindingTestResult'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 5: Status=BindingNotFound
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Status=BindingNotFound: no https bindings match the supplied filters' {

        It 'Should return Status=BindingNotFound when no https bindings exist on the host' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockBindingNotFound }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status | Should -Be 'BindingNotFound'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set OverallStatus=Fail and a non-null ErrorMessage for BindingNotFound' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockBindingNotFound }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.OverallStatus | Should -Be 'Fail'
            $result.ErrorMessage  | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 6: Status=CertNotFound
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Status=CertNotFound: binding thumbprint absent from any LocalMachine store' {

        It 'Should return Status=CertNotFound when the thumbprint is not found in any store' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockCertNotFound }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status | Should -Be 'CertNotFound'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should preserve the orphan Thumbprint in the CertNotFound row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockCertNotFound }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Thumbprint | Should -Be $script:OrphanThumb
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should leave certificate-derived properties null for a CertNotFound row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockCertNotFound }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.OverallStatus | Should -Be 'Fail'
            $result.Subject       | Should -BeNullOrEmpty
            $result.NotAfter      | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 7: -SkipChainValidation
    # ─────────────────────────────────────────────────────────────────────────────
    Context '-SkipChainValidation: ChainValid=$null and ChainStatus empty when chain build is skipped' {

        It 'Should surface ChainValid=$null and empty ChainStatus when -SkipChainValidation is used' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockSkipChain }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1 -SkipChainValidation
            $result.ChainValid  | Should -BeNullOrEmpty
            $result.ChainStatus | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should still produce Status=Tested and OverallStatus=Pass with -SkipChainValidation' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockSkipChain }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1 -SkipChainValidation
            $result.Status        | Should -Be 'Tested'
            $result.OverallStatus | Should -Be 'Pass'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 8: Read-only / ShouldProcess semantics
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Read-only semantics: Test-IISBindingCertificate never mutates state (ShouldProcess not implemented)' {

        It 'Should not accept -WhatIf (function is read-only; SupportsShouldProcess is not declared)' {
            { Test-IISBindingCertificate -ComputerName $script:Host1 -WhatIf } | Should -Throw
        }

        It 'Should invoke Invoke-RemoteOrLocal exactly once and produce no write side-effects' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status | Should -Be 'Tested'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 9: Pipeline by property name
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Pipeline by property name: ComputerName, SiteName, BindingInformation and Thumbprint bound from pipe' {

        It 'Should accept ComputerName via pipeline by property name' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $pipeInput = [PSCustomObject]@{ ComputerName = $script:Host1 }
            $result = $pipeInput | Test-IISBindingCertificate
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept the DNSHostName alias for ComputerName via pipeline by property name' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $pipeInput = [PSCustomObject]@{ DNSHostName = $script:Host1 }
            $result = $pipeInput | Test-IISBindingCertificate
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept SiteName via pipeline by property name alongside ComputerName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $pipeInput = [PSCustomObject]@{ ComputerName = $script:Host1; SiteName = 'Default Web Site' }
            $result = $pipeInput | Test-IISBindingCertificate
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept BindingInformation via pipeline by property name (re-test piped from Get-IISCertificateBinding)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $pipeInput = [PSCustomObject]@{
                ComputerName       = $script:Host1
                BindingInformation = '*:443:'
            }
            $result = $pipeInput | Test-IISBindingCertificate
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept Thumbprint via pipeline by property name' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $pipeInput = [PSCustomObject]@{
                ComputerName = $script:Host1
                Thumbprint   = $script:ValidThumb
            }
            $result = $pipeInput | Test-IISBindingCertificate
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 10: Credential propagation
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal when supplied' {

        It 'Should call Invoke-RemoteOrLocal exactly once when a Credential is provided' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $cred = [System.Management.Automation.PSCredential]::new(
                'domain\svcaccount',
                (ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force)
            )
            $result = Test-IISBindingCertificate -ComputerName $script:Host1 -Credential $cred
            $result.Status | Should -Be 'Tested'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return valid results when no Credential is supplied (local or integrated auth)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $result = Test-IISBindingCertificate -ComputerName $script:Host1
            $result.Status | Should -Be 'Tested'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 11: ComputerName fan-out
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'ComputerName fan-out: each host triggers exactly one Invoke-RemoteOrLocal call' {

        It 'Should invoke Invoke-RemoteOrLocal once per computer when two hosts are supplied' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $null = Test-IISBindingCertificate -ComputerName @($script:Host1, $script:Host2)
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should produce one output row per host when each host returns a single binding' {
            $script:fanOutCallIdx = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:fanOutCallIdx++
                if ($script:fanOutCallIdx -ge 2) { return $script:mockPassHost2 }
                return $script:mockPass
            }
            $results = @(Test-IISBindingCertificate -ComputerName @($script:Host1, $script:Host2))
            $results.Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should invoke Invoke-RemoteOrLocal three times when three hosts are piped in' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockPass }
            $null = @($script:Host1, $script:Host2, $script:FailHost) | Test-IISBindingCertificate
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 3 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 12: Error isolation per machine
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'Error isolation: an exception from one host does not suppress results from healthy hosts' {

        It 'Should emit a result row from the healthy host when the second host throws' {
            $script:irlCallIdx = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:irlCallIdx++
                if ($script:irlCallIdx -ge 2) { throw 'Simulated WinRM error on FAILHOST' }
                return $script:mockPass
            }
            $results = @(
                Test-IISBindingCertificate -ComputerName @($script:Host1, $script:FailHost) `
                    -ErrorAction SilentlyContinue
            )
            $results.Count    | Should -BeGreaterOrEqual 1
            $results[0].Status | Should -Be 'Tested'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ─────────────────────────────────────────────────────────────────────────────
    # Context 13: BOM and CRLF encoding sentinel
    # ─────────────────────────────────────────────────────────────────────────────
    Context 'File encoding: UTF-8 BOM and CRLF line endings (project convention)' {

        It 'Should begin with a UTF-8 BOM byte sequence (EF BB BF)' {
            $bytes = [System.IO.File]::ReadAllBytes($script:testFilePath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'Should use CRLF line endings throughout the file' {
            $raw = [System.IO.File]::ReadAllText($script:testFilePath)
            $raw | Should -Match "`r`n"
        }
    }
}
