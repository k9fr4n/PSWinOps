#Requires -Version 5.1
function Get-WindowsUpdate {
    <#
        .SYNOPSIS
            Lists available Windows Updates on local or remote computers

        .DESCRIPTION
            Scans for available (not yet installed) Windows Updates using the COM API
            (Microsoft.Update.Session). Returns each pending update with its classification,
            product categories, download status, size, reboot requirement, MSRC severity,
            CVE identifiers, EULA status, and more.
            By default all classifications and products are returned. Use the Classification,
            Product, and KBArticleID parameters to filter results. Hidden updates are excluded
            unless the IncludeHidden switch is specified.
            By default, the machine's configured update source is used (WSUS, WUFB, or
            Windows Update). Use the MicrosoftUpdate switch to query the full Microsoft
            Update catalog instead.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local queries.

        .PARAMETER Classification
            Optional filter to return only updates matching the specified classifications.
            Common values: 'Critical Updates', 'Security Updates', 'Update Rollups',
            'Feature Packs', 'Service Packs', 'Definition Updates', 'Tools', 'Drivers', 'Updates'.
            When not specified, all classifications are returned.

        .PARAMETER Product
            Optional filter to return only updates matching the specified product names.
            Common values: 'Windows Server 2022', 'Windows 11', 'Microsoft Office',
            'Windows Defender'. When not specified, all products are returned.

        .PARAMETER KBArticleID
            Optional filter to return only updates matching the specified KB article IDs.
            Accepts one or more KB identifiers with or without the 'KB' prefix
            (e.g., 'KB5034441' or '5034441'). When not specified, all updates are returned.

        .PARAMETER MicrosoftUpdate
            When specified, queries the full Microsoft Update catalog instead of the
            machine's configured source (WSUS, WUFB, or Windows Update). This provides
            access to all Microsoft products including Office, SQL Server, etc.

        .PARAMETER IncludeHidden
            When specified, includes updates that have been hidden (declined).
            By default hidden updates are excluded from results.

        .EXAMPLE
            Get-WindowsUpdate

            Lists all available updates on the local computer using the configured source.

        .EXAMPLE
            Get-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441'

            Checks if a specific KB is available on SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-WindowsUpdate -MicrosoftUpdate -Classification 'Security Updates'

            Lists security updates from the full Microsoft Update catalog on SRV01 and SRV02.

        .OUTPUTS
            PSWinOps.WindowsUpdate
            Returns objects with ComputerName, Title, KBArticle, Classification, Products,
            IsDownloaded, IsHidden, IsInstalled, IsMandatory, IsUninstallable, RebootRequired,
            MsrcSeverity, Description, ReleaseNotes, CveIDs, EulaAccepted, Deadline,
            SizeMB, UpdateId, RevisionNumber, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.1.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only
            Requires: Windows Update service must be accessible on target machines

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iupdatesearcher
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.WindowsUpdate')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $false)]
        [switch]$MicrosoftUpdate,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KBArticleID,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Classification,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Product,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeHidden
    )

    begin {
        $sourceLabel = if ($MicrosoftUpdate) { 'Microsoft Update' } else { 'Default (machine config)' }
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting — Source: $sourceLabel"

        # Normalize KBArticleID — strip 'KB' prefix for consistent matching
        $normalizedKBIds = $null
        if ($KBArticleID) {
            $normalizedKBIds = $KBArticleID | ForEach-Object -Process {
                $_ -replace '^KB', ''
            }
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] KB filter: $($KBArticleID -join ', ')"
        }
        if ($Classification) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Classification filter: $($Classification -join ', ')"
        }
        if ($Product) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Product filter: $($Product -join ', ')"
        }
        if ($IncludeHidden) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Including hidden updates"
        }

        $wuScriptBlock = {
            param(
                [bool]$SearchHidden,
                [bool]$UseMicrosoftUpdate
            )

            try {
                # Detect machine's configured update source from registry
                $wuRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
                $auRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
                $wuReg = Get-ItemProperty -Path $wuRegPath -ErrorAction SilentlyContinue
                $auReg = Get-ItemProperty -Path $auRegPath -ErrorAction SilentlyContinue

                $configuredSource = 'Windows Update'
                $configuredUrl = $null
                $configuredTargetGroup = $null
                if ($auReg.UseWUServer -eq 1 -and -not [string]::IsNullOrEmpty($wuReg.WUServer)) {
                    $configuredSource = 'WSUS'
                    $configuredUrl = $wuReg.WUServer
                    $configuredTargetGroup = $wuReg.TargetGroup
                }
                elseif ($wuReg.DeferFeatureUpdates -eq 1 -or $wuReg.DeferQualityUpdates -eq 1) {
                    $configuredSource = 'WUFB'
                }

                $session = New-Object -ComObject 'Microsoft.Update.Session'
                $searcher = $session.CreateUpdateSearcher()

                $effectiveSource = $configuredSource
                if ($UseMicrosoftUpdate) {
                    $serviceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
                    $serviceManager.ClientApplicationID = 'PSWinOps'
                    $service = $serviceManager.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
                    $searcher.ServerSelection = 3
                    $searcher.ServiceID = $service.ServiceID
                    $effectiveSource = 'Microsoft Update'
                }

                $criteria = 'IsInstalled=0'
                if (-not $SearchHidden) {
                    $criteria += ' AND IsHidden=0'
                }

                $searchResult = $searcher.Search($criteria)

                # Build metadata object for verbose output
                $metadata = [PSCustomObject]@{
                    ConfiguredSource = $configuredSource
                    ConfiguredUrl    = $configuredUrl
                    TargetGroup      = $configuredTargetGroup
                    EffectiveSource  = $effectiveSource
                    TotalCount       = $searchResult.Updates.Count
                }

                if ($searchResult.Updates.Count -eq 0) {
                    return [PSCustomObject]@{
                        Metadata = $metadata
                        Entries  = @()
                    }
                }

                $entries = [System.Collections.Generic.List[object]]::new()
                foreach ($update in $searchResult.Updates) {
                    $classification = $null
                    $products = [System.Collections.Generic.List[string]]::new()

                    foreach ($category in $update.Categories) {
                        if ($category.Type -eq 'UpdateClassification') {
                            if ($null -eq $classification) {
                                $classification = $category.Name
                            }
                        }
                        else {
                            $products.Add($category.Name)
                        }
                    }

                    $kbArticle = ''
                    if ($update.KBArticleIDs.Count -gt 0) {
                        $kbArticle = "KB$($update.KBArticleIDs.Item(0))"
                    }

                    $cveIds = @()
                    if ($update.CveIDs) {
                        foreach ($cve in $update.CveIDs) {
                            $cveIds += [string]$cve
                        }
                    }

                    $allKBs = @()
                    if ($update.KBArticleIDs.Count -gt 0) {
                        foreach ($kb in $update.KBArticleIDs) {
                            $allKBs += [string]$kb
                        }
                    }

                    $entries.Add([PSCustomObject]@{
                        Title           = [string]$update.Title
                        KBArticle       = $kbArticle
                        KBArticleIDs    = $allKBs
                        Classification  = [string]$classification
                        Products        = @($products)
                        Description     = [string]$update.Description
                        ReleaseNotes    = [string]$update.ReleaseNotes
                        MsrcSeverity    = [string]$update.MsrcSeverity
                        CveIDs          = $cveIds
                        IsDownloaded    = [bool]$update.IsDownloaded
                        IsHidden        = [bool]$update.IsHidden
                        IsInstalled     = [bool]$update.IsInstalled
                        IsMandatory     = [bool]$update.IsMandatory
                        IsUninstallable = [bool]$update.IsUninstallable
                        EulaAccepted    = [bool]$update.EulaAccepted
                        Deadline        = $update.Deadline
                        RebootRequired  = ($update.RebootBehavior -ne 0)
                        MaxSizeBytes    = [long]$update.MaxDownloadSize
                        UpdateId        = [string]$update.Identity.UpdateID
                        RevisionNumber  = [int]$update.Identity.RevisionNumber
                    })
                }

                return [PSCustomObject]@{
                    Metadata = $metadata
                    Entries  = $entries
                }
            }
            catch {
                throw "Failed to search for Windows Updates: $_"
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Scanning '$computer' (Source: $sourceLabel, Criteria: IsInstalled=0$(if (-not $IncludeHidden) { ' AND IsHidden=0' }))"

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $wuScriptBlock
                    ArgumentList = @([bool]$IncludeHidden, [bool]$MicrosoftUpdate)
                }

                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $scanTimer = [System.Diagnostics.Stopwatch]::StartNew()
                $scanResult = Invoke-RemoteOrLocal @invokeParams
                $scanTimer.Stop()

                # Unpack metadata and entries
                $metadata = $scanResult.Metadata
                $rawEntries = $scanResult.Entries

                # Build verbose source info
                $configInfo = $metadata.ConfiguredSource
                if ($metadata.ConfiguredUrl) {
                    $configInfo += " ($($metadata.ConfiguredUrl))"
                }
                if ($metadata.TargetGroup) {
                    $configInfo += " [Group: $($metadata.TargetGroup)]"
                }

                if ($metadata.EffectiveSource -ne $metadata.ConfiguredSource) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] '$computer' configured: $configInfo — Overriding to: $($metadata.EffectiveSource)"
                }
                else {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] '$computer' source: $configInfo"
                }

                $totalFound = $metadata.TotalCount
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Scan completed on '$computer' in $($scanTimer.Elapsed.TotalSeconds.ToString('F1'))s — $totalFound update(s) found"

                if ($totalFound -eq 0) {
                    continue
                }

                # Filter by KBArticleID if specified
                if ($normalizedKBIds) {
                    $rawEntries = @($rawEntries | Where-Object -FilterScript {
                        $entryKBs = $_.KBArticleIDs
                        $null -ne ($normalizedKBIds | Where-Object -FilterScript { $_ -in $entryKBs } |
                            Select-Object -First 1)
                    })
                }

                # Filter by Classification if specified
                if ($Classification) {
                    $rawEntries = @($rawEntries | Where-Object -FilterScript {
                        $_.Classification -in $Classification
                    })
                }

                # Filter by Product if specified
                if ($Product) {
                    $rawEntries = @($rawEntries | Where-Object -FilterScript {
                        $entryProducts = $_.Products
                        $null -ne ($Product | Where-Object -FilterScript { $_ -in $entryProducts } |
                            Select-Object -First 1)
                    })
                }

                $filteredCount = @($rawEntries).Count
                if ($filteredCount -ne $totalFound) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] After filtering: $filteredCount of $totalFound update(s) match criteria on '$computer'"
                }

                foreach ($entry in $rawEntries) {
                    [PSCustomObject]@{
                        PSTypeName      = 'PSWinOps.WindowsUpdate'
                        ComputerName    = $computer
                        Title           = $entry.Title
                        KBArticle       = $entry.KBArticle
                        Classification  = $entry.Classification
                        Products        = $entry.Products
                        Description     = $entry.Description
                        ReleaseNotes    = $entry.ReleaseNotes
                        MsrcSeverity    = $entry.MsrcSeverity
                        CveIDs          = $entry.CveIDs
                        IsDownloaded    = $entry.IsDownloaded
                        IsHidden        = $entry.IsHidden
                        IsInstalled     = $entry.IsInstalled
                        IsMandatory     = $entry.IsMandatory
                        IsUninstallable = $entry.IsUninstallable
                        EulaAccepted    = $entry.EulaAccepted
                        Deadline        = $entry.Deadline
                        RebootRequired  = $entry.RebootRequired
                        SizeMB          = [math]::Round($entry.MaxSizeBytes / 1MB, 2)
                        UpdateId        = $entry.UpdateId
                        RevisionNumber  = $entry.RevisionNumber
                        Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to retrieve updates from ${computer}: $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}