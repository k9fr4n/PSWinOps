#Requires -Version 5.1
function Set-IISBindingCertificate {
    <#
        .SYNOPSIS
            Replaces the SSL/TLS certificate on one or more IIS https site bindings.

        .DESCRIPTION
            Replace the SSL/TLS certificate bound to one or more IIS HTTPS site bindings,
            typically to rotate a certificate that is approaching expiration. The new
            certificate must already exist in the target certificate store (LocalMachine\My
            by default). The function is idempotent: running it twice with the same
            thumbprint yields Status=AlreadyUpToDate on the second call. Supports remote
            execution via WinRM, -WhatIf/-Confirm (ConfirmImpact=High), and pipeline input
            by property name from Get-IISHealth / Get-SSLCertificate.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER SiteName
            IIS site name (Get-Website -Name).

        .PARAMETER BindingInformation
            Binding selector ip:port:hostheader (e.g. *:443:www.contoso.com).
            When omitted, the function applies to ALL https bindings of the site.

        .PARAMETER Thumbprint
            SHA-1 thumbprint (40 hex chars) of the new certificate.
            Must already be present in -CertStoreLocation on the target.

        .PARAMETER CertStoreLocation
            Certificate store to read the new cert from.
            Valid values: 'Cert:\LocalMachine\My' (default) or 'Cert:\LocalMachine\WebHosting'.

        .PARAMETER Force
            Bypass the ConfirmImpact=High prompt (equivalent to -Confirm:$false).

        .EXAMPLE
            Set-IISBindingCertificate -SiteName 'www.contoso.com' -Thumbprint 'A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2' -Confirm:$false

            Replaces the cert on every https binding of the site without prompting.

        .EXAMPLE
            Set-IISBindingCertificate -SiteName 'Default Web Site' -BindingInformation '*:443:portal.contoso.com' -Thumbprint $newTp

            Targets one specific binding by its ip:port:hostheader selector.

        .EXAMPLE
            'WEB01','WEB02','WEB03' | Set-IISBindingCertificate -SiteName 'api' -Thumbprint $newTp -Credential (Get-Credential) -WhatIf

            Previews certificate rotation across a fleet via pipeline with explicit credentials.

        .EXAMPLE
            Get-SSLCertificate -ComputerName WEB01 -Port 443 | Set-IISBindingCertificate -SiteName 'www' -Thumbprint $newTp

            Pipeline-by-property-name from Get-SSLCertificate.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISBindingCertificateResult')
            Returns one object per (ComputerName, binding) pair.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-14
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role
            Requires: Module WebAdministration or IISAdministration

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/iis/manage/powershell/powershell-snap-in-changing-simple-settings-at-the-command-line
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.IISBindingCertificateResult')]
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

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$BindingInformation,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[A-Fa-f0-9]{40}$')]
        [string]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Cert:\LocalMachine\My', 'Cert:\LocalMachine\WebHosting')]
        [string]$CertStoreLocation = 'Cert:\LocalMachine\My',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        # Honour -Force by suppressing the ConfirmImpact=High prompt.
        if ($Force.IsPresent) {
            $ConfirmPreference = 'None'
        }

        # ---------------------------------------------------------------
        # Phase 1 scriptBlock — read-only state query (safe under -WhatIf)
        # ---------------------------------------------------------------
        $queryScriptBlock = {
            param(
                [string]$QSiteName,
                [string]$QBindingInformation,
                [string]$QThumbprint,
                [string]$QCertStoreLocation
            )

            $queryResults = [System.Collections.Generic.List[hashtable]]::new()

            # Detect available IIS module (mirrors Get-IISHealth pattern).
            $iisModule = $null
            if (Get-Module -Name 'WebAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'WebAdministration'
            }
            elseif (Get-Module -Name 'IISAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'IISAdministration'
            }

            if ($null -eq $iisModule) {
                $queryResults.Add(@{
                    SiteName           = $QSiteName
                    BindingInformation = $QBindingInformation
                    Protocol           = 'https'
                    PreviousThumbprint = $null
                    NewThumbprint      = $QThumbprint
                    CertStoreLocation  = $QCertStoreLocation
                    SslFlags           = 0
                    Status             = 'Failed'
                    ErrorMessage       = 'Neither WebAdministration nor IISAdministration module is available on the target.'
                    SslKey             = $null
                })
                return $queryResults
            }

            try {
                Import-Module -Name $iisModule -ErrorAction Stop

                if ($iisModule -eq 'WebAdministration') {

                    $site = Get-Website -Name $QSiteName -ErrorAction SilentlyContinue
                    if ($null -eq $site) {
                        $queryResults.Add(@{
                            SiteName           = $QSiteName
                            BindingInformation = $QBindingInformation
                            Protocol           = 'https'
                            PreviousThumbprint = $null
                            NewThumbprint      = $QThumbprint
                            CertStoreLocation  = $QCertStoreLocation
                            SslFlags           = 0
                            Status             = 'BindingNotFound'
                            ErrorMessage       = "Site '$QSiteName' not found."
                            SslKey             = $null
                        })
                        return $queryResults
                    }

                    $httpsBindings = @(Get-WebBinding -Name $QSiteName -Protocol 'https' -ErrorAction SilentlyContinue)
                    if ($httpsBindings.Count -eq 0) {
                        $queryResults.Add(@{
                            SiteName           = $QSiteName
                            BindingInformation = $QBindingInformation
                            Protocol           = 'https'
                            PreviousThumbprint = $null
                            NewThumbprint      = $QThumbprint
                            CertStoreLocation  = $QCertStoreLocation
                            SslFlags           = 0
                            Status             = 'BindingNotFound'
                            ErrorMessage       = "No https bindings found on site '$QSiteName'."
                            SslKey             = $null
                        })
                        return $queryResults
                    }

                    if (-not [string]::IsNullOrEmpty($QBindingInformation)) {
                        $httpsBindings = @($httpsBindings | Where-Object { $_.bindingInformation -eq $QBindingInformation })
                        if ($httpsBindings.Count -eq 0) {
                            $queryResults.Add(@{
                                SiteName           = $QSiteName
                                BindingInformation = $QBindingInformation
                                Protocol           = 'https'
                                PreviousThumbprint = $null
                                NewThumbprint      = $QThumbprint
                                CertStoreLocation  = $QCertStoreLocation
                                SslFlags           = 0
                                Status             = 'BindingNotFound'
                                ErrorMessage       = "No https binding matching '$QBindingInformation' found on site '$QSiteName'."
                                SslKey             = $null
                            })
                            return $queryResults
                        }
                    }

                    foreach ($wb in $httpsBindings) {
                        $bindInfo    = $wb.bindingInformation
                        $sslFlagsVal = [int]$wb.sslFlags

                        # Build IIS:\SslBindings key: <ip>!<port> or <ip>!<port>!<host>
                        $parts      = $bindInfo -split ':'
                        $ipPart     = $parts[0]
                        $portPart   = $parts[1]
                        $hostHeader = if ($parts.Count -ge 3) { $parts[2] } else { '' }
                        $sslKey     = if ([string]::IsNullOrEmpty($hostHeader)) {
                            "$ipPart!$portPart"
                        } else {
                            "$ipPart!$portPart!$hostHeader"
                        }

                        $prevThumbprint = $null
                        try {
                            $existingEntry  = Get-Item -Path "IIS:\SslBindings\$sslKey" -ErrorAction Stop
                            $prevThumbprint = $existingEntry.Thumbprint
                        }
                        catch {
                            Write-Verbose -Message "No pre-existing SSL binding found for key '$sslKey'."
                        }

                        $certPath  = Join-Path -Path $QCertStoreLocation -ChildPath $QThumbprint
                        $certFound = Test-Path -Path $certPath

                        $bindingStatus = if ($prevThumbprint -eq $QThumbprint) {
                            'AlreadyUpToDate'
                        }
                        elseif (-not $certFound) {
                            'CertNotFound'
                        }
                        else {
                            'NeedsReplacement'
                        }

                        $queryResults.Add(@{
                            SiteName           = $QSiteName
                            BindingInformation = $bindInfo
                            Protocol           = 'https'
                            PreviousThumbprint = $prevThumbprint
                            NewThumbprint      = $QThumbprint
                            CertStoreLocation  = $QCertStoreLocation
                            SslFlags           = $sslFlagsVal
                            Status             = $bindingStatus
                            ErrorMessage       = $null
                            SslKey             = $sslKey
                        })
                    }
                }
                else {
                    # IISAdministration fallback
                    $site = Get-IISSite -Name $QSiteName -ErrorAction SilentlyContinue
                    if ($null -eq $site) {
                        $queryResults.Add(@{
                            SiteName           = $QSiteName
                            BindingInformation = $QBindingInformation
                            Protocol           = 'https'
                            PreviousThumbprint = $null
                            NewThumbprint      = $QThumbprint
                            CertStoreLocation  = $QCertStoreLocation
                            SslFlags           = 0
                            Status             = 'BindingNotFound'
                            ErrorMessage       = "Site '$QSiteName' not found."
                            SslKey             = $null
                        })
                        return $queryResults
                    }

                    $httpsBindings = @($site.Bindings | Where-Object { $_.Protocol -eq 'https' })
                    if ($httpsBindings.Count -eq 0) {
                        $queryResults.Add(@{
                            SiteName           = $QSiteName
                            BindingInformation = $QBindingInformation
                            Protocol           = 'https'
                            PreviousThumbprint = $null
                            NewThumbprint      = $QThumbprint
                            CertStoreLocation  = $QCertStoreLocation
                            SslFlags           = 0
                            Status             = 'BindingNotFound'
                            ErrorMessage       = "No https bindings found on site '$QSiteName'."
                            SslKey             = $null
                        })
                        return $queryResults
                    }

                    if (-not [string]::IsNullOrEmpty($QBindingInformation)) {
                        $httpsBindings = @($httpsBindings | Where-Object { $_.BindingInformation -eq $QBindingInformation })
                        if ($httpsBindings.Count -eq 0) {
                            $queryResults.Add(@{
                                SiteName           = $QSiteName
                                BindingInformation = $QBindingInformation
                                Protocol           = 'https'
                                PreviousThumbprint = $null
                                NewThumbprint      = $QThumbprint
                                CertStoreLocation  = $QCertStoreLocation
                                SslFlags           = 0
                                Status             = 'BindingNotFound'
                                ErrorMessage       = "No https binding matching '$QBindingInformation' found on site '$QSiteName'."
                                SslKey             = $null
                            })
                            return $queryResults
                        }
                    }

                    foreach ($ib in $httpsBindings) {
                        $bindInfo    = $ib.BindingInformation
                        $sslFlagsVal = [int]$ib.SslFlags

                        $parts      = $bindInfo -split ':'
                        $ipPart     = $parts[0]
                        $portPart   = $parts[1]
                        $hostHeader = if ($parts.Count -ge 3) { $parts[2] } else { '' }
                        $sslKey     = if ([string]::IsNullOrEmpty($hostHeader)) {
                            "$ipPart!$portPart"
                        } else {
                            "$ipPart!$portPart!$hostHeader"
                        }

                        # IISAdministration: CertificateHash is a byte array.
                        $prevThumbprint = $null
                        $certHashBytes  = $ib.CertificateHash
                        if ($certHashBytes) {
                            $prevThumbprint = ([System.BitConverter]::ToString([byte[]]$certHashBytes) -replace '-', '')
                        }

                        $certPath  = Join-Path -Path $QCertStoreLocation -ChildPath $QThumbprint
                        $certFound = Test-Path -Path $certPath

                        $bindingStatus = if ($prevThumbprint -eq $QThumbprint) {
                            'AlreadyUpToDate'
                        }
                        elseif (-not $certFound) {
                            'CertNotFound'
                        }
                        else {
                            'NeedsReplacement'
                        }

                        $queryResults.Add(@{
                            SiteName           = $QSiteName
                            BindingInformation = $bindInfo
                            Protocol           = 'https'
                            PreviousThumbprint = $prevThumbprint
                            NewThumbprint      = $QThumbprint
                            CertStoreLocation  = $QCertStoreLocation
                            SslFlags           = $sslFlagsVal
                            Status             = $bindingStatus
                            ErrorMessage       = $null
                            SslKey             = $sslKey
                        })
                    }
                }
            }
            catch {
                $queryResults.Add(@{
                    SiteName           = $QSiteName
                    BindingInformation = $QBindingInformation
                    Protocol           = 'https'
                    PreviousThumbprint = $null
                    NewThumbprint      = $QThumbprint
                    CertStoreLocation  = $QCertStoreLocation
                    SslFlags           = 0
                    Status             = 'Failed'
                    ErrorMessage       = $_.Exception.Message
                    SslKey             = $null
                })
            }

            return $queryResults
        }

        # ---------------------------------------------------------------
        # Phase 2 scriptBlock — write (cert replacement)
        # ---------------------------------------------------------------
        $applyScriptBlock = {
            param(
                [string]$ASiteName,
                [string]$ABindingInformation,
                [string]$AThumbprint,
                [string]$ACertStoreLocation,
                [string]$ASslKey,
                [int]$ASslFlags
            )

            # Re-detect available IIS module (cheap; avoids serializing module name).
            $iisModule = $null
            if (Get-Module -Name 'WebAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'WebAdministration'
            }
            elseif (Get-Module -Name 'IISAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'IISAdministration'
            }

            if ($null -eq $iisModule) {
                return @{ Success = $false; NewThumbprint = $null; ErrorMessage = 'IIS module unavailable on target.' }
            }

            try {
                Import-Module -Name $iisModule -ErrorAction Stop

                if ($iisModule -eq 'WebAdministration') {
                    # Remove existing SSL binding entry.
                    if (Test-Path -Path "IIS:\SslBindings\$ASslKey") {
                        Remove-Item -Path "IIS:\SslBindings\$ASslKey" -ErrorAction Stop
                    }

                    # Bind the new certificate (pipe cert object to New-Item on IIS: provider).
                    $certItem = Get-Item -Path (Join-Path -Path $ACertStoreLocation -ChildPath $AThumbprint) -ErrorAction Stop
                    $null = $certItem | New-Item -Path "IIS:\SslBindings\$ASslKey" -SslFlags $ASslFlags -ErrorAction Stop

                    # Verify replacement.
                    $confirmedEntry = Get-Item -Path "IIS:\SslBindings\$ASslKey" -ErrorAction Stop
                    return @{ Success = $true; NewThumbprint = $confirmedEntry.Thumbprint; ErrorMessage = $null }
                }
                else {
                    # IISAdministration fallback: remove and re-add the binding.
                    Remove-IISSiteBinding -Name $ASiteName -BindingInformation $ABindingInformation `
                        -Protocol 'https' -Confirm:$false -ErrorAction Stop

                    $addParams = @{
                        Name                  = $ASiteName
                        BindingInformation    = $ABindingInformation
                        Protocol              = 'https'
                        CertificateThumbPrint = $AThumbprint
                        CertStoreLocation     = $ACertStoreLocation
                        SslFlag               = $ASslFlags
                    }
                    Add-IISSiteBinding @addParams -ErrorAction Stop
                    return @{ Success = $true; NewThumbprint = $AThumbprint; ErrorMessage = $null }
                }
            }
            catch {
                return @{ Success = $false; NewThumbprint = $null; ErrorMessage = $_.Exception.Message }
            }
        }
    }

    process {
        foreach ($cn in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$cn'"

            try {
                $queryArgs      = @($SiteName, $BindingInformation, $Thumbprint, $CertStoreLocation)
                $queryRawResult = Invoke-RemoteOrLocal -ComputerName $cn -Credential $Credential `
                    -ScriptBlock $queryScriptBlock -ArgumentList $queryArgs

                foreach ($entry in $queryRawResult) {
                    $entryStatus    = $entry.Status
                    $entryBindInfo  = $entry.BindingInformation
                    $entryPrevThumb = $entry.PreviousThumbprint
                    $entryNewThumb  = $entry.NewThumbprint
                    $entrySslFlags  = $entry.SslFlags
                    $entrySslKey    = $entry.SslKey
                    $entryErrMsg    = $entry.ErrorMessage

                    if ($entryStatus -eq 'NeedsReplacement') {
                        $spTarget = "$cn/$SiteName binding $entryBindInfo"
                        $spAction = "Replace SSL certificate $entryPrevThumb -> $Thumbprint"

                        if ($PSCmdlet.ShouldProcess($spTarget, $spAction)) {
                            try {
                                $applyArgs   = @($SiteName, $entryBindInfo, $Thumbprint, $CertStoreLocation, $entrySslKey, $entrySslFlags)
                                $applyResult = Invoke-RemoteOrLocal -ComputerName $cn -Credential $Credential `
                                    -ScriptBlock $applyScriptBlock -ArgumentList $applyArgs

                                if ($applyResult.Success) {
                                    $entryStatus   = 'Replaced'
                                    $entryNewThumb = $applyResult.NewThumbprint
                                    $entryErrMsg   = $null
                                }
                                else {
                                    $entryStatus = 'Failed'
                                    $entryErrMsg = $applyResult.ErrorMessage
                                }
                            }
                            catch {
                                $entryStatus = 'Failed'
                                $entryErrMsg = $_.Exception.Message
                            }

                            [PSCustomObject]@{
                                PSTypeName         = 'PSWinOps.IISBindingCertificateResult'
                                ComputerName       = $cn.ToUpper()
                                SiteName           = $entry.SiteName
                                BindingInformation = $entryBindInfo
                                Protocol           = $entry.Protocol
                                PreviousThumbprint = $entryPrevThumb
                                NewThumbprint      = $entryNewThumb
                                CertStoreLocation  = $entry.CertStoreLocation
                                SslFlags           = $entrySslFlags
                                Status             = $entryStatus
                                ErrorMessage       = $entryErrMsg
                                Timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            }
                        }
                        # ShouldProcess returned $false (-WhatIf / user declined): no output emitted.
                    }
                    else {
                        # AlreadyUpToDate, CertNotFound, BindingNotFound, Failed: emit directly.
                        [PSCustomObject]@{
                            PSTypeName         = 'PSWinOps.IISBindingCertificateResult'
                            ComputerName       = $cn.ToUpper()
                            SiteName           = $entry.SiteName
                            BindingInformation = $entryBindInfo
                            Protocol           = $entry.Protocol
                            PreviousThumbprint = $entryPrevThumb
                            NewThumbprint      = $entryNewThumb
                            CertStoreLocation  = $entry.CertStoreLocation
                            SslFlags           = $entrySslFlags
                            Status             = $entryStatus
                            ErrorMessage       = $entryErrMsg
                            Timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        }
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${cn}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
