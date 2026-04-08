#Requires -Version 5.1
function Get-WindowsUpdate {
    <#
        .SYNOPSIS
            Lists available Windows Updates on local or remote computers

        .DESCRIPTION
            Scans for available (not yet installed) Windows Updates using the COM API
            (Microsoft.Update.Session). Returns each pending update with its classification,
            product categories, download status, size, and reboot requirement.
            By default all classifications and products are returned. Use the Classification
            and Product parameters to filter results. Hidden updates are excluded unless
            the IncludeHidden switch is specified.
            The Source parameter controls which update service is queried: the machine's
            configured source (Default), Microsoft Update (full catalog), or Windows Update
            (bypassing WSUS).

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

        .PARAMETER Source
            Specifies the update service to query. Valid values are:
            - Default: Uses the machine's configured source (WSUS, WUFB, or Windows Update).
            - MicrosoftUpdate: Queries the full Microsoft Update catalog (all products).
            - WindowsUpdate: Queries Windows Update directly, bypassing WSUS if configured.
            Defaults to 'Default'.

        .PARAMETER IncludeHidden
            When specified, includes updates that have been hidden (declined).
            By default hidden updates are excluded from results.

        .EXAMPLE
            Get-WindowsUpdate

            Lists all available updates on the local computer using the configured source.

        .EXAMPLE
            Get-WindowsUpdate -ComputerName 'SRV01' -Source MicrosoftUpdate -Classification 'Security Updates'

            Lists security updates from the full Microsoft Update catalog on SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-WindowsUpdate -Source WindowsUpdate | Where-Object { -not $_.IsDownloaded }

            Bypasses WSUS and queries Windows Update directly on SRV01 and SRV02, filtering for not-yet-downloaded updates.

        .OUTPUTS
            PSWinOps.WindowsUpdate
            Returns objects with ComputerName, Title, KBArticle, Classification, Products,
            IsDownloaded, IsHidden, IsMandatory, RebootRequired, SizeMB, UpdateId,
            RevisionNumber, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
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
        [ValidateSet('Default', 'MicrosoftUpdate', 'WindowsUpdate')]
        [string]$Source = 'Default',

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
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $wuScriptBlock = {
            param(
                [bool]$SearchHidden,
                [string]$UpdateSource
            )

            try {
                $session = New-Object -ComObject 'Microsoft.Update.Session'
                $searcher = $session.CreateUpdateSearcher()

                switch ($UpdateSource) {
                    'MicrosoftUpdate' {
                        $serviceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
                        $serviceManager.ClientApplicationID = 'PSWinOps'
                        $service = $serviceManager.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
                        $searcher.ServerSelection = 3
                        $searcher.ServiceID = $service.ServiceID
                    }
                    'WindowsUpdate' {
                        $searcher.ServerSelection = 2
                    }
                }

                $criteria = 'IsInstalled=0'
                if (-not $SearchHidden) {
                    $criteria += ' AND IsHidden=0'
                }

                $searchResult = $searcher.Search($criteria)

                if ($searchResult.Updates.Count -eq 0) {
                    return @()
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

                    $entries.Add([PSCustomObject]@{
                        Title          = [string]$update.Title
                        KBArticle      = $kbArticle
                        Classification = [string]$classification
                        Products       = @($products)
                        IsDownloaded   = [bool]$update.IsDownloaded
                        IsHidden       = [bool]$update.IsHidden
                        IsMandatory    = [bool]$update.IsMandatory
                        RebootRequired = ($update.RebootBehavior -ne 0)
                        MaxSizeBytes   = [long]$update.MaxDownloadSize
                        UpdateId       = [string]$update.Identity.UpdateID
                        RevisionNumber = [int]$update.Identity.RevisionNumber
                    })
                }

                return $entries
            }
            catch {
                throw "Failed to search for Windows Updates: $_"
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Scanning for updates on $computer"

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $wuScriptBlock
                    ArgumentList = @([bool]$IncludeHidden, $Source)
                }

                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawEntries = Invoke-RemoteOrLocal @invokeParams

                if (-not $rawEntries -or @($rawEntries).Count -eq 0) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No available updates found on $computer"
                    continue
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

                foreach ($entry in $rawEntries) {
                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.WindowsUpdate'
                        ComputerName   = $computer
                        Title          = $entry.Title
                        KBArticle      = $entry.KBArticle
                        Classification = $entry.Classification
                        Products       = $entry.Products
                        IsDownloaded   = $entry.IsDownloaded
                        IsHidden       = $entry.IsHidden
                        IsMandatory    = $entry.IsMandatory
                        RebootRequired = $entry.RebootRequired
                        SizeMB         = [math]::Round($entry.MaxSizeBytes / 1MB, 2)
                        UpdateId       = $entry.UpdateId
                        RevisionNumber = $entry.RevisionNumber
                        Timestamp      = Get-Date -Format 'o'
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