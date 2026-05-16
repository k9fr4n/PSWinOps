#Requires -Version 5.1
function Get-IISCertificateBinding {
    <#
        .SYNOPSIS
            Inventories every IIS HTTPS binding joined to the X509 certificate it actually presents.

        .DESCRIPTION
            Enumerates all https bindings on one or more IIS hosts and joins each binding
            to the X509 certificate it points at, surfacing site, ip:port:hostheader,
            SNI/CCS flags, thumbprint, subject, SAN, issuer, validity window, days until
            expiration, certificate store of record and presence of the private key.
            Provides the read-only typed counterpart of Set-IISBindingCertificate that
            IISAdministration does not expose in a single cmdlet. Falls back gracefully
            from WebAdministration to IISAdministration to appcmd, and pipes cleanly into
            Set-IISBindingCertificate for rotation workflows.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER SiteName
            Filter to one or more site names. Supports -like wildcards. Defaults to all
            https-bound sites.

        .PARAMETER Thumbprint
            Filter to one or more certificate thumbprints (40 hex characters, uppercased
            internally). Useful to track a specific certificate across multiple bindings.

        .PARAMETER HostHeader
            Filter on the host header part of the binding. Supports -like wildcards.

        .PARAMETER Port
            Filter to specific TCP ports. Defaults to all https ports (typically 443).

        .PARAMETER ExpiringInDays
            Returns only certificates with DaysUntilExpiration less than or equal to this
            value. Includes already-expired certificates (negative DaysUntilExpiration).

        .PARAMETER IncludeExpired
            When used alone, returns only rows where Expired is $true. Implied when
            -ExpiringInDays is used.

        .EXAMPLE
            Get-IISCertificateBinding

            Inventories all https bindings and their certificates on the local machine.

        .EXAMPLE
            'WEB01','WEB02','WEB03' | Get-IISCertificateBinding -Credential (Get-Credential)

            Audits certificate bindings across a web farm using alternate credentials.

        .EXAMPLE
            Get-IISCertificateBinding -ComputerName WEB01 -ExpiringInDays 30

            Returns bindings whose certificate expires within the next 30 days.

        .EXAMPLE
            Get-IISCertificateBinding -SiteName 'www*' -HostHeader '*.contoso.com'

            Filters by site name wildcard and host header wildcard.

        .EXAMPLE
            Get-IISCertificateBinding -ComputerName WEB01 -ExpiringInDays 15 | Set-IISBindingCertificate -Thumbprint $newTp -Confirm:$false

            Pipes expiring bindings directly into the rotation cmdlet.

        .EXAMPLE
            Get-IISCertificateBinding | Where-Object Status -eq 'CertNotFound'

            Surfaces orphan bindings whose certificate has been removed from the store.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISCertificateBinding')

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
            https://learn.microsoft.com/en-us/iis/manage/configuring-security/how-to-set-up-ssl-on-iis
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISCertificateBinding')]
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
        [ValidatePattern('^[A-Fa-f0-9]{40}$')]
        [string[]]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [string[]]$HostHeader,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int[]]$Port,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3650)]
        [int]$ExpiringInDays,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeExpired
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            param(
                [string[]]$FilterSiteName,
                [string[]]$FilterThumbprint,
                [string[]]$FilterHostHeader,
                [int[]]$FilterPort,
                [object]$FilterExpiringInDays,
                [bool]$FilterIncludeExpired
            )

            $results = [System.Collections.Generic.List[hashtable]]::new()

            $tsNow = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            # ── 1. Verify W3SVC / IIS installed ───────────────────────────────
            try {
                $null = Get-Service -Name 'W3SVC' -ErrorAction Stop
            }
            catch {
                $results.Add(@{
                    ComputerName            = $env:COMPUTERNAME
                    SiteName                = $null; SiteId = $null; SiteState = $null
                    BindingInformation      = $null; IPAddress = $null; Port = $null; HostHeader = $null
                    Protocol                = $null; SslFlags = $null; SniEnabled = $null; CentralCertStore = $null
                    Thumbprint              = $null; CertStoreLocation = $null; CertStoreName = $null
                    Subject                 = $null; SubjectCN = $null; Issuer = $null; SerialNumber = $null
                    NotBefore               = $null; NotAfter = $null; DaysUntilExpiration = $null; Expired = $null
                    SubjectAlternativeNames = @()
                    SignatureAlgorithm      = $null; KeyAlgorithm = $null; KeySize = $null
                    HasPrivateKey           = $null; FriendlyName = $null
                    Status                  = 'IISNotInstalled'
                    ErrorMessage            = "W3SVC service not found: $($_.Exception.Message)"
                    Timestamp               = $tsNow
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

            # ── 3. Collect raw binding descriptors ────────────────────────────
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
                        $httpsBindings = @(Get-WebBinding -Name $site.Name -Protocol 'https' -ErrorAction SilentlyContinue)
                        if ($httpsBindings.Count -eq 0) {
                            if ($FilterSiteName) {
                                $bindingRows.Add(@{
                                    SiteNameVal    = $site.Name
                                    SiteIdVal      = [int]$site.Id
                                    SiteStateVal   = $site.State
                                    BindingInfoVal = ''
                                    SslFlagsVal    = 0
                                    ThumbprintVal  = $null
                                    StoreNameVal   = $null
                                    StatusVal      = 'BindingNotFound'
                                    ErrorVal       = "No https bindings on site '$($site.Name)'."
                                })
                            }
                            continue
                        }
                        foreach ($b in $httpsBindings) {
                            $sslHash  = $b.certificateHash
                            $sslStore = if ($b.certificateStoreName) { $b.certificateStoreName } else { 'My' }
                            $bindingRows.Add(@{
                                SiteNameVal    = $site.Name
                                SiteIdVal      = [int]$site.Id
                                SiteStateVal   = $site.State
                                BindingInfoVal = $b.bindingInformation
                                SslFlagsVal    = [int]$b.sslFlags
                                ThumbprintVal  = $sslHash
                                StoreNameVal   = $sslStore
                                StatusVal      = if ($sslHash) { 'Resolved' } else { 'CertNotFound' }
                                ErrorVal       = if (-not $sslHash) { 'Binding has no certificateHash (unbound https listener).' } else { $null }
                            })
                        }
                    }
                }
                catch {
                    $results.Add(@{
                        ComputerName            = $env:COMPUTERNAME
                        SiteName                = $null; SiteId = $null; SiteState = $null
                        BindingInformation      = $null; IPAddress = $null; Port = $null; HostHeader = $null
                        Protocol                = $null; SslFlags = $null; SniEnabled = $null; CentralCertStore = $null
                        Thumbprint              = $null; CertStoreLocation = $null; CertStoreName = $null
                        Subject                 = $null; SubjectCN = $null; Issuer = $null; SerialNumber = $null
                        NotBefore               = $null; NotAfter = $null; DaysUntilExpiration = $null; Expired = $null
                        SubjectAlternativeNames = @()
                        SignatureAlgorithm      = $null; KeyAlgorithm = $null; KeySize = $null
                        HasPrivateKey           = $null; FriendlyName = $null
                        Status                  = 'Failed'
                        ErrorMessage            = "WebAdministration error: $($_.Exception.Message)"
                        Timestamp               = $tsNow
                    })
                    return $results
                }
            }
            elseif ($iisModule -eq 'IISAdministration') {
                try {
                    Import-Module -Name 'IISAdministration' -ErrorAction Stop
                    $mgr = [Microsoft.Web.Administration.ServerManager]::OpenRemote('localhost')
                    $allSites = @($mgr.Sites)
                    if ($FilterSiteName) {
                        $allSites = @($allSites | Where-Object {
                            $sn = $_.Name
                            $null -ne ($FilterSiteName | Where-Object { $sn -like $_ })
                        })
                    }
                    foreach ($site in $allSites) {
                        $httpsBindings = @($site.Bindings | Where-Object { $_.Protocol -eq 'https' })
                        if ($httpsBindings.Count -eq 0) {
                            if ($FilterSiteName) {
                                $bindingRows.Add(@{
                                    SiteNameVal    = $site.Name
                                    SiteIdVal      = [long]$site.Id
                                    SiteStateVal   = $site.State.ToString()
                                    BindingInfoVal = ''
                                    SslFlagsVal    = 0
                                    ThumbprintVal  = $null
                                    StoreNameVal   = $null
                                    StatusVal      = 'BindingNotFound'
                                    ErrorVal       = "No https bindings on site '$($site.Name)'."
                                })
                            }
                            continue
                        }
                        foreach ($b in $httpsBindings) {
                            $rawHash  = [System.BitConverter]::ToString($b.CertificateHash) -replace '-', ''
                            $sslStore = if ($b.CertificateStoreName) { $b.CertificateStoreName } else { 'My' }
                            $bindingRows.Add(@{
                                SiteNameVal    = $site.Name
                                SiteIdVal      = [long]$site.Id
                                SiteStateVal   = $site.State.ToString()
                                BindingInfoVal = $b.BindingInformation
                                SslFlagsVal    = [int]$b.SslFlags
                                ThumbprintVal  = $rawHash
                                StoreNameVal   = $sslStore
                                StatusVal      = if ($rawHash) { 'Resolved' } else { 'CertNotFound' }
                                ErrorVal       = if (-not $rawHash) { 'Binding has no certificate hash (unbound https listener).' } else { $null }
                            })
                        }
                    }
                    $mgr.Dispose()
                }
                catch {
                    $results.Add(@{
                        ComputerName            = $env:COMPUTERNAME
                        SiteName                = $null; SiteId = $null; SiteState = $null
                        BindingInformation      = $null; IPAddress = $null; Port = $null; HostHeader = $null
                        Protocol                = $null; SslFlags = $null; SniEnabled = $null; CentralCertStore = $null
                        Thumbprint              = $null; CertStoreLocation = $null; CertStoreName = $null
                        Subject                 = $null; SubjectCN = $null; Issuer = $null; SerialNumber = $null
                        NotBefore               = $null; NotAfter = $null; DaysUntilExpiration = $null; Expired = $null
                        SubjectAlternativeNames = @()
                        SignatureAlgorithm      = $null; KeyAlgorithm = $null; KeySize = $null
                        HasPrivateKey           = $null; FriendlyName = $null
                        Status                  = 'Failed'
                        ErrorMessage            = "IISAdministration error: $($_.Exception.Message)"
                        Timestamp               = $tsNow
                    })
                    return $results
                }
            }
            else {
                # appcmd fallback
                $appcmdExe = Join-Path -Path $env:windir -ChildPath 'system32\inetsrv\appcmd.exe'
                if (-not (Test-Path -LiteralPath $appcmdExe -PathType Leaf)) {
                    $results.Add(@{
                        ComputerName            = $env:COMPUTERNAME
                        SiteName                = $null; SiteId = $null; SiteState = $null
                        BindingInformation      = $null; IPAddress = $null; Port = $null; HostHeader = $null
                        Protocol                = $null; SslFlags = $null; SniEnabled = $null; CentralCertStore = $null
                        Thumbprint              = $null; CertStoreLocation = $null; CertStoreName = $null
                        Subject                 = $null; SubjectCN = $null; Issuer = $null; SerialNumber = $null
                        NotBefore               = $null; NotAfter = $null; DaysUntilExpiration = $null; Expired = $null
                        SubjectAlternativeNames = @()
                        SignatureAlgorithm      = $null; KeyAlgorithm = $null; KeySize = $null
                        HasPrivateKey           = $null; FriendlyName = $null
                        Status                  = 'IISNotInstalled'
                        ErrorMessage            = 'Neither WebAdministration nor IISAdministration module is available, and appcmd.exe was not found.'
                        Timestamp               = $tsNow
                    })
                    return $results
                }
                try {
                    [xml]$sitesXml = & $appcmdExe list sites /config:* /xml 2>$null
                    foreach ($siteNode in $sitesXml.appcmd.SITE) {
                        $siteName  = $siteNode.'SITE.NAME'
                        $siteId    = [int]$siteNode.site.id
                        $siteState = $siteNode.'SITE.STATE'

                        if ($FilterSiteName) {
                            $matched = $FilterSiteName | Where-Object { $siteName -like $_ }
                            if (-not $matched) { continue }
                        }

                        $httpsNodes = @($siteNode.site.bindings.binding | Where-Object { $_.protocol -eq 'https' })
                        if ($httpsNodes.Count -eq 0) {
                            if ($FilterSiteName) {
                                $bindingRows.Add(@{
                                    SiteNameVal    = $siteName
                                    SiteIdVal      = $siteId
                                    SiteStateVal   = $siteState
                                    BindingInfoVal = ''
                                    SslFlagsVal    = 0
                                    ThumbprintVal  = $null
                                    StoreNameVal   = $null
                                    StatusVal      = 'BindingNotFound'
                                    ErrorVal       = "No https bindings on site '$siteName'."
                                })
                            }
                            continue
                        }
                        foreach ($bn in $httpsNodes) {
                            $sslHash  = $bn.certificateHash
                            $sslStore = if ($bn.certificateStoreName) { $bn.certificateStoreName } else { 'My' }
                            $sslFlags = if ($bn.sslFlags) { [int]$bn.sslFlags } else { 0 }
                            $bindingRows.Add(@{
                                SiteNameVal    = $siteName
                                SiteIdVal      = $siteId
                                SiteStateVal   = $siteState
                                BindingInfoVal = $bn.bindingInformation
                                SslFlagsVal    = $sslFlags
                                ThumbprintVal  = $sslHash
                                StoreNameVal   = $sslStore
                                StatusVal      = if ($sslHash) { 'Resolved' } else { 'CertNotFound' }
                                ErrorVal       = if (-not $sslHash) { 'Binding has no certificateHash (unbound https listener).' } else { $null }
                            })
                        }
                    }
                }
                catch {
                    $results.Add(@{
                        ComputerName            = $env:COMPUTERNAME
                        SiteName                = $null; SiteId = $null; SiteState = $null
                        BindingInformation      = $null; IPAddress = $null; Port = $null; HostHeader = $null
                        Protocol                = $null; SslFlags = $null; SniEnabled = $null; CentralCertStore = $null
                        Thumbprint              = $null; CertStoreLocation = $null; CertStoreName = $null
                        Subject                 = $null; SubjectCN = $null; Issuer = $null; SerialNumber = $null
                        NotBefore               = $null; NotAfter = $null; DaysUntilExpiration = $null; Expired = $null
                        SubjectAlternativeNames = @()
                        SignatureAlgorithm      = $null; KeyAlgorithm = $null; KeySize = $null
                        HasPrivateKey           = $null; FriendlyName = $null
                        Status                  = 'Failed'
                        ErrorMessage            = "appcmd fallback error: $($_.Exception.Message)"
                        Timestamp               = $tsNow
                    })
                    return $results
                }
            }

            # ── 4. No bindings at all ──────────────────────────────────────────
            if ($bindingRows.Count -eq 0) {
                $results.Add(@{
                    ComputerName            = $env:COMPUTERNAME
                    SiteName                = $null; SiteId = $null; SiteState = $null
                    BindingInformation      = $null; IPAddress = $null; Port = $null; HostHeader = $null
                    Protocol                = $null; SslFlags = $null; SniEnabled = $null; CentralCertStore = $null
                    Thumbprint              = $null; CertStoreLocation = $null; CertStoreName = $null
                    Subject                 = $null; SubjectCN = $null; Issuer = $null; SerialNumber = $null
                    NotBefore               = $null; NotAfter = $null; DaysUntilExpiration = $null; Expired = $null
                    SubjectAlternativeNames = @()
                    SignatureAlgorithm      = $null; KeyAlgorithm = $null; KeySize = $null
                    HasPrivateKey           = $null; FriendlyName = $null
                    Status                  = 'BindingNotFound'
                    ErrorMessage            = 'No https bindings found on this host.'
                    Timestamp               = $tsNow
                })
                return $results
            }

            # ── 5. Build full rows: parse binding + resolve cert + filter ──────
            foreach ($br in $bindingRows) {
                # Parse BindingInformation: ip:port:hostheader
                # Last colon-segment = hostheader, second-to-last = port,
                # everything before second-to-last joined = IP (safe for IPv6).
                $bindInfo  = $br.BindingInfoVal
                $bParts    = $bindInfo -split ':'
                $hostHeader = ''
                $portVal    = 0
                $ipAddress  = '*'
                if ($bParts.Count -ge 2) {
                    $hostHeader = $bParts[-1]
                    $portVal    = [int]$bParts[-2]
                    $ipRaw      = ($bParts[0..($bParts.Count - 3)]) -join ':'
                    $ipAddress  = if ([string]::IsNullOrEmpty($ipRaw)) { '*' } else { $ipRaw }
                }

                # HostHeader filter
                if ($FilterHostHeader) {
                    $hh      = $hostHeader
                    $matched = $FilterHostHeader | Where-Object { $hh -like $_ }
                    if (-not $matched) { continue }
                }

                # Port filter
                if ($FilterPort -and ($portVal -notin $FilterPort)) { continue }

                # Thumbprint filter (pre-resolution, fast path)
                if ($FilterThumbprint) {
                    $tpRaw   = if ($br.ThumbprintVal) { $br.ThumbprintVal.ToUpper() } else { '' }
                    $matched = $FilterThumbprint | Where-Object { $tpRaw -eq $_.ToUpper() }
                    if (-not $matched) { continue }
                }

                # Resolve X509 certificate
                $tp           = if ($br.ThumbprintVal) { $br.ThumbprintVal.ToUpper() } else { $null }
                $storeName    = $br.StoreNameVal
                $statusVal    = $br.StatusVal
                $errorVal     = $br.ErrorVal

                $certSubject   = $null; $certSubjectCN = $null
                $certIssuer    = $null; $certSerial    = $null
                $certNotBefore = $null; $certNotAfter  = $null
                $certDays      = $null; $certExpired   = $null
                $certSAN       = @()
                $certSigAlg    = $null; $certKeyAlg    = $null
                $certKeySize   = $null; $certHasPK     = $null
                $certFriendly  = $null

                if ($statusVal -eq 'Resolved' -and $tp -and $storeName) {
                    $storePath = "Cert:\LocalMachine\$storeName"
                    $cert      = $null
                    try {
                        $cert = Get-ChildItem -LiteralPath $storePath -ErrorAction Stop |
                            Where-Object { $_.Thumbprint -eq $tp } |
                            Select-Object -First 1
                    }
                    catch {
                        Write-Verbose -Message "[Get-IISCertificateBinding] Could not open store '$storePath': $($_.Exception.Message)"
                    }

                    if ($null -eq $cert) {
                        $statusVal = 'CertNotFound'
                        $errorVal  = "Certificate with thumbprint '$tp' not found in '$storePath'."
                    }
                    else {
                        $now           = Get-Date
                        $certDays      = [int][math]::Floor(($cert.NotAfter - $now).TotalDays)
                        $certExpired   = ($cert.NotAfter -lt $now)
                        $certSubject   = $cert.Subject
                        $certIssuer    = $cert.Issuer
                        $certSerial    = $cert.SerialNumber.ToUpper()
                        $certNotBefore = $cert.NotBefore
                        $certNotAfter  = $cert.NotAfter
                        $certHasPK     = $cert.HasPrivateKey
                        $certFriendly  = $cert.FriendlyName
                        $certSigAlg    = $cert.SignatureAlgorithm.FriendlyName

                        # SubjectCN extraction
                        $cnMatch = [regex]::Match($cert.Subject, '(?:^|,\s*)CN=([^,]+)')
                        if ($cnMatch.Success) {
                            $certSubjectCN = $cnMatch.Groups[1].Value.Trim()
                        }

                        # KeyAlgorithm and KeySize
                        try {
                            $certKeyAlg = $cert.PublicKey.Oid.FriendlyName
                            $rsaKey     = $cert.GetRSAPublicKey()
                            if ($null -ne $rsaKey) {
                                $certKeySize = $rsaKey.KeySize
                            }
                            else {
                                $ecKey = $cert.GetECDsaPublicKey()
                                if ($null -ne $ecKey) {
                                    $certKeySize = $ecKey.KeySize
                                }
                            }
                        }
                        catch {
                            Write-Verbose -Message "[Get-IISCertificateBinding] Key size resolution failed for '$tp': $($_.Exception.Message)"
                        }

                        # SAN (OID 2.5.29.17)
                        $sanExt = $cert.Extensions |
                            Where-Object { $_.Oid.Value -eq '2.5.29.17' } |
                            Select-Object -First 1
                        if ($null -ne $sanExt) {
                            $sanFormatted = $sanExt.Format($false)
                            if (-not [string]::IsNullOrWhiteSpace($sanFormatted)) {
                                $certSAN = @($sanFormatted -split ',\s*' |
                                    ForEach-Object { $_ -replace '^(DNS Name|IP Address)=', '' } |
                                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                            }
                        }
                    }
                }

                # ExpiringInDays / IncludeExpired filters
                if ($null -ne $FilterExpiringInDays) {
                    if ($null -eq $certDays) { continue }
                    if ($certDays -gt $FilterExpiringInDays) { continue }
                }
                elseif ($FilterIncludeExpired) {
                    if ($certExpired -ne $true) { continue }
                }

                $results.Add(@{
                    ComputerName            = $env:COMPUTERNAME
                    SiteName                = $br.SiteNameVal
                    SiteId                  = $br.SiteIdVal
                    SiteState               = $br.SiteStateVal
                    BindingInformation      = $bindInfo
                    IPAddress               = $ipAddress
                    Port                    = $portVal
                    HostHeader              = $hostHeader
                    Protocol                = 'https'
                    SslFlags                = $br.SslFlagsVal
                    SniEnabled              = (($br.SslFlagsVal -band 1) -eq 1)
                    CentralCertStore        = (($br.SslFlagsVal -band 2) -eq 2)
                    Thumbprint              = $tp
                    CertStoreLocation       = if ($storeName) { "Cert:\LocalMachine\$storeName" } else { $null }
                    CertStoreName           = $storeName
                    Subject                 = $certSubject
                    SubjectCN               = $certSubjectCN
                    Issuer                  = $certIssuer
                    SerialNumber            = $certSerial
                    NotBefore               = $certNotBefore
                    NotAfter                = $certNotAfter
                    DaysUntilExpiration     = $certDays
                    Expired                 = $certExpired
                    SubjectAlternativeNames = $certSAN
                    SignatureAlgorithm      = $certSigAlg
                    KeyAlgorithm            = $certKeyAlg
                    KeySize                 = $certKeySize
                    HasPrivateKey           = $certHasPK
                    FriendlyName            = $certFriendly
                    Status                  = $statusVal
                    ErrorMessage            = $errorVal
                    Timestamp               = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                })
            }

            # ── 6. No rows survived filters ────────────────────────────────────
            if ($results.Count -eq 0) {
                $results.Add(@{
                    ComputerName            = $env:COMPUTERNAME
                    SiteName                = $null; SiteId = $null; SiteState = $null
                    BindingInformation      = $null; IPAddress = $null; Port = $null; HostHeader = $null
                    Protocol                = $null; SslFlags = $null; SniEnabled = $null; CentralCertStore = $null
                    Thumbprint              = $null; CertStoreLocation = $null; CertStoreName = $null
                    Subject                 = $null; SubjectCN = $null; Issuer = $null; SerialNumber = $null
                    NotBefore               = $null; NotAfter = $null; DaysUntilExpiration = $null; Expired = $null
                    SubjectAlternativeNames = @()
                    SignatureAlgorithm      = $null; KeyAlgorithm = $null; KeySize = $null
                    HasPrivateKey           = $null; FriendlyName = $null
                    Status                  = 'BindingNotFound'
                    ErrorMessage            = 'No https bindings matched the specified filters on this host.'
                    Timestamp               = $tsNow
                })
            }

            return $results
        }
    }

    process {
        foreach ($cn in $ComputerName) {
            $filterDays   = if ($PSBoundParameters.ContainsKey('ExpiringInDays')) { $ExpiringInDays } else { $null }
            $invokeParams = @{
                ComputerName = $cn
                ScriptBlock  = $scriptBlock
                ArgumentList = @(
                    $SiteName,
                    $Thumbprint,
                    $HostHeader,
                    $Port,
                    $filterDays,
                    $IncludeExpired.IsPresent
                )
            }
            if ($Credential) {
                $invokeParams['Credential'] = $Credential
            }

            try {
                $rawResults = Invoke-RemoteOrLocal @invokeParams
                foreach ($r in $rawResults) {
                    [PSCustomObject]([ordered]@{
                        PSTypeName              = 'PSWinOps.IISCertificateBinding'
                        ComputerName            = $r.ComputerName
                        SiteName                = $r.SiteName
                        SiteId                  = $r.SiteId
                        SiteState               = $r.SiteState
                        BindingInformation      = $r.BindingInformation
                        IPAddress               = $r.IPAddress
                        Port                    = $r.Port
                        HostHeader              = $r.HostHeader
                        Protocol                = $r.Protocol
                        SslFlags                = $r.SslFlags
                        SniEnabled              = $r.SniEnabled
                        CentralCertStore        = $r.CentralCertStore
                        Thumbprint              = $r.Thumbprint
                        CertStoreLocation       = $r.CertStoreLocation
                        CertStoreName           = $r.CertStoreName
                        Subject                 = $r.Subject
                        SubjectCN               = $r.SubjectCN
                        Issuer                  = $r.Issuer
                        SerialNumber            = $r.SerialNumber
                        NotBefore               = $r.NotBefore
                        NotAfter                = $r.NotAfter
                        DaysUntilExpiration     = $r.DaysUntilExpiration
                        Expired                 = $r.Expired
                        SubjectAlternativeNames = $r.SubjectAlternativeNames
                        SignatureAlgorithm      = $r.SignatureAlgorithm
                        KeyAlgorithm            = $r.KeyAlgorithm
                        KeySize                 = $r.KeySize
                        HasPrivateKey           = $r.HasPrivateKey
                        FriendlyName            = $r.FriendlyName
                        Status                  = $r.Status
                        ErrorMessage            = $r.ErrorMessage
                        Timestamp               = $r.Timestamp
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
