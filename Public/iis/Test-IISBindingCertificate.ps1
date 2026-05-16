#Requires -Version 5.1
function Test-IISBindingCertificate {
    <#
        .SYNOPSIS
            Validates each IIS HTTPS binding certificate and emits a per-binding verdict (expiration, chain, hostname, key, store).

        .DESCRIPTION
            Inspects every https binding on one or more IIS hosts and evaluates the
            associated X509 certificate across six independent checks: expiration
            against configurable Warning/Critical thresholds, X509Chain.Build()
            validity, hostname/SAN match against the binding host header, private
            key availability, signature/key-algorithm strength, and alignment
            between the binding's declared CertStoreName and the store where the
            certificate is actually found. Each check contributes to a per-binding
            OverallStatus (Pass/Warning/Critical/Fail) and a Findings array
            describing every non-Pass condition. Complements Get-IISCertificateBinding
            (inventory) with an actionable verdict that IISAdministration does not
            expose. Falls back gracefully WebAdministration -> IISAdministration
            -> appcmd, supports multi-host execution via Invoke-RemoteOrLocal,
            and pipes cleanly from Get-IISCertificateBinding / Get-IISHealth.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER SiteName
            Filter to one or more IIS site names. Supports -like wildcards.
            Defaults to all https-bound sites.

        .PARAMETER BindingInformation
            Filter to specific ip:port:hostheader bindings. Supports -like wildcards.
            Enables piping rows from Get-IISCertificateBinding for targeted re-tests.

        .PARAMETER HostHeader
            Filter on the host header part of the binding. Supports -like wildcards.

        .PARAMETER Thumbprint
            Filter to specific certificate thumbprints (40 hex characters, normalised
            upper-case internally).

        .PARAMETER WarningDays
            DaysUntilExpiration threshold below which ExpirationStatus becomes Warning.
            Must be greater than CriticalDays. Default: 30.

        .PARAMETER CriticalDays
            DaysUntilExpiration threshold below which ExpirationStatus becomes Critical.
            Default: 7.

        .PARAMETER MinKeySize
            Minimum acceptable RSA/DSA key size in bits. ECDSA keys are evaluated
            against a separate built-in baseline (>=256). Anything below MinKeySize
            flags AlgorithmStrength=Weak. Default: 2048.

        .PARAMETER SkipChainValidation
            Skip X509Chain.Build() -- useful on hosts without internet access to
            CRL/OCSP endpoints; ChainValid will be $null and ChainStatus empty.

        .PARAMETER AllowSelfSigned
            Do not downgrade OverallStatus when the chain ends in an untrusted root
            if the certificate is self-signed (Issuer equals Subject).

        .PARAMETER IncludeRevocationCheck
            Enable X509RevocationMode.Online during chain build (default is NoCheck
            for speed/offline-friendliness).

        .EXAMPLE
            Test-IISBindingCertificate

            Audit every HTTPS binding on the local host with default thresholds.

        .EXAMPLE
            'WEB01','WEB02','WEB03' | Test-IISBindingCertificate -Credential (Get-Credential)

            Audit a web farm using alternate credentials.

        .EXAMPLE
            Test-IISBindingCertificate -ComputerName WEB01 | Where-Object OverallStatus -ne 'Pass'

            Surface only actionable verdicts.

        .EXAMPLE
            Test-IISBindingCertificate -ComputerName WEB01 -WarningDays 60 -CriticalDays 14

            Tighten the expiration window for a renewal sweep.

        .EXAMPLE
            Test-IISBindingCertificate -ComputerName WEB01 -SkipChainValidation

            Skip chain build on an offline / air-gapped host.

        .EXAMPLE
            Get-IISCertificateBinding -ComputerName WEB01 -SiteName www | Test-IISBindingCertificate

            Re-test a specific binding piped from the inventory cmdlet.

        .EXAMPLE
            Test-IISBindingCertificate -ComputerName WEB01 -IncludeRevocationCheck

            Enable online revocation (CRL/OCSP) for a compliance run.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISCertificateBindingTestResult')

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-16
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role
            Optional: Module WebAdministration or IISAdministration (falls back to appcmd)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509chain
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISCertificateBindingTestResult')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string[]]$SiteName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string[]]$BindingInformation,

        [Parameter(Mandatory = $false)]
        [string[]]$HostHeader,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Fa-f0-9]{40}$')]
        [string[]]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$WarningDays = 30,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3650)]
        [int]$CriticalDays = 7,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1024, 2048, 3072, 4096)]
        [int]$MinKeySize = 2048,

        [Parameter(Mandatory = $false)]
        [switch]$SkipChainValidation,

        [Parameter(Mandatory = $false)]
        [switch]$AllowSelfSigned,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeRevocationCheck
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        if ($PSBoundParameters.ContainsKey('WarningDays') -and $PSBoundParameters.ContainsKey('CriticalDays')) {
            if ($WarningDays -le $CriticalDays) {
                throw [System.ArgumentException]::new(
                    "WarningDays ($WarningDays) must be greater than CriticalDays ($CriticalDays)."
                )
            }
        }

        $scriptBlock = {
            param(
                [string[]]$FilterSiteName,
                [string[]]$FilterBindingInformation,
                [string[]]$FilterHostHeader,
                [string[]]$FilterThumbprint,
                [int]$PWarningDays,
                [int]$PCriticalDays,
                [int]$PMinKeySize,
                [bool]$PSkipChainValidation,
                [bool]$PAllowSelfSigned,
                [bool]$PIncludeRevocationCheck
            )

            $results = [System.Collections.Generic.List[hashtable]]::new()
            $tsNow   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $now     = [datetime]::UtcNow

            # ── 1. Verify W3SVC / IIS installed ───────────────────────────────
            try {
                $null = Get-Service -Name 'W3SVC' -ErrorAction Stop
            }
            catch {
                $results.Add(@{
                    ComputerName           = $env:COMPUTERNAME
                    SiteName               = $null; BindingInformation = $null; Protocol = $null
                    Port                   = $null; HostHeader = $null; SslFlags = $null
                    Thumbprint             = $null; Subject = $null; SubjectAlternativeName = @()
                    Issuer                 = $null; NotBefore = $null; NotAfter = $null
                    DaysUntilExpiration    = $null; ExpirationStatus = $null
                    ChainValid             = $null; ChainStatus = @()
                    HostnameMatch          = $null; HasPrivateKey = $null
                    SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                    AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                    OverallStatus          = 'Fail'; Findings = @()
                    Status                 = 'IISNotInstalled'
                    ErrorMessage           = "W3SVC service not found: $($_.Exception.Message)"
                    Timestamp              = $tsNow
                })
                return $results
            }

            # ── 2. Detect IIS module chain ─────────────────────────────────────
            $iisModule = $null
            if (Get-Module -Name 'WebAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'WebAdministration'
            }
            elseif (Get-Module -Name 'IISAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'IISAdministration'
            }

            # ── 3. Collect raw binding descriptors (https only) ────────────────
            $bindingRows = [System.Collections.Generic.List[hashtable]]::new()

            if ($iisModule -eq 'WebAdministration') {
                try {
                    Import-Module -Name 'WebAdministration' -ErrorAction Stop
                    $allSites = @(Get-Website -ErrorAction Stop)

                    if ($FilterSiteName) {
                        $allSites = @($allSites | Where-Object {
                            $sn = $_.Name
                            $null -ne ($FilterSiteName | Where-Object { $sn -like $_ })
                        })
                    }

                    foreach ($site in $allSites) {
                        $httpsBindings = @(
                            Get-WebBinding -Name $site.Name -Protocol 'https' -ErrorAction SilentlyContinue
                        )
                        foreach ($b in $httpsBindings) {
                            $rawTp = $b.certificateHash
                            $tpStr = if ($rawTp) {
                                ($rawTp -split '(?<=\G.{2})' | Where-Object { $_ -ne '' }) -join ''
                            }
                            else { $null }
                            $bindingRows.Add(@{
                                SiteNameVal    = $site.Name
                                BindingInfoVal = $b.bindingInformation
                                SslFlagsVal    = [int]$b.sslFlags
                                StoreNameVal   = $b.certificateStoreName
                                ThumbprintVal  = if ($tpStr) { $tpStr.ToUpperInvariant() } else { $null }
                            })
                        }
                    }
                }
                catch {
                    $results.Add(@{
                        ComputerName           = $env:COMPUTERNAME
                        SiteName               = $null; BindingInformation = $null; Protocol = $null
                        Port                   = $null; HostHeader = $null; SslFlags = $null
                        Thumbprint             = $null; Subject = $null; SubjectAlternativeName = @()
                        Issuer                 = $null; NotBefore = $null; NotAfter = $null
                        DaysUntilExpiration    = $null; ExpirationStatus = $null
                        ChainValid             = $null; ChainStatus = @()
                        HostnameMatch          = $null; HasPrivateKey = $null
                        SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                        AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                        OverallStatus          = 'Fail'; Findings = @()
                        Status                 = 'Failed'
                        ErrorMessage           = "WebAdministration error: $($_.Exception.Message)"
                        Timestamp              = $tsNow
                    })
                    return $results
                }
            }
            elseif ($iisModule -eq 'IISAdministration') {
                try {
                    Import-Module -Name 'IISAdministration' -ErrorAction Stop
                    $allSites = @(Get-IISSite -ErrorAction Stop)

                    if ($FilterSiteName) {
                        $allSites = @($allSites | Where-Object {
                            $sn = $_.Name
                            $null -ne ($FilterSiteName | Where-Object { $sn -like $_ })
                        })
                    }

                    foreach ($site in $allSites) {
                        foreach ($b in ($site.Bindings | Where-Object { $_.Protocol -eq 'https' })) {
                            $rawHash = $b.CertificateHash
                            $tpStr = if ($rawHash -and $rawHash.Count -gt 0) {
                                ($rawHash | ForEach-Object { $_.ToString('X2') }) -join ''
                            }
                            else { $null }
                            $sslFlagsInt = try { [int]$b.SslFlags } catch { 0 }
                            $bindingRows.Add(@{
                                SiteNameVal    = $site.Name
                                BindingInfoVal = $b.BindingInformation
                                SslFlagsVal    = $sslFlagsInt
                                StoreNameVal   = $b.CertificateStoreName
                                ThumbprintVal  = if ($tpStr) { $tpStr.ToUpperInvariant() } else { $null }
                            })
                        }
                    }
                }
                catch {
                    $results.Add(@{
                        ComputerName           = $env:COMPUTERNAME
                        SiteName               = $null; BindingInformation = $null; Protocol = $null
                        Port                   = $null; HostHeader = $null; SslFlags = $null
                        Thumbprint             = $null; Subject = $null; SubjectAlternativeName = @()
                        Issuer                 = $null; NotBefore = $null; NotAfter = $null
                        DaysUntilExpiration    = $null; ExpirationStatus = $null
                        ChainValid             = $null; ChainStatus = @()
                        HostnameMatch          = $null; HasPrivateKey = $null
                        SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                        AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                        OverallStatus          = 'Fail'; Findings = @()
                        Status                 = 'Failed'
                        ErrorMessage           = "IISAdministration error: $($_.Exception.Message)"
                        Timestamp              = $tsNow
                    })
                    return $results
                }
            }
            else {
                # appcmd fallback
                $appcmdExe = Join-Path -Path $env:windir -ChildPath 'system32\inetsrv\appcmd.exe'
                if (-not (Test-Path -LiteralPath $appcmdExe -PathType Leaf)) {
                    $results.Add(@{
                        ComputerName           = $env:COMPUTERNAME
                        SiteName               = $null; BindingInformation = $null; Protocol = $null
                        Port                   = $null; HostHeader = $null; SslFlags = $null
                        Thumbprint             = $null; Subject = $null; SubjectAlternativeName = @()
                        Issuer                 = $null; NotBefore = $null; NotAfter = $null
                        DaysUntilExpiration    = $null; ExpirationStatus = $null
                        ChainValid             = $null; ChainStatus = @()
                        HostnameMatch          = $null; HasPrivateKey = $null
                        SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                        AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                        OverallStatus          = 'Fail'; Findings = @()
                        Status                 = 'IISNotInstalled'
                        ErrorMessage           = 'Neither WebAdministration nor IISAdministration module is available, and appcmd.exe was not found.'
                        Timestamp              = $tsNow
                    })
                    return $results
                }

                try {
                    [xml]$sitesXml = & $appcmdExe list sites /config:* /xml 2>$null
                    foreach ($siteNode in $sitesXml.appcmd.SITE) {
                        $siteName = $siteNode.'SITE.NAME'
                        if ($FilterSiteName) {
                            $snMatch = $FilterSiteName | Where-Object { $siteName -like $_ }
                            if (-not $snMatch) { continue }
                        }
                        foreach ($bNode in $siteNode.site.bindings.binding) {
                            if ($bNode.protocol -ne 'https') { continue }
                            $bindingRows.Add(@{
                                SiteNameVal    = $siteName
                                BindingInfoVal = $bNode.bindingInformation
                                SslFlagsVal    = 0
                                StoreNameVal   = 'My'
                                ThumbprintVal  = $null
                            })
                        }
                    }
                    # Enrich thumbprints via netsh sslcert
                    $netshOut   = & netsh http show sslcert 2>$null
                    $netshBlock = ($netshOut -join "`n")
                    $netshRx    = [regex]'IP:port\s+:\s+(\S+)[\s\S]*?Certificate Hash\s+:\s+([0-9a-fA-F]+)'
                    foreach ($nm in $netshRx.Matches($netshBlock)) {
                        $epPort = ($nm.Groups[1].Value -split ':')[-1]
                        $tpVal  = $nm.Groups[2].Value.ToUpperInvariant()
                        foreach ($row in $bindingRows) {
                            $rParts = $row.BindingInfoVal -split ':'
                            $rPort  = if ($rParts.Count -ge 2) { $rParts[-2] } else { '' }
                            if ($rPort -eq $epPort -and -not $row.ThumbprintVal) {
                                $row.ThumbprintVal = $tpVal
                            }
                        }
                    }
                }
                catch {
                    $results.Add(@{
                        ComputerName           = $env:COMPUTERNAME
                        SiteName               = $null; BindingInformation = $null; Protocol = $null
                        Port                   = $null; HostHeader = $null; SslFlags = $null
                        Thumbprint             = $null; Subject = $null; SubjectAlternativeName = @()
                        Issuer                 = $null; NotBefore = $null; NotAfter = $null
                        DaysUntilExpiration    = $null; ExpirationStatus = $null
                        ChainValid             = $null; ChainStatus = @()
                        HostnameMatch          = $null; HasPrivateKey = $null
                        SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                        AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                        OverallStatus          = 'Fail'; Findings = @()
                        Status                 = 'Failed'
                        ErrorMessage           = "appcmd fallback error: $($_.Exception.Message)"
                        Timestamp              = $tsNow
                    })
                    return $results
                }
            }

            # ── 4. No bindings found ───────────────────────────────────────────
            if ($bindingRows.Count -eq 0) {
                $results.Add(@{
                    ComputerName           = $env:COMPUTERNAME
                    SiteName               = $null; BindingInformation = $null; Protocol = 'https'
                    Port                   = $null; HostHeader = $null; SslFlags = $null
                    Thumbprint             = $null; Subject = $null; SubjectAlternativeName = @()
                    Issuer                 = $null; NotBefore = $null; NotAfter = $null
                    DaysUntilExpiration    = $null; ExpirationStatus = $null
                    ChainValid             = $null; ChainStatus = @()
                    HostnameMatch          = $null; HasPrivateKey = $null
                    SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                    AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                    OverallStatus          = 'Fail'; Findings = @()
                    Status                 = 'BindingNotFound'
                    ErrorMessage           = 'No https bindings found on this host.'
                    Timestamp              = $tsNow
                })
                return $results
            }

            # ── 5. Test each binding ──────────────────────────────────────────
            foreach ($br in $bindingRows) {
                $bindInfo = $br.BindingInfoVal

                # Parse BindingInformation: ip:port:hostheader (handles IPv6)
                $bParts     = $bindInfo -split ':'
                $bHostHeader = ''
                $bPort       = 443
                if ($bParts.Count -ge 2) {
                    $bHostHeader = $bParts[-1]
                    $bPort       = [int]$bParts[-2]
                }

                # Normalise SslFlags
                $sslFlagsStr = switch ($br.SslFlagsVal) {
                    0 { 'None' }
                    1 { 'Sni' }
                    2 { 'CentralCertStore' }
                    3 { 'Sni+CentralCertStore' }
                    default { $br.SslFlagsVal.ToString() }
                }

                # Apply filters
                if ($FilterBindingInformation) {
                    $bim = $bindInfo
                    $bimMatch = $FilterBindingInformation | Where-Object { $bim -like $_ }
                    if (-not $bimMatch) { continue }
                }
                if ($FilterHostHeader) {
                    $bhhLocal = $bHostHeader
                    $bhhMatch = $FilterHostHeader | Where-Object { $bhhLocal -like $_ }
                    if (-not $bhhMatch) { continue }
                }

                $thumbprintUp = if ($br.ThumbprintVal) { $br.ThumbprintVal.ToUpperInvariant() } else { '' }
                if ($FilterThumbprint) {
                    $tpMatch = $FilterThumbprint | Where-Object { $thumbprintUp -ieq $_ }
                    if (-not $tpMatch) { continue }
                }

                $certStoreName = if ($br.StoreNameVal) { $br.StoreNameVal } else { 'My' }

                # ── Find certificate in LocalMachine stores ───────────────────
                $cert           = $null
                $actualStore    = $null
                $storeAligned   = $false

                if ($thumbprintUp) {
                    foreach ($storeName in @('My', 'WebHosting', 'CA', 'Root')) {
                        try {
                            $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
                                $storeName,
                                [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
                            )
                            $store.Open(
                                [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly
                            )
                            $found = $store.Certificates |
                                Where-Object { $_.Thumbprint -ieq $thumbprintUp } |
                                Select-Object -First 1
                            $store.Close()
                            if ($found) {
                                $cert         = $found
                                $actualStore  = "LocalMachine\$storeName"
                                $storeAligned = ($storeName -ieq $certStoreName)
                                break
                            }
                        }
                        catch {
                            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Could not search store '$storeName': $_"
                        }
                    }
                }

                if (-not $cert) {
                    $results.Add(@{
                        ComputerName           = $env:COMPUTERNAME
                        SiteName               = $br.SiteNameVal
                        BindingInformation     = $bindInfo
                        Protocol               = 'https'
                        Port                   = $bPort
                        HostHeader             = $bHostHeader
                        SslFlags               = $sslFlagsStr
                        Thumbprint             = $thumbprintUp
                        Subject                = $null; SubjectAlternativeName = @()
                        Issuer                 = $null; NotBefore = $null; NotAfter = $null
                        DaysUntilExpiration    = $null; ExpirationStatus = $null
                        ChainValid             = $null; ChainStatus = @()
                        HostnameMatch          = $null; HasPrivateKey = $null
                        SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                        AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                        OverallStatus          = 'Fail'; Findings = @()
                        Status                 = 'CertNotFound'
                        ErrorMessage           = "Certificate with thumbprint '$thumbprintUp' not found in any LocalMachine store."
                        Timestamp              = $tsNow
                    })
                    continue
                }

                $findings = [System.Collections.Generic.List[string]]::new()

                # ── Check 1 : Expiration ──────────────────────────────────────
                $notBefore = $cert.NotBefore
                $notAfter  = $cert.NotAfter
                $daysLeft  = [int][math]::Floor(($notAfter.ToUniversalTime() - $now).TotalDays)

                $expirationStatus = if ($notAfter.ToUniversalTime() -le $now) {
                    [void]$findings.Add("Certificate expired on $($notAfter.ToString('yyyy-MM-dd HH:mm:ss'))")
                    'Expired'
                }
                elseif ($notBefore.ToUniversalTime() -gt $now) {
                    [void]$findings.Add("Certificate not yet valid (NotBefore: $($notBefore.ToString('yyyy-MM-dd HH:mm:ss')))")
                    'NotYetValid'
                }
                elseif ($daysLeft -le $PCriticalDays) {
                    [void]$findings.Add("Certificate expires in $daysLeft day(s) (Critical threshold: $PCriticalDays)")
                    'Critical'
                }
                elseif ($daysLeft -le $PWarningDays) {
                    [void]$findings.Add("Certificate expires in $daysLeft day(s) (Warning threshold: $PWarningDays)")
                    'Warning'
                }
                else {
                    'OK'
                }

                # ── Check 2 : Chain ───────────────────────────────────────────
                $chainValid  = $null
                $chainStatus = @()

                if (-not $PSkipChainValidation) {
                    try {
                        $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
                        $chain.ChainPolicy.RevocationMode = if ($PIncludeRevocationCheck) {
                            [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
                        }
                        else {
                            [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
                        }
                        $chainValid = $chain.Build($cert)

                        if (-not $chainValid) {
                            $chainStatus = @(
                                $chain.ChainStatus | ForEach-Object { $_.Status.ToString() }
                            )
                            $isSelfSigned = ($cert.Subject -eq $cert.Issuer)
                            $onlyUntrustedRoot = (
                                $chainStatus.Count -gt 0 -and
                                ($chainStatus | Where-Object { $_ -ne 'UntrustedRoot' }).Count -eq 0
                            )
                            if ($PAllowSelfSigned -and $isSelfSigned -and $onlyUntrustedRoot) {
                                $chainValid  = $true
                                $chainStatus = @()
                            }
                            else {
                                [void]$findings.Add("Chain build failed: $($chainStatus -join ', ')")
                            }
                        }
                        $chain.Dispose()
                    }
                    catch {
                        $chainValid  = $false
                        $chainStatus = @("Exception: $($_.Exception.Message)")
                        [void]$findings.Add("Chain validation threw an exception: $($_.Exception.Message)")
                    }
                }

                # ── Check 3 : Hostname match ──────────────────────────────────
                $hostnameMatch = $true
                if (-not [string]::IsNullOrEmpty($bHostHeader)) {
                    $nameToTest = $bHostHeader.ToLowerInvariant()

                    $certNames = [System.Collections.Generic.List[string]]::new()
                    $cnRegex   = [regex]::Match($cert.Subject, '(?i)CN=([^,]+)')
                    if ($cnRegex.Success) {
                        [void]$certNames.Add($cnRegex.Groups[1].Value.Trim())
                    }

                    $sanExtension = $cert.Extensions |
                        Where-Object { $_.Oid.FriendlyName -eq 'Subject Alternative Name' }
                    if ($sanExtension) {
                        $sanExtension.Format($false) -split ', ' |
                            Where-Object { $_ -like 'DNS Name=*' } |
                            ForEach-Object { [void]$certNames.Add(($_ -split '=', 2)[1]) }
                    }

                    $hostnameMatch = $false
                    foreach ($certName in $certNames) {
                        $p = $certName.ToLowerInvariant()
                        if ($p.StartsWith('*.')) {
                            $suffix = $p.Substring(1)
                            if ($nameToTest.EndsWith($suffix)) {
                                $label = $nameToTest.Substring(0, $nameToTest.Length - $suffix.Length)
                                if ($label -notmatch '\.') {
                                    $hostnameMatch = $true
                                    break
                                }
                            }
                        }
                        elseif ($nameToTest -eq $p) {
                            $hostnameMatch = $true
                            break
                        }
                    }

                    if (-not $hostnameMatch) {
                        [void]$findings.Add(
                            "Hostname '$bHostHeader' does not match any certificate CN or SAN ($($certNames -join ', '))"
                        )
                    }
                }

                # ── Check 4 : Private key ─────────────────────────────────────
                $hasPrivateKey = $cert.HasPrivateKey
                if (-not $hasPrivateKey) {
                    [void]$findings.Add('Certificate does not have an associated private key in this store')
                }

                # ── Check 5 : Algorithm strength ──────────────────────────────
                $sigAlgFriendly = $cert.SignatureAlgorithm.FriendlyName
                $keyAlgOid      = $cert.PublicKey.Oid.FriendlyName

                $keyAlg = switch ($keyAlgOid) {
                    'RSA' { 'RSA' }
                    'ECC' { 'ECDSA' }
                    'DSA' { 'DSA' }
                    default { $keyAlgOid }
                }

                $keySize = 0
                try {
                    if ($keyAlg -eq 'ECDSA') {
                        $ecKey = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPublicKey($cert)
                        if ($ecKey) { $keySize = $ecKey.KeySize }
                    }
                    else {
                        $keySize = $cert.PublicKey.Key.KeySize
                    }
                }
                catch { $keySize = 0 }

                $sigHash = if ($sigAlgFriendly -imatch 'sha512') { 'SHA512' }
                elseif ($sigAlgFriendly -imatch 'sha384') { 'SHA384' }
                elseif ($sigAlgFriendly -imatch 'sha256') { 'SHA256' }
                elseif ($sigAlgFriendly -imatch 'sha1') { 'SHA1' }
                elseif ($sigAlgFriendly -imatch 'md5') { 'MD5' }
                else { 'Unknown' }

                $goodHash = $sigHash -in @('SHA256', 'SHA384', 'SHA512')

                $algStrength = if ($sigHash -in @('MD5', 'SHA1', 'Unknown') -or $keySize -eq 0) {
                    'Weak'
                }
                elseif ($keyAlg -eq 'ECDSA') {
                    if ($keySize -ge 384 -and $goodHash) { 'Strong' }
                    elseif ($keySize -ge 256 -and $goodHash) { 'Acceptable' }
                    else { 'Weak' }
                }
                elseif ($keyAlg -in @('RSA', 'DSA')) {
                    if ($keySize -lt $PMinKeySize) { 'Weak' }
                    elseif ($keySize -ge 3072 -and $goodHash) { 'Strong' }
                    elseif ($keySize -ge 2048 -and $goodHash) { 'Acceptable' }
                    else { 'Weak' }
                }
                else { 'Weak' }

                if ($algStrength -eq 'Weak') {
                    [void]$findings.Add(
                        "Algorithm strength Weak: $keyAlg $keySize-bit, signature $sigAlgFriendly"
                    )
                }
                elseif ($algStrength -eq 'Acceptable') {
                    [void]$findings.Add(
                        "Algorithm strength Acceptable: $keyAlg $keySize-bit (consider upgrading to 3072+)"
                    )
                }

                # ── Check 6 : Store alignment ─────────────────────────────────
                if (-not $storeAligned) {
                    [void]$findings.Add(
                        "Store misalignment: binding declares '$certStoreName' but certificate found in '$actualStore'"
                    )
                }

                # ── Collect SANs for output ───────────────────────────────────
                $outSANs     = @()
                $sanExtOut   = $cert.Extensions |
                    Where-Object { $_.Oid.FriendlyName -eq 'Subject Alternative Name' }
                if ($sanExtOut) {
                    $outSANs = @(
                        $sanExtOut.Format($false) -split ', ' |
                            Where-Object { $_ -like 'DNS Name=*' } |
                            ForEach-Object { ($_ -split '=', 2)[1] }
                    )
                }

                # ── Compute OverallStatus ─────────────────────────────────────
                $isCriticalExp = $expirationStatus -in @('Critical', 'Expired', 'NotYetValid')
                $chainFail     = ($null -ne $chainValid) -and (-not $chainValid)

                $overallStatus = if (
                    $isCriticalExp -or
                    (-not $hostnameMatch) -or
                    (-not $hasPrivateKey) -or
                    $chainFail -or
                    ($algStrength -eq 'Weak') -or
                    (-not $storeAligned)
                ) {
                    'Critical'
                }
                elseif ($expirationStatus -eq 'Warning' -or $algStrength -eq 'Acceptable') {
                    'Warning'
                }
                else {
                    'Pass'
                }

                $results.Add(@{
                    ComputerName           = $env:COMPUTERNAME
                    SiteName               = $br.SiteNameVal
                    BindingInformation     = $bindInfo
                    Protocol               = 'https'
                    Port                   = $bPort
                    HostHeader             = $bHostHeader
                    SslFlags               = $sslFlagsStr
                    Thumbprint             = $thumbprintUp
                    Subject                = $cert.Subject
                    SubjectAlternativeName = $outSANs
                    Issuer                 = $cert.Issuer
                    NotBefore              = $notBefore
                    NotAfter               = $notAfter
                    DaysUntilExpiration    = $daysLeft
                    ExpirationStatus       = $expirationStatus
                    ChainValid             = $chainValid
                    ChainStatus            = $chainStatus
                    HostnameMatch          = $hostnameMatch
                    HasPrivateKey          = $hasPrivateKey
                    SignatureAlgorithm     = $sigAlgFriendly
                    KeyAlgorithm           = $keyAlg
                    KeySize                = $keySize
                    AlgorithmStrength      = $algStrength
                    CertificateStore       = $actualStore
                    StoreAligned           = $storeAligned
                    OverallStatus          = $overallStatus
                    Findings               = @($findings)
                    Status                 = 'Tested'
                    ErrorMessage           = $null
                    Timestamp              = $tsNow
                })
            }

            if ($results.Count -eq 0) {
                $results.Add(@{
                    ComputerName           = $env:COMPUTERNAME
                    SiteName               = $null; BindingInformation = $null; Protocol = 'https'
                    Port                   = $null; HostHeader = $null; SslFlags = $null
                    Thumbprint             = $null; Subject = $null; SubjectAlternativeName = @()
                    Issuer                 = $null; NotBefore = $null; NotAfter = $null
                    DaysUntilExpiration    = $null; ExpirationStatus = $null
                    ChainValid             = $null; ChainStatus = @()
                    HostnameMatch          = $null; HasPrivateKey = $null
                    SignatureAlgorithm     = $null; KeyAlgorithm = $null; KeySize = $null
                    AlgorithmStrength      = $null; CertificateStore = $null; StoreAligned = $null
                    OverallStatus          = 'Fail'; Findings = @()
                    Status                 = 'BindingNotFound'
                    ErrorMessage           = 'No https bindings matched the supplied filters on this host.'
                    Timestamp              = $tsNow
                })
            }

            return $results
        }
    }

    process {
        foreach ($cn in $ComputerName) {
            $tpNorm = if ($Thumbprint) {
                @($Thumbprint | ForEach-Object { $_.ToUpperInvariant() })
            }
            else { $null }

            $invokeParams = @{
                ComputerName = $cn
                ScriptBlock  = $scriptBlock
                ArgumentList = @(
                    $SiteName,
                    $BindingInformation,
                    $HostHeader,
                    $tpNorm,
                    $WarningDays,
                    $CriticalDays,
                    $MinKeySize,
                    $SkipChainValidation.IsPresent,
                    $AllowSelfSigned.IsPresent,
                    $IncludeRevocationCheck.IsPresent
                )
            }
            if ($Credential) {
                $invokeParams['Credential'] = $Credential
            }

            try {
                $rawResults = Invoke-RemoteOrLocal @invokeParams
                foreach ($r in $rawResults) {
                    [PSCustomObject]([ordered]@{
                        PSTypeName             = 'PSWinOps.IISCertificateBindingTestResult'
                        ComputerName           = $r.ComputerName
                        SiteName               = $r.SiteName
                        BindingInformation     = $r.BindingInformation
                        Protocol               = $r.Protocol
                        Port                   = $r.Port
                        HostHeader             = $r.HostHeader
                        SslFlags               = $r.SslFlags
                        Thumbprint             = $r.Thumbprint
                        Subject                = $r.Subject
                        SubjectAlternativeName = $r.SubjectAlternativeName
                        Issuer                 = $r.Issuer
                        NotBefore              = $r.NotBefore
                        NotAfter               = $r.NotAfter
                        DaysUntilExpiration    = $r.DaysUntilExpiration
                        ExpirationStatus       = $r.ExpirationStatus
                        ChainValid             = $r.ChainValid
                        ChainStatus            = $r.ChainStatus
                        HostnameMatch          = $r.HostnameMatch
                        HasPrivateKey          = $r.HasPrivateKey
                        SignatureAlgorithm     = $r.SignatureAlgorithm
                        KeyAlgorithm           = $r.KeyAlgorithm
                        KeySize                = $r.KeySize
                        AlgorithmStrength      = $r.AlgorithmStrength
                        CertificateStore       = $r.CertificateStore
                        StoreAligned           = $r.StoreAligned
                        OverallStatus          = $r.OverallStatus
                        Findings               = $r.Findings
                        Status                 = $r.Status
                        ErrorMessage           = $r.ErrorMessage
                        Timestamp              = $r.Timestamp
                    })
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '$cn': $_"
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
