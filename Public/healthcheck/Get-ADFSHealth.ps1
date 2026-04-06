#Requires -Version 5.1
function Get-ADFSHealth {
    <#
        .SYNOPSIS
            Retrieves AD FS health status from one or more Windows servers

        .DESCRIPTION
            Collects comprehensive AD FS health information including service status, SSL certificate
            expiry, relying party trusts, enabled endpoints, and server health test results.
            Returns a single typed object per server with an overall health assessment.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-ADFSHealth

            Queries the local server for AD FS health information.

        .EXAMPLE
            Get-ADFSHealth -ComputerName 'ADFS01'

            Queries a single remote AD FS server by name.

        .EXAMPLE
            'ADFS01', 'ADFS02' | Get-ADFSHealth -Credential (Get-Credential)

            Queries multiple remote AD FS servers via the pipeline with alternate credentials.

        .OUTPUTS
            PSWinOps.ADFSHealth
            Returns one object per server with service status, SSL certificate details,
            relying party counts, endpoint counts, health test results, and overall health.

        .NOTES
            Author: Franck SALLET
            Version: 1.1.0
            Last Modified: 2026-03-31
            Requires: PowerShell 5.1+ / Windows only
            Requires: AD FS role installed on target servers
            Requires: Module ADFS

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/adfs/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ADFSHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            $data = @{
                ServiceStatus         = 'Unknown'
                ModuleAvailable       = $false
                FederationServiceName = 'Unknown'
                SslCertExpiry         = 'Unknown'
                SslCertDaysRemaining  = -1
                TotalRelyingParties   = 0
                EnabledRelyingParties = 0
                EnabledEndpoints      = 0
                ServerHealthOK        = $true
                FarmRole              = 'Unknown'
                PrimaryServer         = 'Unknown'
            }

            try {
                $svc = Get-Service -Name 'adfssrv' -ErrorAction Stop
                $data.ServiceStatus = $svc.Status.ToString()
            }
            catch {
                $data.ServiceStatus = 'NotFound'
            }

            $adfsModule = Get-Module -Name 'ADFS' -ListAvailable -ErrorAction SilentlyContinue
            if ($adfsModule) { $data.ModuleAvailable = $true }

            if ($data.ModuleAvailable -and $data.ServiceStatus -eq 'Running') {
                # Detect farm role first — secondary servers cannot run management cmdlets
                try {
                    $adfsProps = Get-AdfsProperties -ErrorAction Stop
                    $data.FederationServiceName = [string]$adfsProps.HostName
                    $data.FarmRole = 'Primary'
                }
                catch {
                    if ($_.Exception.Message -match 'PS0033') {
                        $data.FarmRole = 'Secondary'
                        if ($_.Exception.Message -match 'primary server is presently:\s*(\S+)') {
                            $data.PrimaryServer = $Matches[1].TrimEnd('.')
                        }
                    }
                    else {
                        Write-Warning -Message "Failed to retrieve ADFS properties: $_"
                    }
                }

                # SSL certificate can be queried on both primary and secondary
                try {
                    $sslCerts = Get-AdfsSslCertificate -ErrorAction Stop
                    if ($sslCerts) {
                        $thumbprint = ($sslCerts | Select-Object -First 1).CertificateHash
                        if ($thumbprint) {
                            $cert = Get-Item -Path "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
                            if ($cert -and $cert.NotAfter) {
                                $data.SslCertExpiry = $cert.NotAfter.ToString('yyyy-MM-dd HH:mm:ss')
                                $data.SslCertDaysRemaining = [int]($cert.NotAfter - (Get-Date)).Days
                                # On secondary, try to get federation service name from cert subject
                                if ($data.FarmRole -eq 'Secondary' -and $data.FederationServiceName -eq 'Unknown') {
                                    $subject = $cert.Subject -replace '^CN=', ''
                                    if ($subject) { $data.FederationServiceName = $subject }
                                }
                            }
                        }
                    }
                }
                catch { Write-Warning -Message "Failed to retrieve SSL certificate info: $_" }

                # RP trusts and endpoints: only available on primary servers
                if ($data.FarmRole -ne 'Secondary') {
                    try {
                        $rpTrusts = @(Get-AdfsRelyingPartyTrust -ErrorAction Stop)
                        $data.TotalRelyingParties = $rpTrusts.Count
                        $data.EnabledRelyingParties = @($rpTrusts | Where-Object -FilterScript { $_.Enabled -eq $true }).Count
                    }
                    catch { Write-Warning -Message "Failed to retrieve relying party trusts: $_" }

                    try {
                        $endpoints = @(Get-AdfsEndpoint -ErrorAction Stop)
                        $data.EnabledEndpoints = @($endpoints | Where-Object -FilterScript { $_.Enabled -eq $true }).Count
                    }
                    catch { Write-Warning -Message "Failed to retrieve ADFS endpoints: $_" }
                }

                $testCmd = Get-Command -Name 'Test-AdfsServerHealth' -ErrorAction SilentlyContinue
                if ($testCmd) {
                    try {
                        $healthResults = Test-AdfsServerHealth -ErrorAction Stop
                        if ($healthResults) {
                            $failures = @($healthResults | Where-Object -FilterScript { $_.Result -ne 'Pass' })
                            if ($failures.Count -gt 0) { $data.ServerHealthOK = $false }
                        }
                    }
                    catch {
                        Write-Warning -Message "Failed to run Test-AdfsServerHealth: $_"
                        $data.ServerHealthOK = $false
                    }
                }
            }

            $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $result = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                $isSecondary = $result.FarmRole -eq 'Secondary'

                if (-not $result.ModuleAvailable) {
                    $healthStatus = [PSWinOpsHealthStatus]::RoleUnavailable
                }
                elseif ($result.ServiceStatus -ne 'Running' -or $result.SslCertDaysRemaining -le 0 -or -not $result.ServerHealthOK) {
                    $healthStatus = [PSWinOpsHealthStatus]::Critical
                }
                elseif ($result.SslCertDaysRemaining -lt 30 -or ($result.EnabledRelyingParties -eq 0 -and -not $isSecondary)) {
                    $healthStatus = [PSWinOpsHealthStatus]::Degraded
                }
                else {
                    $healthStatus = [PSWinOpsHealthStatus]::Healthy
                }

                [PSCustomObject]@{
                    PSTypeName            = 'PSWinOps.ADFSHealth'
                    ComputerName          = $displayName
                    ServiceName           = 'adfssrv'
                    ServiceStatus         = [string]$result.ServiceStatus
                    FarmRole              = [string]$result.FarmRole
                    PrimaryServer         = [string]$result.PrimaryServer
                    FederationServiceName = [string]$result.FederationServiceName
                    SslCertExpiry         = [string]$result.SslCertExpiry
                    SslCertDaysRemaining  = [int]$result.SslCertDaysRemaining
                    TotalRelyingParties   = [int]$result.TotalRelyingParties
                    EnabledRelyingParties = [int]$result.EnabledRelyingParties
                    EnabledEndpoints      = [int]$result.EnabledEndpoints
                    ServerHealthOK        = [bool]$result.ServerHealthOK
                    OverallHealth         = $healthStatus
                    Timestamp             = Get-Date -Format 'o'
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}