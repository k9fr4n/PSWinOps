#Requires -Version 5.1

function Test-WinRM {
    <#
        .SYNOPSIS
            Tests WinRM connectivity and configuration on remote computers

        .DESCRIPTION
            Performs a comprehensive WinRM connectivity test on both HTTP (5985) and
            HTTPS (5986) by default:
            1. Tests TCP port reachability
            2. Tests WSMan connection via Test-WSMan
            3. Tests actual command execution via Invoke-Command

            Returns two rows per computer (HTTP + HTTPS), giving a complete picture
            in a single call. Use -Protocol to test only one protocol.

        .PARAMETER ComputerName
            One or more computer names to test. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional credential for authentication.

        .PARAMETER Protocol
            Protocol(s) to test. Default: both HTTP and HTTPS.
            Valid values: HTTP, HTTPS.

        .PARAMETER TimeoutMs
            TCP port test timeout in milliseconds. Default: 3000.

        .EXAMPLE
            Test-WinRM

            Tests WinRM on the local computer over both HTTP (5985) and HTTPS (5986).

        .EXAMPLE
            Test-WinRM -ComputerName 'SRV01'

            Tests WinRM on SRV01 over both HTTP (5985) and HTTPS (5986).

        .EXAMPLE
            Test-WinRM -ComputerName 'SRV01' -Protocol HTTP

            Tests WinRM on SRV01 over HTTP only.

        .EXAMPLE
            Test-WinRM -ComputerName 'SRV01' -Credential (Get-Credential)

            Full test with credentials (both protocols).

        .EXAMPLE
            'SRV01', 'SRV02', 'SRV03' | Test-WinRM

            Pipeline: tests WinRM on 3 servers (both protocols each).

        .OUTPUTS
            PSWinOps.WinRMTestResult

        .NOTES
            Author:        Franck SALLET
            Version:       1.2.0
            Last Modified: 2026-04-02
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   No admin required for testing, target must allow WinRM

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.WinRMTestResult')]
    param (
        [Parameter(Mandatory = $false,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateSet('HTTP', 'HTTPS')]
        [string[]]$Protocol = @('HTTP', 'HTTPS'),

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 30000)]
        [int]$TimeoutMs = 3000
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting WinRM tests (Protocol: $($Protocol -join ', '))"
        $hasCredential = $PSBoundParameters.ContainsKey('Credential')

        $protocolMap = @{
            'HTTP'  = @{ Port = 5985; UseSSL = $false }
            'HTTPS' = @{ Port = 5986; UseSSL = $true }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            foreach ($proto in $Protocol) {
                try {
                    $winrmPort = $protocolMap[$proto].Port
                    $useSSL = $protocolMap[$proto].UseSSL
                    $portOpen = $false
                    $wsmanOK = $false
                    $execOK = $null
                    $wsmanVersion = $null
                    $errorMessage = $null

                    Write-Verbose "[$($MyInvocation.MyCommand)] Testing '$targetComputer' $proto (port $winrmPort)"

                    # Step 1: TCP port test
                    $tcpClient = $null
                    try {
                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $connectTask = $tcpClient.ConnectAsync($targetComputer, $winrmPort)
                        $portOpen = $connectTask.Wait($TimeoutMs) -and -not $connectTask.IsFaulted
                    } catch {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Port $winrmPort closed on '$targetComputer': $_"
                    } finally {
                        if ($tcpClient) {
                            $tcpClient.Close(); $tcpClient.Dispose()
                        }
                    }

                    # Step 2: WSMan test (only if port is open)
                    if ($portOpen) {
                        try {
                            $wsmanParams = @{
                                ComputerName = $targetComputer
                                ErrorAction  = 'Stop'
                            }
                            if ($useSSL) {
                                $wsmanParams['UseSsl'] = $true
                            }
                            if ($hasCredential) {
                                $wsmanParams['Credential'] = $Credential
                            }

                            $wsmanResult = Test-WSMan @wsmanParams
                            $wsmanOK = $true
                            $wsmanVersion = $wsmanResult.ProductVersion
                        } catch {
                            $errorMessage = "WSMan failed: $($_.Exception.Message)"
                            Write-Verbose "[$($MyInvocation.MyCommand)] WSMan test failed on '$targetComputer' ($proto): $_"
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
                            if ($useSSL) {
                                $invokeParams['UseSSL'] = $true
                            }
                            if ($hasCredential) {
                                $invokeParams['Credential'] = $Credential
                            }

                            $execResult = Invoke-Command @invokeParams
                            $execOK = ($null -ne $execResult)
                        } catch {
                            $execOK = $false
                            $errorMessage = "Execution failed: $($_.Exception.Message)"
                            Write-Verbose "[$($MyInvocation.MyCommand)] Execution test failed on '$targetComputer' ($proto): $_"
                        }
                    }

                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.WinRMTestResult'
                        ComputerName   = $targetComputer
                        Port           = $winrmPort
                        Protocol       = $proto
                        PortOpen       = $portOpen
                        WSManConnected = $wsmanOK
                        ExecutionOK    = $execOK
                        WSManVersion   = $wsmanVersion
                        ErrorMessage   = $errorMessage
                        Timestamp      = Get-Date -Format 'o'
                    }
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer' ($proto): $_"
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed WinRM tests"
    }
}
