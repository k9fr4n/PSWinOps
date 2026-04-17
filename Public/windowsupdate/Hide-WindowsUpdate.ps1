#Requires -Version 5.1
function Hide-WindowsUpdate {
    <#
        .SYNOPSIS
            Hides one or more Windows Updates to prevent them from being installed

        .DESCRIPTION
            Hides (declines) specified Windows Updates by setting the IsHidden property
            to true on matching IUpdate COM objects. Hidden updates are excluded from
            automatic installation and from Get-WindowsUpdate results unless -IncludeHidden
            is specified. Use Show-WindowsUpdate to unhide them later.
            Searches both visible and already-hidden updates to accurately report
            AlreadyHidden status.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local operations.

        .PARAMETER KBArticleID
            One or more KB article IDs to hide. Accepts values with or without
            the KB prefix (e.g., 'KB5034441' or '5034441').

        .PARAMETER MicrosoftUpdate
            When specified, queries the full Microsoft Update catalog instead of the
            machine's configured source.

        .EXAMPLE
            Hide-WindowsUpdate -KBArticleID 'KB5034441'

            Hides KB5034441 on the local computer.

        .EXAMPLE
            Hide-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441', 'KB5035432'

            Hides two updates on SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Hide-WindowsUpdate -KBArticleID 'KB5034441'

            Hides KB5034441 on SRV01 and SRV02 via pipeline.

        .OUTPUTS
            PSWinOps.WindowsUpdateHideResult
            Returns objects with ComputerName, Title, KBArticle, Result, and Timestamp.
            Result is one of: Hidden, AlreadyHidden, NotFound.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdate-get_ishidden
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('PSWinOps.WindowsUpdateHideResult')]
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

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KBArticleID,

        [Parameter(Mandatory = $false)]
        [switch]$MicrosoftUpdate
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $normalizedKBIds = $KBArticleID | ForEach-Object -Process { $_ -replace '^KB', '' }
        $kbCsv = $normalizedKBIds -join ','
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] KB targets: $($normalizedKBIds | ForEach-Object -Process { "KB$_" }) "

        $hideScriptBlock = {
            param(
                [string]$KBCsv,
                [bool]$UseMicrosoftUpdate
            )

            $kbTargets = $KBCsv -split ','
            $session = New-Object -ComObject 'Microsoft.Update.Session'
            $session.ClientApplicationID = 'PSWinOps'
            $searcher = $session.CreateUpdateSearcher()

            if ($UseMicrosoftUpdate) {
                $serviceManager = New-Object -ComObject 'Microsoft.Update.ServiceManager'
                $serviceManager.ClientApplicationID = 'PSWinOps'
                $service = $serviceManager.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
                $searcher.ServerSelection = 3
                $searcher.ServiceID = $service.ServiceID
            }

            $processedKB = @{}

            # Search available (non-hidden) updates
            $availableResult = $searcher.Search('IsInstalled=0')
            foreach ($update in $availableResult.Updates) {
                foreach ($kbId in $update.KBArticleIDs) {
                    if ($kbTargets -contains $kbId -and -not $processedKB.ContainsKey($kbId)) {
                        $update.IsHidden = $true
                        $processedKB[$kbId] = [PSCustomObject]@{
                            Title  = [string]$update.Title
                            Result = 'Hidden'
                        }
                    }
                }
            }

            # Search already-hidden updates
            $hiddenResult = $searcher.Search('IsInstalled=0 AND IsHidden=1')
            foreach ($update in $hiddenResult.Updates) {
                foreach ($kbId in $update.KBArticleIDs) {
                    if ($kbTargets -contains $kbId -and -not $processedKB.ContainsKey($kbId)) {
                        $processedKB[$kbId] = [PSCustomObject]@{
                            Title  = [string]$update.Title
                            Result = 'AlreadyHidden'
                        }
                    }
                }
            }

            # Build results preserving input order
            foreach ($kb in $kbTargets) {
                if ($processedKB.ContainsKey($kb)) {
                    [PSCustomObject]@{
                        KBArticle = "KB$kb"
                        Title     = $processedKB[$kb].Title
                        Result    = $processedKB[$kb].Result
                    }
                } else {
                    [PSCustomObject]@{
                        KBArticle = "KB$kb"
                        Title     = $null
                        Result    = 'NotFound'
                    }
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$computer'"

            if (-not $PSCmdlet.ShouldProcess("$computer — KB$($normalizedKBIds -join ', KB')", 'Hide Windows Update')) {
                continue
            }

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $hideScriptBlock
                    ArgumentList = @($kbCsv, [bool]$MicrosoftUpdate)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $results = Invoke-RemoteOrLocal @invokeParams

                foreach ($entry in $results) {
                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.WindowsUpdateHideResult'
                        ComputerName = $computer
                        Title        = $entry.Title
                        KBArticle    = $entry.KBArticle
                        Result       = $entry.Result
                        Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${computer}': $_"
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
