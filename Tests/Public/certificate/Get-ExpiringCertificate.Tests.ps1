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

    $script:ModuleName = 'PSWinOps'
    $script:Host1       = 'SRV01'
    $script:Host2       = 'SRV02'
    $script:FailHost    = 'FAILHOST'

    # ── Helper: build a fake certificate object ────────────────────────────────
    function script:New-FakeCert {
        param(
            [string]$Subject,
            [string]$Issuer,
            [string]$Thumbprint,
            [datetime]$NotAfter,
            [bool]$HasPrivateKey = $true,
            [string[]]$Eku = @('Server Authentication')
        )
        [PSCustomObject]@{
            Subject             = $Subject
            Issuer              = $Issuer
            Thumbprint          = $Thumbprint
            NotAfter            = $NotAfter
            HasPrivateKey       = $HasPrivateKey
            EnhancedKeyUsageList = @($Eku | ForEach-Object { [PSCustomObject]@{ FriendlyName = $_ } })
        }
    }

    # Certs used for local-path tests (real scriptblock executed via Invoke-RemoteOrLocal,
    # only Get-ChildItem is mocked at the module boundary).
    $script:certSoon = New-FakeCert -Subject 'CN=soon.contoso.com' -Issuer 'CN=Contoso CA' `
        -Thumbprint 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' -NotAfter (Get-Date).AddDays(10)
    $script:certFar = New-FakeCert -Subject 'CN=far.contoso.com' -Issuer 'CN=Contoso CA' `
        -Thumbprint 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' -NotAfter (Get-Date).AddDays(365)
    $script:certExpired = New-FakeCert -Subject 'CN=expired.contoso.com' -Issuer 'CN=Contoso CA' `
        -Thumbprint 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC' -NotAfter (Get-Date).AddDays(-30)
    $script:certSooner = New-FakeCert -Subject 'CN=sooner.contoso.com' -Issuer 'CN=Contoso CA' `
        -Thumbprint 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD' -NotAfter (Get-Date).AddDays(3)

    # Raw rows used for remote-path tests (Invoke-RemoteOrLocal itself is mocked,
    # so these already look like the flattened hashtables the scriptblock returns).
    $script:mockRemoteRow = @(
        @{
            ComputerName     = 'SRV01'
            StoreName        = 'My'
            Subject          = 'CN=remote.contoso.com'
            Issuer           = 'CN=Contoso CA'
            Thumbprint       = 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'
            NotAfter         = (Get-Date).AddDays(15)
            DaysRemaining    = 15
            HasPrivateKey    = $true
            EnhancedKeyUsage = @('Server Authentication')
            Timestamp        = '2026-05-16 12:00:00'
        }
    )
    $script:mockRemoteRowHost2 = @(
        @{
            ComputerName     = 'SRV02'
            StoreName        = 'My'
            Subject          = 'CN=remote2.contoso.com'
            Issuer           = 'CN=Contoso CA'
            Thumbprint       = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'
            NotAfter         = (Get-Date).AddDays(20)
            DaysRemaining    = 20
            HasPrivateKey    = $false
            EnhancedKeyUsage = @()
            Timestamp        = '2026-05-16 12:00:00'
        }
    )
}

Describe 'Get-ExpiringCertificate' {

    # ── Context 1: Local happy path ─────────────────────────────────────────
    Context 'Local happy path: certs under threshold returned, sorted ascending' {

        It 'Should return certs under threshold sorted by NotAfter ascending, with correct PSTypeName' {
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\My' } `
                -MockWith { return @($script:certSoon, $script:certFar, $script:certSooner) }

            $result = Get-ExpiringCertificate -DaysUntilExpiration 30

            $result.Count                 | Should -Be 2
            $result[0].Thumbprint         | Should -Be 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'
            $result[1].Thumbprint         | Should -Be 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSWinOps.ExpiringCertificate'
            $result[0].ComputerName       | Should -Be $env:COMPUTERNAME
            Should -Invoke -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName -Times 1 -Exactly
        }

        It 'Should set Timestamp matching the yyyy-MM-dd HH:mm:ss format pattern' {
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\My' } `
                -MockWith { return @($script:certSoon) }

            $result = Get-ExpiringCertificate -DaysUntilExpiration 30
            "$($result.Timestamp)" | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }

        It 'Should populate EnhancedKeyUsage as a string array' {
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\My' } `
                -MockWith { return @($script:certSoon) }

            $result = Get-ExpiringCertificate -DaysUntilExpiration 30
            $result.EnhancedKeyUsage | Should -Contain 'Server Authentication'
        }
    }

    # ── Context 2: Explicit remote machine with Credential ───────────────────
    Context 'Explicit remote machine with Credential' {

        It 'Should return the remote result and propagate the supplied credential' {
            $securePwd = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new('CONTOSO\svc', $securePwd)

            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith {
                    param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                    $script:capturedCredential = $Credential
                    return $script:mockRemoteRow
                }

            $result = Get-ExpiringCertificate -ComputerName $script:Host1 -Credential $cred

            $result.ComputerName          | Should -Be 'SRV01'
            $result.Thumbprint            | Should -Be 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'
            $script:capturedCredential    | Should -Be $cred
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 1 -Exactly
        }
    }

    # ── Context 3: Pipeline of multiple machine names ─────────────────────────
    Context 'Pipeline of multiple machine names' {

        It 'Should invoke once per machine and return combined results' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith {
                    param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                    if ($ComputerName -eq 'SRV01') { return $script:mockRemoteRow }
                    if ($ComputerName -eq 'SRV02') { return $script:mockRemoteRowHost2 }
                }

            $result = @($script:Host1, $script:Host2) | Get-ExpiringCertificate

            $result.Count | Should -Be 2
            ($result.ComputerName | Sort-Object) | Should -Be @('SRV01', 'SRV02')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ── Context 4: Per-machine error isolation ────────────────────────────────
    Context 'Per-machine failure: continues to next machine and writes an error' {

        It 'Should write an error for the failing machine but still return the other machine result' {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName `
                -MockWith {
                    param($ComputerName, $ScriptBlock, $ArgumentList, $Credential)
                    if ($ComputerName -eq $script:FailHost) {
                        throw 'WinRM connection refused'
                    }
                    return $script:mockRemoteRow
                }

            $result = @($script:FailHost, $script:Host1) | Get-ExpiringCertificate -ErrorVariable errs -ErrorAction SilentlyContinue

            $result.ComputerName | Should -Be 'SRV01'
            $errs.Count           | Should -BeGreaterThan 0
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName $script:ModuleName -Times 2 -Exactly
        }
    }

    # ── Context 5: Non-existent StoreName ─────────────────────────────────────
    Context 'Non-existent StoreName: warns and skips, does not throw' {

        It 'Should write a warning for the missing store and still return certs from the other store' {
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\Bogus' } `
                -MockWith { throw [System.Management.Automation.ItemNotFoundException]::new('Cannot find path') }
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\My' } `
                -MockWith { return @($script:certSoon) }

            $result = Get-ExpiringCertificate -StoreName 'Bogus', 'My' -DaysUntilExpiration 30 -WarningVariable warnings -WarningAction SilentlyContinue

            $result.Thumbprint | Should -Be 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            $warnings.Count    | Should -BeGreaterThan 0
        }
    }

    # ── Context 6: IncludeExpired toggle ──────────────────────────────────────
    Context 'IncludeExpired toggles expired certs in/out' {

        It 'Should exclude expired certs by default' {
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\My' } `
                -MockWith { return @($script:certExpired, $script:certSoon) }

            $result = Get-ExpiringCertificate -DaysUntilExpiration 30

            $result.Count      | Should -Be 1
            $result.Thumbprint | Should -Be 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        }

        It 'Should include expired certs with negative DaysRemaining when -IncludeExpired is set' {
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\My' } `
                -MockWith { return @($script:certExpired, $script:certSoon) }

            $result = Get-ExpiringCertificate -DaysUntilExpiration 30 -IncludeExpired

            $result.Count | Should -Be 2
            ($result | Where-Object { $_.Thumbprint -eq 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC' }).DaysRemaining | Should -BeLessThan 0
        }
    }

    # ── Context 7: Empty result ────────────────────────────────────────────────
    Context 'Empty result: no cert under threshold' {

        It 'Should emit nothing and no error when no certificate is under threshold' {
            Mock -CommandName 'Get-ChildItem' -ModuleName $script:ModuleName `
                -ParameterFilter { $Path -eq 'Cert:\LocalMachine\My' } `
                -MockWith { return @($script:certFar) }

            $result = Get-ExpiringCertificate -DaysUntilExpiration 30 -ErrorVariable errs

            $result       | Should -BeNullOrEmpty
            $errs.Count   | Should -Be 0
        }
    }

    # ── Context 8: Parameter validation ───────────────────────────────────────
    Context 'Parameter validation' {

        It 'Should throw for a negative DaysUntilExpiration' {
            { Get-ExpiringCertificate -DaysUntilExpiration -1 } | Should -Throw
        }

        It 'Should throw for an empty StoreName array' {
            { Get-ExpiringCertificate -StoreName @() } | Should -Throw
        }

        It 'Should throw for an empty ComputerName value' {
            { Get-ExpiringCertificate -ComputerName '' } | Should -Throw
        }
    }
}
