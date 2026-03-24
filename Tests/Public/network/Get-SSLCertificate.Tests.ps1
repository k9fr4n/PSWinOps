BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:ModuleName = 'PSWinOps'
}

Describe 'Get-SSLCertificate' {

    Context 'Parameter validation' {

        It 'Should require Uri parameter' {
            { Get-SSLCertificate -Uri $null } | Should -Throw
        }

        It 'Should reject Port 0' {
            { Get-SSLCertificate -Uri 'test' -Port 0 } | Should -Throw
        }

        It 'Should reject TimeoutMs below 1000' {
            { Get-SSLCertificate -Uri 'test' -TimeoutMs 500 } | Should -Throw
        }

        It 'Should have expected parameters' {
            $cmd = Get-Command -Name 'Get-SSLCertificate'
            $cmd.Parameters.Keys | Should -Contain 'Uri'
            $cmd.Parameters.Keys | Should -Contain 'Port'
            $cmd.Parameters.Keys | Should -Contain 'TimeoutMs'
            $cmd.Parameters.Keys | Should -Contain 'RejectUntrusted'
        }

        It 'Should have RejectUntrusted as switch parameter' {
            $cmd = Get-Command -Name 'Get-SSLCertificate'
            $cmd.Parameters['RejectUntrusted'].ParameterType | Should -Be ([switch])
        }

        It 'Should accept pipeline input for Uri' {
            $param = (Get-Command Get-SSLCertificate).Parameters['Uri']
            $attr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $attr.ValueFromPipeline | Should -Be $true
        }
    }

    Context 'URI parsing' {

        BeforeEach {
            # Mock TcpClient to fail fast so we test URI parsing only
            Mock -ModuleName $script:ModuleName -CommandName 'New-Object' -MockWith {
                $mock = [PSCustomObject]@{}
                $mock | Add-Member -MemberType ScriptMethod -Name 'ConnectAsync' -Value {
                    param($h, $p)
                    throw "Connection refused to ${h}:${p}"
                }
                $mock | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value { }
                return $mock
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }
        }

        It 'Should write error on connection failure' {
            Get-SSLCertificate -Uri 'unreachable.invalid' -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Integration' -Tag 'Integration' {

        It 'Should retrieve certificate from a public HTTPS site' -Skip:(-not ($env:OS -eq 'Windows_NT')) {
            $result = Get-SSLCertificate -Uri 'google.com' -TimeoutMs 10000
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'PSWinOps.SSLCertificate'
            $result.Host | Should -Be 'google.com'
            $result.Port | Should -Be 443
            $result.Subject | Should -Not -BeNullOrEmpty
            $result.Issuer | Should -Not -BeNullOrEmpty
            $result.DaysRemaining | Should -BeOfType [int]
            $result.Thumbprint | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'Should parse https:// URI format' -Skip:(-not ($env:OS -eq 'Windows_NT')) {
            $result = Get-SSLCertificate -Uri 'https://google.com' -TimeoutMs 10000
            $result | Should -Not -BeNullOrEmpty
            $result.Host | Should -Be 'google.com'
        }
    }
}
