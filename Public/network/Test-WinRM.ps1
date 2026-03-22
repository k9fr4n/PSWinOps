#Requires -Version 5.1

function Test-WinRM {
    <#
    .SYNOPSIS
        Tests WinRM connectivity and configuration on remote computers.
    .DESCRIPTION
        Performs a comprehensive WinRM connectivity test:
        1. Tests TCP port 5985 (HTTP) and/or 5986 (HTTPS)
        2. Tests WSMan connection via Test-WSMan
        3. Optionally tests Invoke-Command execution

        Returns structured results for each step, making it easy to pinpoint
        where the connection fails.
    .PARAMETER ComputerName
        One or more computer names to test. Accepts pipeline input.
    .PARAMETER Credential
        Optional credential for authentication.
    .PARAMETER UseSSL
        Test HTTPS port 5986 instead of HTTP port 5985.
    .PARAMETER TimeoutMs
        TCP port test timeout in milliseconds. Default: 3000.
    .EXAMPLE
        Test-WinRM -ComputerName 'SRV01'

        Tests WinRM on SRV01 (port 5985 + WSMan).
    .EXAMPLE
        Test-WinRM -ComputerName 'SRV01' -Credential (Get-Credential)

        Full test with credentials (port + WSMan + execution).
    .EXAMPLE
        'SRV01', 'SRV02', 'SRV03' | Test-WinRM

        Pipeline: tests WinRM on 3 servers.
    .EXAMPLE
        Test-WinRM -ComputerName 'SRV01' -UseSSL

        Tests WinRM over HTTPS (port 5986).
    .OUTPUTS
    PSWinOps.WinRMTestResult
    .NOTES
        Author:        Franck SALLET
        Version:       1.0.0
        Last Modified: 2026-03-21
        Requires:      PowerShell 5.1+ / Windows only
        Permissions:   No admin required for testing, target must allow WinRM
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.WinRMTestResult')]
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$UseSSL,

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 30000)]
        [int]$TimeoutMs = 3000
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting WinRM tests"
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $winrmPort = if ($UseSSL) { 5986 } else { 5985 }
                $portOpen = $false
                $wsmanOK = $false
                $execOK = $null
                $wsmanVersion = $null
                $errorMessage = $null

                Write-Verbose "[$($MyInvocation.MyCommand)] Testing '$targetComputer' port $winrmPort"

                # Step 1: TCP port test
                $tcpClient = $null
                try {
                    $tcpClient = New-Object System.Net.Sockets.TcpClient
                    $connectTask = $tcpClient.ConnectAsync($targetComputer, $winrmPort)
                    $portOpen = $connectTask.Wait($TimeoutMs) -and -not $connectTask.IsFaulted
                } catch {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Port $winrmPort closed on '$targetComputer': $_"
                } finally {
                    if ($tcpClient) { $tcpClient.Close(); $tcpClient.Dispose() }
                }

                # Step 2: WSMan test (only if port is open)
                if ($portOpen) {
                    try {
                        $wsmanParams = @{
                            ComputerName = $targetComputer
                            ErrorAction  = 'Stop'
                        }
                        if ($hasCredential) { $wsmanParams['Credential'] = $Credential }

                        $wsmanResult = Test-WSMan @wsmanParams
                        $wsmanOK = $true
                        $wsmanVersion = $wsmanResult.ProductVersion
                    } catch {
                        $errorMessage = "WSMan failed: $($_.Exception.Message)"
                        Write-Verbose "[$($MyInvocation.MyCommand)] WSMan test failed on '$targetComputer': $_"
                    }
                } else {
                    $errorMessage = "Port $winrmPort is not reachable"
                }

                # Step 3: Execution test (always when WSMan succeeds)
                if ($wsmanOK) {
                    try {
                        $invokeParams = @{
                            ComputerName = $targetComputer
                            ScriptBlock  = { $env:COMPUTERNAME }
                            ErrorAction  = 'Stop'
                        }
                        if ($hasCredential) { $invokeParams['Credential'] = $Credential }

                        $execResult = Invoke-Command @invokeParams
                        $execOK = ($null -ne $execResult)
                    } catch {
                        $execOK = $false
                        $errorMessage = "Execution failed: $($_.Exception.Message)"
                        Write-Verbose "[$($MyInvocation.MyCommand)] Execution test failed on '$targetComputer': $_"
                    }
                }

                [PSCustomObject]@{
                    PSTypeName     = 'PSWinOps.WinRMTestResult'
                    ComputerName   = $targetComputer
                    Port           = $winrmPort
                    PortOpen       = $portOpen
                    WSManConnected = $wsmanOK
                    ExecutionOK    = $execOK
                    WSManVersion   = $wsmanVersion
                    Protocol       = if ($UseSSL) { 'HTTPS' } else { 'HTTP' }
                    ErrorMessage   = $errorMessage
                    Timestamp      = Get-Date -Format 'o'
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed WinRM tests"
    }
}
