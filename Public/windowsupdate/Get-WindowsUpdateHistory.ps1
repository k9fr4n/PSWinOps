#Requires -Version 5.1
function Get-WindowsUpdateHistory {
    <#
        .SYNOPSIS
            Retrieves Windows Update installation history from local or remote computers

        .DESCRIPTION
            Queries the Windows Update Agent COM API (Microsoft.Update.Session) to retrieve
            the installation history of Windows Updates. Results include update title, KB article,
            operation type, result status, date, description, and support URL.
            Output is sorted by date descending (most recent first) and limited by MaxResults.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER MaxResults
            Maximum number of history entries to return per computer.
            Valid range is 1 to 1000. Defaults to 50.

        .EXAMPLE
            Get-WindowsUpdateHistory

            Retrieves the 50 most recent Windows Update history entries from the local computer.

        .EXAMPLE
            Get-WindowsUpdateHistory -ComputerName 'SRV01' -Credential (Get-Credential) -MaxResults 100

            Retrieves the 100 most recent update history entries from SRV01 using alternate credentials.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-WindowsUpdateHistory -MaxResults 10

            Retrieves the 10 most recent update history entries from SRV01 and SRV02 via pipeline.

        .OUTPUTS
            PSWinOps.WindowsUpdateHistory
            Returns objects with ComputerName, Title, KBArticle, Operation, Result, Date,
            Description, SupportUrl, UpdateIdentity, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only
            Requires: Windows Update service must be accessible on target machines

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iupdatesession
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.WindowsUpdateHistory')]
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
        [ValidateRange(1, 1000)]
        [int]$MaxResults = 50
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $resultCodeMap = @{
            0 = 'NotStarted'
            1 = 'InProgress'
            2 = 'Succeeded'
            3 = 'SucceededWithErrors'
            4 = 'Failed'
            5 = 'Aborted'
        }

        $operationMap = @{
            1 = 'Installation'
            2 = 'Uninstallation'
        }

        $wuScriptBlock = {
            param(
                [int]$Limit
            )

            try {
                $session = New-Object -ComObject 'Microsoft.Update.Session'
                $searcher = $session.CreateUpdateSearcher()
                $totalCount = $searcher.GetTotalHistoryCount()

                if ($totalCount -eq 0) {
                    return @()
                }

                $queryCount = [System.Math]::Min($Limit, $totalCount)
                $history = $searcher.QueryHistory(0, $queryCount)

                $entries = [System.Collections.Generic.List[object]]::new()
                foreach ($entry in $history) {
                    $entries.Add([PSCustomObject]@{
                        Title          = [string]$entry.Title
                        Operation      = [int]$entry.Operation
                        ResultCode     = [int]$entry.ResultCode
                        Date           = [datetime]$entry.Date
                        Description    = [string]$entry.Description
                        SupportUrl     = [string]$entry.SupportUrl
                        UpdateIdentity = [string]$entry.UpdateIdentity.UpdateID
                    })
                }

                return $entries
            }
            catch {
                throw "Failed to query Windows Update history: $_"
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying update history on $computer"

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $wuScriptBlock
                    ArgumentList = @($MaxResults)
                }

                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawEntries = Invoke-RemoteOrLocal @invokeParams

                if (-not $rawEntries -or @($rawEntries).Count -eq 0) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No update history found on $computer"
                    continue
                }

                $sortedEntries = $rawEntries | Sort-Object -Property 'Date' -Descending

                foreach ($entry in $sortedEntries) {
                    $kbMatch = [regex]::Match($entry.Title, 'KB\d+')
                    $kbArticle = if ($kbMatch.Success) { $kbMatch.Value } else { '' }

                    $operationString = if ($operationMap.ContainsKey($entry.Operation)) {
                        $operationMap[$entry.Operation]
                    }
                    else {
                        'Unknown'
                    }

                    $resultString = if ($resultCodeMap.ContainsKey($entry.ResultCode)) {
                        $resultCodeMap[$entry.ResultCode]
                    }
                    else {
                        'Unknown'
                    }

                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.WindowsUpdateHistory'
                        ComputerName   = $computer
                        Title          = $entry.Title
                        KBArticle      = $kbArticle
                        Operation      = $operationString
                        Result         = $resultString
                        Date           = $entry.Date
                        Description    = $entry.Description
                        SupportUrl     = $entry.SupportUrl
                        UpdateIdentity = $entry.UpdateIdentity
                        Timestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to retrieve update history from ${computer}: $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}