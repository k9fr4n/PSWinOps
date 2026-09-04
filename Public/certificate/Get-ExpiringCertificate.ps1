#Requires -Version 5.1
function Get-ExpiringCertificate {
    <#
    .SYNOPSIS
        Find local-store certificates expiring within a threshold of days

    .DESCRIPTION
        Scans one or more local machine certificate stores (My, WebHosting, CA, ...) on one or
        more computers and returns the certificates whose NotAfter falls within the given number
        of days, sorted by expiry date ascending. Optionally includes already-expired
        certificates. Complements Get-SSLCertificate (network endpoints) and
        Get-IISCertificateBinding (IIS bindings) on the local-store side.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote computers.
        Not used for local queries.

    .PARAMETER DaysUntilExpiration
        Threshold in days. Certificates whose NotAfter is on or before
        (Get-Date).AddDays($DaysUntilExpiration) are returned. Defaults to 30.

    .PARAMETER StoreName
        One or more certificate store names to scan under LocalMachine (for example My,
        WebHosting, CA, Root). Defaults to 'My'. A store that does not exist on the target
        machine triggers a warning and is skipped; other stores and machines still process.

    .PARAMETER IncludeExpired
        Also include certificates whose NotAfter has already passed. DaysRemaining is negative
        for those certificates.

    .EXAMPLE
        Get-ExpiringCertificate -DaysUntilExpiration 30

        Local usage example.

    .EXAMPLE
        Get-ExpiringCertificate -ComputerName 'SRV01' -StoreName 'My','WebHosting' -DaysUntilExpiration 60

        Remote single-machine example.

    .EXAMPLE
        'SRV01','SRV02' | Get-ExpiringCertificate -IncludeExpired

        Pipeline usage example.

    .OUTPUTS
        PSWinOps.ExpiringCertificate
        One object per matching certificate, sorted by NotAfter ascending per machine.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-04
        Requires: PowerShell 5.1+ / Windows only

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509store
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.ExpiringCertificate')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$DaysUntilExpiration = 30,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$StoreName = @('My'),

        [Parameter(Mandatory = $false)]
        [switch]$IncludeExpired
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            param(
                [string[]]$StoreNames,
                [int]$Threshold,
                [bool]$IncludeExpiredCerts
            )

            $results = [System.Collections.Generic.List[hashtable]]::new()
            $now = Get-Date
            $tsNow = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            foreach ($sn in $StoreNames) {
                try {
                    $certs = @(Get-ChildItem -Path "Cert:\LocalMachine\$sn" -ErrorAction Stop)
                }
                catch {
                    Write-Warning -Message "Certificate store '$sn' not found on '$env:COMPUTERNAME': $($_.Exception.Message)"
                    continue
                }

                foreach ($cert in $certs) {
                    $isExpired = $cert.NotAfter -lt $now
                    if ($isExpired -and -not $IncludeExpiredCerts) {
                        continue
                    }
                    if ($cert.NotAfter -gt $now.AddDays($Threshold)) {
                        continue
                    }

                    $daysRemaining = [int][math]::Floor(($cert.NotAfter - $now).TotalDays)
                    $eku = @($cert.EnhancedKeyUsageList | ForEach-Object { $_.FriendlyName })

                    $results.Add(@{
                        ComputerName     = $env:COMPUTERNAME
                        StoreName        = $sn
                        Subject          = $cert.Subject
                        Issuer           = $cert.Issuer
                        Thumbprint       = $cert.Thumbprint
                        NotAfter         = $cert.NotAfter
                        DaysRemaining    = $daysRemaining
                        HasPrivateKey    = $cert.HasPrivateKey
                        EnhancedKeyUsage = $eku
                        Timestamp        = $tsNow
                    })
                }
            }

            return @($results | Sort-Object -Property { $_.NotAfter })
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                $invokeParams = @{
                    ComputerName = $targetComputer
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @(
                        $StoreName,
                        $DaysUntilExpiration,
                        $IncludeExpired.IsPresent
                    )
                }
                if ($Credential) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawResults = Invoke-RemoteOrLocal @invokeParams
                foreach ($r in $rawResults) {
                    [PSCustomObject]([ordered]@{
                        PSTypeName       = 'PSWinOps.ExpiringCertificate'
                        ComputerName     = $r.ComputerName
                        StoreName        = $r.StoreName
                        Subject          = $r.Subject
                        Issuer           = $r.Issuer
                        Thumbprint       = $r.Thumbprint
                        NotAfter         = $r.NotAfter
                        DaysRemaining    = $r.DaysRemaining
                        HasPrivateKey    = $r.HasPrivateKey
                        EnhancedKeyUsage = $r.EnhancedKeyUsage
                        Timestamp        = $r.Timestamp
                    })
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
