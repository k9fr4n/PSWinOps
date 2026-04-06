#Requires -Version 5.1

function Get-SSLCertificate {
    <#
        .SYNOPSIS
            Retrieves SSL/TLS certificate information from remote endpoints

        .DESCRIPTION
            Connects to one or more remote hosts using System.Net.Security.SslStream
            and retrieves the server certificate. Returns structured objects with
            subject, issuer, validity dates, days remaining, SAN entries, and
            thumbprint.

            Ideal for proactive certificate expiry monitoring.

        .PARAMETER Uri
            One or more hostnames, IP addresses, or URIs to check.
            Accepts pipeline input. If a full URI is provided (https://host),
            the hostname and port are extracted automatically.

        .PARAMETER Port
            TCP port to connect to. Default: 443.

        .PARAMETER TimeoutMs
            Connection timeout in milliseconds. Default: 5000. Valid range: 1000-30000.

        .PARAMETER AcceptUntrusted
            Accept self-signed or untrusted certificates for inspection.
            By default, certificates are validated normally and untrusted ones are rejected.
            Use this switch to inspect certificates regardless of their trust status.

        .EXAMPLE
            Get-SSLCertificate -Uri 'google.com'

            Retrieves the SSL certificate from google.com:443.

        .EXAMPLE
            Get-SSLCertificate -Uri 'mail.corp.local', 'intranet.corp.local' -Port 443

            Checks certificates on two internal hosts.

        .EXAMPLE
            Get-SSLCertificate -Uri 'myserver' -Port 8443

            Checks a certificate on a non-standard HTTPS port.

        .EXAMPLE
            Get-Content servers.txt | Get-SSLCertificate | Where-Object { $_.DaysRemaining -lt 30 }

            Pipeline: find certificates expiring within 30 days.

        .OUTPUTS
            PSWinOps.SSLCertificate

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-21
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/dotnet/api/system.net.security.sslstream
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.SSLCertificate')]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Host', 'ComputerName', 'CN', 'Url')]
        [string[]]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port = 443,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1000, 30000)]
        [int]$TimeoutMs = 5000,

        [Parameter(Mandatory = $false)]
        [switch]$AcceptUntrusted
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting SSL certificate retrieval"
    }

    process {
        foreach ($target in $Uri) {
            try {
                # Extract hostname and optional port from URI
                $targetHost = $target
                $targetPort = $Port

                if ($target -match '^https?://') {
                    $parsed = [System.Uri]::new($target)
                    $targetHost = $parsed.Host
                    if ($parsed.Port -gt 0 -and $parsed.Port -ne 443) {
                        $targetPort = $parsed.Port
                    }
                } elseif ($target -match '^([^:]+):(\d+)$') {
                    $targetHost = $Matches[1]
                    $targetPort = [int]$Matches[2]
                }

                Write-Verbose "[$($MyInvocation.MyCommand)] Connecting to ${targetHost}:${targetPort}"

                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connectTask = $tcpClient.ConnectAsync($targetHost, $targetPort)
                if (-not $connectTask.Wait($TimeoutMs)) {
                    $tcpClient.Dispose()
                    Write-Error "[$($MyInvocation.MyCommand)] Connection to '${targetHost}:${targetPort}' timed out"
                    continue
                }

                $sslStream = $null
                try {
                    $callback = if ($AcceptUntrusted) {
                        [System.Net.Security.RemoteCertificateValidationCallback] { $true }
                    } else {
                        $null
                    }

                    $sslStream = New-Object System.Net.Security.SslStream(
                        $tcpClient.GetStream(), $false, $callback
                    )
                    $sslStream.AuthenticateAsClient($targetHost)

                    $cert = $sslStream.RemoteCertificate
                    $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)

                    # Extract SAN (Subject Alternative Names)
                    $san = @($cert2.Extensions |
                            Where-Object { $_.Oid.FriendlyName -eq 'Subject Alternative Name' } |
                            ForEach-Object { $_.Format($false) }) -join ', '

                    $now = Get-Date
                    $daysRemaining = [int][math]::Floor(($cert2.NotAfter - $now).TotalDays)

                    [PSCustomObject]@{
                        PSTypeName         = 'PSWinOps.SSLCertificate'
                        ComputerName       = $targetHost
                        Port               = $targetPort
                        Subject            = $cert2.Subject
                        Issuer             = $cert2.Issuer
                        NotBefore          = $cert2.NotBefore
                        NotAfter           = $cert2.NotAfter
                        DaysRemaining      = $daysRemaining
                        IsExpired          = ($now -gt $cert2.NotAfter)
                        Thumbprint         = $cert2.Thumbprint
                        SerialNumber       = $cert2.SerialNumber
                        SignatureAlgorithm = $cert2.SignatureAlgorithm.FriendlyName
                        KeyLength          = $cert2.PublicKey.Key.KeySize
                        SAN                = $san
                        Protocol           = $sslStream.SslProtocol
                        Timestamp          = Get-Date -Format 'o'
                    }

                    $cert2.Dispose()
                } finally {
                    if ($sslStream) {
                        $sslStream.Dispose()
                    }
                    $tcpClient.Dispose()
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '${target}': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed SSL certificate retrieval"
    }
}
