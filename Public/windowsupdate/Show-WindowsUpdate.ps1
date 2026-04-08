#Requires -Version 5.1
function Show-WindowsUpdate {
    <#
        .SYNOPSIS
            Unhides previously hidden Windows Updates to allow installation

        .DESCRIPTION
            Reverses the hiding of Windows Updates by setting the IsHidden property
            to false on matching IUpdate COM objects. This function searches only
            hidden, non-installed updates and restores visibility for those matching
            the specified KB article IDs.
            Use this after Hide-WindowsUpdate to re-enable updates for installation.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local operations.

        .PARAMETER KBArticleID
            One or more KB article IDs to unhide. Accepts values with or without
            the KB prefix (e.g., 'KB5034441' or '5034441').

        .PARAMETER MicrosoftUpdate
            When specified, queries the full Microsoft Update catalog instead of the
            machine's configured source.

        .EXAMPLE
            Show-WindowsUpdate -KBArticleID 'KB5034441'

            Unhides KB5034441 on the local computer.

        .EXAMPLE
            Show-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441', 'KB5035432'

            Unhides two updates on SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Show-WindowsUpdate -KBArticleID 'KB5034441'

            Unhides KB5034441 on SRV01 and SRV02 via pipeline.

        .OUTPUTS
            PSWinOps.WindowsUpdateShowResult
            Returns objects with ComputerName, Title, KBArticle, Result, and Timestamp.
            Result is one of: Shown, NotFound.

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
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType('PSWinOps.WindowsUpdateShowResult')]
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
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] KB targets: $($normalizedKBIds | ForEach-Object -Process { "KB$_" })"

        $showScriptBlock = {
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

            # Search only hidden, non-installed updates
            $searchResult = $searcher.Search('IsInstalled=0 AND IsHidden=1')
            $foundKBs = @{}

            foreach ($update in $searchResult.Updates) {
                foreach ($kbId in $update.KBArticleIDs) {
                    if ($kbTargets -contains $kbId -and -not $foundKBs.ContainsKey($kbId)) {
                        $update.IsHidden = $false
                        $foundKBs[$kbId] = [string]$update.Title
                    }
                }
            }

            # Build results preserving input order
            foreach ($kb in $kbTargets) {
                if ($foundKBs.ContainsKey($kb)) {
                    [PSCustomObject]@{
                        KBArticle = "KB$kb"
                        Title     = $foundKBs[$kb]
                        Result    = 'Shown'
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

            if (-not $PSCmdlet.ShouldProcess("$computer — KB$($normalizedKBIds -join ', KB')", 'Show Windows Update')) {
                continue
            }

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $showScriptBlock
                    ArgumentList = @($kbCsv, [bool]$MicrosoftUpdate)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $results = Invoke-RemoteOrLocal @invokeParams

                foreach ($entry in $results) {
                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.WindowsUpdateShowResult'
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
