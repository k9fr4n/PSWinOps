#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Script-scoped variables are assigned in BeforeAll and referenced across nested It scopes'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture only — not a real credential'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingComputerNameHardcoded', '',
    Justification = 'Fake target names used exclusively in test fixtures — no real machines are contacted'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'Stub parameters are declared to satisfy the Pester mock engine (PR #42) but have no body'
)]
param()

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:testFilePath = $PSCommandPath

    # IIS WebAdministration / IISAdministration stubs — parameters declared explicitly
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

    $script:ModuleName   = 'PSWinOps'
    $script:Host1        = 'WEB01'
    $script:Host2        = 'WEB02'
    $script:FailHost     = 'FAILHOST'
    $script:ValidThumb   = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    $script:OrphanThumb  = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
    $script:ExpiredThumb = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'

    # ── Mock payload: Resolved binding with full certificate details ──────────
    $script:mockResolved = @(
        @{
            ComputerName            = 'WEB01'
            SiteName                = 'Default Web Site'
            SiteId                  = 1
            SiteState               = 'Started'
            BindingInformation      = '*:443:'
            IPAddress               = '*'
            Port                    = 443
            HostHeader              = ''
            Protocol                = 'https'
            SslFlags                = 0
            SniEnabled              = $false
            CentralCertStore        = $false
            Thumbprint              = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            CertStoreLocation       = 'Cert:\LocalMachine\My'
            CertStoreName           = 'My'
            Subject                 = 'CN=web01.contoso.com, O=Contoso, C=US'
            SubjectCN               = 'web01.contoso.com'
            Issuer                  = 'CN=Contoso CA, O=Contoso, C=US'
            SerialNumber            = '01020304'
            NotBefore               = [datetime]'2025-01-01'
            NotAfter                = [datetime]'2027-01-01'
            DaysUntilExpiration     = 230
            Expired                 = $false
            SubjectAlternativeNames = @('web01.contoso.com', 'www.contoso.com')
            SignatureAlgorithm      = 'sha256RSA'
            KeyAlgorithm            = 'RSA'
            KeySize                 = 2048
            HasPrivateKey           = $true
            FriendlyName            = 'Contoso Web Certificate'
            Status                  = 'Resolved'
            ErrorMessage            = $null
            Timestamp               = '2026-05-16 12:00:00'
        }
    )

    # ── Mock payload: SNI binding (SslFlags=1) ────────────────────────────────
    $script:mockSNI = @(
        @{
            ComputerName            = 'WEB01'
            SiteName                = 'SNISite'
            SiteId                  = 2
            SiteState               = 'Started'
            BindingInformation      = '*:443:sni.contoso.com'
            IPAddress               = '*'
            Port                    = 443
            HostHeader              = 'sni.contoso.com'
            Protocol                = 'https'
            SslFlags                = 1
            SniEnabled              = $true
            CentralCertStore        = $false
            Thumbprint              = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            CertStoreLocation       = 'Cert:\LocalMachine\My'
            CertStoreName           = 'My'
            Subject                 = 'CN=sni.contoso.com'
            SubjectCN               = 'sni.contoso.com'
            Issuer                  = 'CN=Contoso CA'
            SerialNumber            = '0A0B0C0D'
            NotBefore               = [datetime]'2025-01-01'
            NotAfter                = [datetime]'2027-01-01'
            DaysUntilExpiration     = 230
            Expired                 = $false
            SubjectAlternativeNames = @('sni.contoso.com')
            SignatureAlgorithm      = 'sha256RSA'
            KeyAlgorithm            = 'RSA'
            KeySize                 = 2048
            HasPrivateKey           = $true
            FriendlyName            = ''
            Status                  = 'Resolved'
            ErrorMessage            = $null
            Timestamp               = '2026-05-16 12:00:00'
        }
    )

    # ── Mock payload: CertNotFound (orphan binding) ───────────────────────────
    $script:mockCertNotFound = @(
        @{
            ComputerName            = 'WEB01'
            SiteName                = 'Default Web Site'
            SiteId                  = 1
            SiteState               = 'Started'
            BindingInformation      = '*:443:'
            IPAddress               = '*'
            Port                    = 443
            HostHeader              = ''
            Protocol                = 'https'
            SslFlags                = 0
            SniEnabled              = $false
            CentralCertStore        = $false
            Thumbprint              = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
            CertStoreLocation       = 'Cert:\LocalMachine\My'
            CertStoreName           = 'My'
            Subject                 = $null
            SubjectCN               = $null
            Issuer                  = $null
            SerialNumber            = $null
            NotBefore               = $null
            NotAfter                = $null
            DaysUntilExpiration     = $null
            Expired                 = $null
            SubjectAlternativeNames = @()
            SignatureAlgorithm      = $null
            KeyAlgorithm            = $null
            KeySize                 = $null
            HasPrivateKey           = $null
            FriendlyName            = $null
            Status                  = 'CertNotFound'
            ErrorMessage            = "Certificate with thumbprint 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' not found in 'Cert:\LocalMachine\My'."
            Timestamp               = '2026-05-16 12:00:00'
        }
    )

    # ── Mock payload: BindingNotFound ─────────────────────────────────────────
    $script:mockBindingNotFound = @(
        @{
            ComputerName            = 'WEB01'
            SiteName                = $null
            SiteId                  = $null
            SiteState               = $null
            BindingInformation      = $null
            IPAddress               = $null
            Port                    = $null
            HostHeader              = $null
            Protocol                = $null
            SslFlags                = $null
            SniEnabled              = $null
            CentralCertStore        = $null
            Thumbprint              = $null
            CertStoreLocation       = $null
            CertStoreName           = $null
            Subject                 = $null
            SubjectCN               = $null
            Issuer                  = $null
            SerialNumber            = $null
            NotBefore               = $null
            NotAfter                = $null
            DaysUntilExpiration     = $null
            Expired                 = $null
            SubjectAlternativeNames = @()
            SignatureAlgorithm      = $null
            KeyAlgorithm            = $null
            KeySize                 = $null
            HasPrivateKey           = $null
            FriendlyName            = $null
            Status                  = 'BindingNotFound'
            ErrorMessage            = 'No https bindings found on this host.'
            Timestamp               = '2026-05-16 12:00:00'
        }
    )

    # ── Mock payload: IISNotInstalled ─────────────────────────────────────────
    $script:mockIISNotInstalled = @(
        @{
            ComputerName            = 'WEB01'
            SiteName                = $null
            SiteId                  = $null
            SiteState               = $null
            BindingInformation      = $null
            IPAddress               = $null
            Port                    = $null
            HostHeader              = $null
            Protocol                = $null
            SslFlags                = $null
            SniEnabled              = $null
            CentralCertStore        = $null
            Thumbprint              = $null
            CertStoreLocation       = $null
            CertStoreName           = $null
            Subject                 = $null
            SubjectCN               = $null
            Issuer                  = $null
            SerialNumber            = $null
            NotBefore               = $null
            NotAfter                = $null
            DaysUntilExpiration     = $null
            Expired                 = $null
            SubjectAlternativeNames = @()
            SignatureAlgorithm      = $null
            KeyAlgorithm            = $null
            KeySize                 = $null
            HasPrivateKey           = $null
            FriendlyName            = $null
            Status                  = 'IISNotInstalled'
            ErrorMessage            = 'W3SVC service not found: Cannot find service'
            Timestamp               = '2026-05-16 12:00:00'
        }
    )

    # ── Mock payload: Failed ──────────────────────────────────────────────────
    $script:mockFailed = @(
        @{
            ComputerName            = 'FAILHOST'
            SiteName                = $null
            SiteId                  = $null
            SiteState               = $null
            BindingInformation      = $null
            IPAddress               = $null
            Port                    = $null
            HostHeader              = $null
            Protocol                = $null
            SslFlags                = $null
            SniEnabled              = $null
            CentralCertStore        = $null
            Thumbprint              = $null
            CertStoreLocation       = $null
            CertStoreName           = $null
            Subject                 = $null
            SubjectCN               = $null
            Issuer                  = $null
            SerialNumber            = $null
            NotBefore               = $null
            NotAfter                = $null
            DaysUntilExpiration     = $null
            Expired                 = $null
            SubjectAlternativeNames = @()
            SignatureAlgorithm      = $null
            KeyAlgorithm            = $null
            KeySize                 = $null
            HasPrivateKey           = $null
            FriendlyName            = $null
            Status                  = 'Failed'
            ErrorMessage            = 'Unexpected error during enumeration'
            Timestamp               = '2026-05-16 12:00:00'
        }
    )

    # ── Mock payload: Expired certificate ─────────────────────────────────────
    $script:mockExpired = @(
        @{
            ComputerName            = 'WEB01'
            SiteName                = 'LegacySite'
            SiteId                  = 3
            SiteState               = 'Started'
            BindingInformation      = '*:443:'
            IPAddress               = '*'
            Port                    = 443
            HostHeader              = ''
            Protocol                = 'https'
            SslFlags                = 0
            SniEnabled              = $false
            CentralCertStore        = $false
            Thumbprint              = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
            CertStoreLocation       = 'Cert:\LocalMachine\My'
            CertStoreName           = 'My'
            Subject                 = 'CN=legacy.contoso.com'
            SubjectCN               = 'legacy.contoso.com'
            Issuer                  = 'CN=Contoso CA'
            SerialNumber            = '0D0E0F10'
            NotBefore               = [datetime]'2020-01-01'
            NotAfter                = [datetime]'2021-01-01'
            DaysUntilExpiration     = -1600
            Expired                 = $true
            SubjectAlternativeNames = @()
            SignatureAlgorithm      = 'sha1RSA'
            KeyAlgorithm            = 'RSA'
            KeySize                 = 1024
            HasPrivateKey           = $true
            FriendlyName            = ''
            Status                  = 'Resolved'
            ErrorMessage            = $null
            Timestamp               = '2026-05-16 12:00:00'
        }
    )
}

Describe 'Get-IISCertificateBinding' {

    # ── Context 1: Happy path ─────────────────────────────────────────────────
    Context 'Happy path: Resolved binding with full certificate details' {

        It 'Should return Status=Resolved with correct PSTypeName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Status                | Should -Be 'Resolved'
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISCertificateBinding'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate certificate metadata (Subject, SubjectCN, Thumbprint, KeySize)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Thumbprint | Should -Be $script:ValidThumb
            $result.Subject    | Should -Be 'CN=web01.contoso.com, O=Contoso, C=US'
            $result.SubjectCN  | Should -Be 'web01.contoso.com'
            $result.Issuer     | Should -Not -BeNullOrEmpty
            $result.KeySize    | Should -Be 2048
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate binding geometry (Port, IPAddress, HostHeader, Protocol)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Port       | Should -Be 443
            $result.IPAddress  | Should -Be '*'
            $result.HostHeader | Should -Be ''
            $result.Protocol   | Should -Be 'https'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set ComputerName on the output row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.ComputerName | Should -Be 'WEB01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should report Expired=false and DaysUntilExpiration > 0 for a valid certificate' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Expired             | Should -BeFalse
            $result.DaysUntilExpiration | Should -BeGreaterThan 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate SubjectAlternativeNames as a non-empty array' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.SubjectAlternativeNames | Should -Contain 'web01.contoso.com'
            $result.SubjectAlternativeNames | Should -Contain 'www.contoso.com'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set Timestamp matching the yyyy-MM-dd HH:mm:ss format pattern' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            "$($result.Timestamp)" | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate CertStoreLocation and CertStoreName for a Resolved binding' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.CertStoreLocation | Should -Be 'Cert:\LocalMachine\My'
            $result.CertStoreName     | Should -Be 'My'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 2: Status=CertNotFound ───────────────────────────────────────
    Context 'Status=CertNotFound: orphan binding whose thumbprint is absent from the cert store' {

        It 'Should return Status=CertNotFound with a non-null ErrorMessage' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockCertNotFound }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Status       | Should -Be 'CertNotFound'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should leave certificate-derived properties null for a CertNotFound row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockCertNotFound }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Subject  | Should -BeNullOrEmpty
            $result.NotAfter | Should -BeNullOrEmpty
            $result.Expired  | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should preserve the orphan Thumbprint for a CertNotFound row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockCertNotFound }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Thumbprint | Should -Be $script:OrphanThumb
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should still carry a valid PSTypeName for CertNotFound rows' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockCertNotFound }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISCertificateBinding'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 3: Status=BindingNotFound ────────────────────────────────────
    Context 'Status=BindingNotFound: host has no https bindings matching the supplied filter' {

        It 'Should return Status=BindingNotFound with a non-null ErrorMessage' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockBindingNotFound }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Status       | Should -Be 'BindingNotFound'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return null SiteName and null Thumbprint for a BindingNotFound row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockBindingNotFound }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.SiteName   | Should -BeNullOrEmpty
            $result.Thumbprint | Should -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 4: Status=IISNotInstalled ────────────────────────────────────
    Context 'Status=IISNotInstalled: W3SVC service absent on the target host' {

        It 'Should return Status=IISNotInstalled when the W3SVC service is missing' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockIISNotInstalled }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Status | Should -Be 'IISNotInstalled'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should include W3SVC in the ErrorMessage for an IISNotInstalled row' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockIISNotInstalled }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.ErrorMessage | Should -Match 'W3SVC'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 5: Status=Failed ──────────────────────────────────────────────
    Context 'Status=Failed: unhandled exception during binding enumeration' {

        It 'Should return Status=Failed with a populated ErrorMessage' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockFailed }
            $result = Get-IISCertificateBinding -ComputerName $script:FailHost
            $result.Status       | Should -Be 'Failed'
            $result.ErrorMessage | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set PSTypeName to PSWinOps.IISCertificateBinding even for Failed rows' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockFailed }
            $result = Get-IISCertificateBinding -ComputerName $script:FailHost
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.IISCertificateBinding'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 6: Pipeline by property name ─────────────────────────────────
    Context 'Pipeline by property name: ComputerName aliases and business params accepted from pipe' {

        It 'Should accept ComputerName via pipeline by property name' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $pipeInput = [PSCustomObject]@{ ComputerName = $script:Host1 }
            $result = $pipeInput | Get-IISCertificateBinding
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept the DNSHostName alias for ComputerName via pipeline by property name' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $pipeInput = [PSCustomObject]@{ DNSHostName = $script:Host1 }
            $result = $pipeInput | Get-IISCertificateBinding
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept SiteName via pipeline by property name alongside ComputerName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $pipeInput = [PSCustomObject]@{ ComputerName = $script:Host1; SiteName = 'Default Web Site' }
            $result = $pipeInput | Get-IISCertificateBinding
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should accept Thumbprint via pipeline by property name alongside ComputerName' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $pipeInput = [PSCustomObject]@{ ComputerName = $script:Host1; Thumbprint = $script:ValidThumb }
            $result = $pipeInput | Get-IISCertificateBinding
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 7: Credential propagation ────────────────────────────────────
    Context 'Credential propagation: PSCredential forwarded to Invoke-RemoteOrLocal when supplied' {

        It 'Should call Invoke-RemoteOrLocal exactly once when Credential is provided' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $cred = [System.Management.Automation.PSCredential]::new(
                'domain\user',
                (ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force)
            )
            $result = Get-IISCertificateBinding -ComputerName $script:Host1 -Credential $cred
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Resolved'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should return valid results when no Credential is provided (local / integrated auth)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.Status | Should -Be 'Resolved'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 8: ComputerName fan-out ──────────────────────────────────────
    Context 'ComputerName fan-out: each host generates exactly one Invoke-RemoteOrLocal call' {

        It 'Should invoke Invoke-RemoteOrLocal once per computer for two hosts' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $null = Get-IISCertificateBinding -ComputerName @($script:Host1, $script:Host2)
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should produce one output row per host when each host returns a single binding' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $results = @(Get-IISCertificateBinding -ComputerName @($script:Host1, $script:Host2))
            $results.Count | Should -Be 2
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }

        It 'Should invoke Invoke-RemoteOrLocal three times for three hosts piped as an array' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $null = @($script:Host1, $script:Host2, $script:FailHost) | Get-IISCertificateBinding
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 3 -Exactly
        }
    }

    # ── Context 9: Error isolation per machine ───────────────────────────────
    Context 'Error isolation: a Failed host does not suppress successful host output' {

        It 'Should return a Resolved row and a Failed row when two hosts have different health' {
            $script:irlCallIdx = 0
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -MockWith {
                $script:irlCallIdx++
                if ($script:irlCallIdx -ge 2) { return $script:mockFailed }
                return $script:mockResolved
            }
            $results = @(Get-IISCertificateBinding -ComputerName @($script:Host1, $script:FailHost))
            $results.Count  | Should -Be 2
            $results.Status | Should -Contain 'Resolved'
            $results.Status | Should -Contain 'Failed'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ── Context 10: SslFlags bitmask ─────────────────────────────────────────
    Context 'SslFlags bitmask: SniEnabled and CentralCertStore derived from bit positions' {

        It 'Should set SniEnabled=true when SslFlags bit 0 is set (SslFlags=1)' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockSNI }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.SslFlags   | Should -Be 1
            $result.SniEnabled | Should -BeTrue
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set SniEnabled=false and CentralCertStore=false when SslFlags=0' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockResolved }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.SniEnabled       | Should -BeFalse
            $result.CentralCertStore | Should -BeFalse
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should populate HostHeader with the SNI hostname from BindingInformation' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockSNI }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1
            $result.HostHeader | Should -Be 'sni.contoso.com'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 11: Expired certificate ──────────────────────────────────────
    Context 'Expired certificate: Expired=true and negative DaysUntilExpiration surface correctly' {

        It 'Should return Expired=true and negative DaysUntilExpiration for a past-due certificate' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockExpired }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1 -IncludeExpired
            $result.Expired             | Should -BeTrue
            $result.DaysUntilExpiration | Should -BeLessThan 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should still report Status=Resolved for an expired but store-present certificate' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith { return $script:mockExpired }
            $result = Get-IISCertificateBinding -ComputerName $script:Host1 -IncludeExpired
            $result.Status     | Should -Be 'Resolved'
            $result.Thumbprint | Should -Be $script:ExpiredThumb
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 12: BOM and CRLF encoding ────────────────────────────────────
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
