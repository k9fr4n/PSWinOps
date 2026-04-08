#Requires -Version 5.1
function Test-ProxyConnection {
    <#
        .SYNOPSIS
            Tests connectivity through a proxy server

        .DESCRIPTION
            Sends an HTTP request through the configured or specified proxy to verify
            that proxy connectivity is working. Returns a result object with success status,
            HTTP status code, response time, and proxy details.

            By default, uses the system proxy (WinINET/WinHTTP). Use -ProxyServer to
            test a specific proxy.

        .PARAMETER Uri
            URI to test connectivity against.
            Default: 'http://www.msftconnecttest.com/connecttest.txt'

        .PARAMETER ProxyServer
            Proxy server to test. Format: 'host:port' or 'http://host:port'.
            If not specified, uses the system default proxy.

        .PARAMETER TimeoutSec
            Timeout in seconds for the HTTP request. Default: 10.

        .PARAMETER Credential
            Credentials for proxy authentication.

        .EXAMPLE
            Test-ProxyConnection

            Tests connectivity through the system proxy using the default Microsoft connectivity test URL.

        .EXAMPLE
            Test-ProxyConnection -ProxyServer 'proxy.example.com:8080'

            Tests connectivity through a specific proxy server.

        .EXAMPLE
            Test-ProxyConnection -Uri 'https://www.google.com' -ProxyServer 'proxy.example.com:8080' -TimeoutSec 5

            Tests connectivity to Google through a specific proxy with a 5-second timeout.

        .OUTPUTS
            PSWinOps.ProxyTestResult
            Proxy connectivity test result with latency and status code.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.1
            Last Modified: 2026-04-02
            Requires: PowerShell 5.1+ / Windows only

            The default test URI (msftconnecttest.com) is used by Windows itself for
            internet connectivity detection. It returns the text 'Microsoft Connect Test'
            when successful.

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ProxyTestResult')]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri = 'http://www.msftconnecttest.com/connecttest.txt',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ProxyServer,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSec = 10,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting proxy connection test"
    }

    process {
        # Build Invoke-WebRequest parameters
        $webParams = @{
            Uri             = $Uri
            UseBasicParsing = $true
            TimeoutSec      = $TimeoutSec
            ErrorAction     = 'Stop'
        }

        # Determine proxy to use
        $proxyUsed = $null
        if ($ProxyServer) {
            $proxyUrl = if ($ProxyServer -match '^https?://') { $ProxyServer } else { "http://$ProxyServer" }
            $webParams['Proxy'] = $proxyUrl
            $proxyUsed = $proxyUrl
            Write-Verbose "[$($MyInvocation.MyCommand)] Using explicit proxy: $proxyUrl"

            if ($Credential) {
                $webParams['ProxyCredential'] = $Credential
                Write-Verbose "[$($MyInvocation.MyCommand)] Using proxy credentials (username redacted from verbose output)"
            } else {
                $webParams['ProxyUseDefaultCredentials'] = $true
            }
        } else {
            Write-Verbose "[$($MyInvocation.MyCommand)] Using system default proxy"
            $proxyUsed = 'System Default'
        }

        # Execute the request and measure response time
        $success      = $false
        $statusCode   = $null
        $responseTime = $null
        $errorMessage = $null

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Write-Verbose "[$($MyInvocation.MyCommand)] Testing connection to: $Uri"
            $response     = Invoke-WebRequest @webParams
            $stopwatch.Stop()
            $success      = $true
            $statusCode   = [int]$response.StatusCode
            $responseTime = $stopwatch.ElapsedMilliseconds
        } catch {
            $stopwatch.Stop()
            $responseTime = $stopwatch.ElapsedMilliseconds
            $errorMessage = $_.Exception.Message

            # Try to extract status code from the exception
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            Write-Verbose "[$($MyInvocation.MyCommand)] Connection test failed: $errorMessage"
        }

        # Build output object
        [PSCustomObject]@{
            PSTypeName   = 'PSWinOps.ProxyTestResult'
            ComputerName = $env:COMPUTERNAME
            Uri          = $Uri
            ProxyUsed    = $proxyUsed
            StatusCode   = $statusCode
            Success      = $success
            ResponseTime = $responseTime
            ErrorMessage = $errorMessage
            Timestamp    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed proxy connection test"
    }
}
