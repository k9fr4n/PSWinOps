#Requires -Version 5.1
function Get-CertificateAuthorityHealth {
    <#
        .SYNOPSIS
            Checks Active Directory Certificate Services health on CA servers

        .DESCRIPTION
            Performs comprehensive health checks on AD CS Certificate Authority servers.
            Validates CertSvc service status, CA certificate expiration, CRL publication,
            and CA responsiveness via certutil diagnostics. Returns one typed object per
            server suitable for List view display.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-CertificateAuthorityHealth

            Checks AD CS health on the local computer.

        .EXAMPLE
            Get-CertificateAuthorityHealth -ComputerName 'CA01'

            Checks AD CS health on a single remote CA server.

        .EXAMPLE
            'CA01', 'CA02' | Get-CertificateAuthorityHealth -Credential (Get-Credential)

            Checks AD CS health on multiple remote CA servers via pipeline.

        .OUTPUTS
            PSWinOps.CertificateAuthorityHealth
            Returns one object per server with service status, CA name, CA type,
            certificate expiry, CRL publish status, ping status, and overall health.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: AD-Certificate role (ADCS-Cert-Authority)
            Requires: certutil.exe (included with ADCS or RSAT)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.CertificateAuthorityHealth')]
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
                ServiceStatus       = 'NotFound'
                CAName              = 'Unknown'
                CAType              = 'Unknown'
                CACertExpiry        = 'Unknown'
                CACertDaysRemaining = -1
                CRLPublishOK        = $false
                CAPingOK            = $false
            }

            # 1. Check CertSvc service
            try {
                $certSvc = Get-Service -Name 'CertSvc' -ErrorAction Stop
                $data.ServiceStatus = $certSvc.Status.ToString()
            }
            catch {
                $data.ServiceStatus = 'NotFound'
            }

            # 2. Verify certutil.exe availability
            $certutilAvailable = $null -ne (Get-Command -Name 'certutil.exe' -ErrorAction SilentlyContinue)

            if (-not $certutilAvailable) {
                return $data
            }

            # 3. certutil -CAInfo : CA name, CA type, cert expiry
            try {
                $caInfoOutput = & certutil.exe -CAInfo 2>&1
                if ($LASTEXITCODE -eq 0 -and $null -ne $caInfoOutput) {
                    $caInfoLines = $caInfoOutput | ForEach-Object -Process { $_.ToString() }

                    foreach ($line in $caInfoLines) {
                        if ($line -match '^\s*CA\s+name:\s*(.+)') {
                            $data.CAName = $Matches[1].Trim()
                        }
                        if ($line -match '^\s*CA\s+type:\s*\d+\s*-+\s*(.+)') {
                            $data.CAType = $Matches[1].Trim()
                        }
                        elseif ($line -match '^\s*CA\s+type:\s*(.+)') {
                            $data.CAType = $Matches[1].Trim()
                        }
                    }

                    # Parse NotAfter from CA cert[0]
                    $inCert0 = $false
                    foreach ($line in $caInfoLines) {
                        if ($line -match 'CA\s+cert\[0\]') {
                            $inCert0 = $true
                            continue
                        }
                        if ($inCert0 -and $line -match 'CA\s+cert\[\d+\]') {
                            break
                        }
                        if ($inCert0 -and $line -match 'Not\s*After\s*:\s*(.+)') {
                            $expiryString = $Matches[1].Trim()
                            $data.CACertExpiry = $expiryString
                            try {
                                $expiryDate = [datetime]::Parse($expiryString)
                                $data.CACertDaysRemaining = ($expiryDate - (Get-Date)).Days
                            }
                            catch {
                                $data.CACertDaysRemaining = -1
                            }
                            break
                        }
                    }

                    # Fallback: parse Cert Expires line if NotAfter was not found
                    if ($data.CACertExpiry -eq 'Unknown') {
                        foreach ($line in $caInfoLines) {
                            if ($line -match '(?i)Cert\s+expires?:\s*(.+)') {
                                $expiryString = $Matches[1].Trim()
                                $data.CACertExpiry = $expiryString
                                try {
                                    $expiryDate = [datetime]::Parse($expiryString)
                                    $data.CACertDaysRemaining = ($expiryDate - (Get-Date)).Days
                                }
                                catch {
                                    $data.CACertDaysRemaining = -1
                                }
                                break
                            }
                        }
                    }
                }
            }
            catch {
                Write-Verbose -Message "certutil -CAInfo failed: $_"
            }

            # 4. certutil -CRL : CRL publication check
            try {
                $crlOutput = & certutil.exe -CRL 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $crlText = ($crlOutput | ForEach-Object -Process { $_.ToString() }) -join "`n"
                    if ($crlText -notmatch '(?i)error') {
                        $data.CRLPublishOK = $true
                    }
                }
            }
            catch {
                $data.CRLPublishOK = $false
            }

            # 5. certutil -ping : CA responsiveness
            try {
                $pingOutput = & certutil.exe -ping 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $data.CAPingOK = $true
                }
                else {
                    $pingText = ($pingOutput | ForEach-Object -Process { $_.ToString() }) -join "`n"
                    if ($pingText -match '(?i)successfully') {
                        $data.CAPingOK = $true
                    }
                }
            }
            catch {
                $data.CAPingOK = $false
            }

            return $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $result = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                # Compute OverallHealth
                $serviceNotFound = ($result.ServiceStatus -eq 'NotFound')
                $certutilMissing = (
                    $result.CAName -eq 'Unknown' -and
                    $result.CACertExpiry -eq 'Unknown' -and
                    $result.CACertDaysRemaining -eq -1 -and
                    -not $result.CRLPublishOK -and
                    -not $result.CAPingOK
                )

                if ($serviceNotFound -and $certutilMissing) {
                    $healthStatus = [PSWinOpsHealthStatus]::RoleUnavailable
                }
                elseif ($result.ServiceStatus -ne 'Running' -or
                        ($result.CACertDaysRemaining -ne -1 -and $result.CACertDaysRemaining -le 0) -or
                        -not $result.CAPingOK) {
                    $healthStatus = [PSWinOpsHealthStatus]::Critical
                }
                elseif (($result.CACertDaysRemaining -ne -1 -and $result.CACertDaysRemaining -lt 30) -or
                        -not $result.CRLPublishOK) {
                    $healthStatus = [PSWinOpsHealthStatus]::Degraded
                }
                else {
                    $healthStatus = [PSWinOpsHealthStatus]::Healthy
                }

                [PSCustomObject]@{
                    PSTypeName          = 'PSWinOps.CertificateAuthorityHealth'
                    ComputerName        = $displayName
                    ServiceName         = 'CertSvc'
                    ServiceStatus       = [string]$result.ServiceStatus
                    CAName              = [string]$result.CAName
                    CAType              = [string]$result.CAType
                    CACertExpiry        = [string]$result.CACertExpiry
                    CACertDaysRemaining = [int]$result.CACertDaysRemaining
                    CRLPublishOK        = [bool]$result.CRLPublishOK
                    CAPingOK            = [bool]$result.CAPingOK
                    OverallHealth       = $healthStatus
                    Timestamp           = Get-Date -Format 'o'
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