#Requires -Version 5.1
function Get-IISCurrentRequest {
    <#
        .SYNOPSIS
            Lists HTTP requests currently executing in IIS (typed equivalent of `appcmd list requests`).

        .DESCRIPTION
            Enumerates every request actively being processed by IIS worker processes
            on one or more target servers, joining each entry with the owning
            application pool, the served site, the absolute URL, HTTP verb, client IP,
            elapsed time and pipeline state. Provides real-time visibility on stuck or
            long-running requests -- diagnostic data that the IISAdministration module
            does not expose. Implementation parses `appcmd.exe list requests /xml`
            inside a remoting-aware scriptblock dispatched through Invoke-RemoteOrLocal.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER AppPoolName
            Restrict the result set to requests served by one or more named
            application pools. Wildcards accepted via -like.

        .PARAMETER SiteName
            Restrict the result set to requests targeting one or more named IIS
            sites. Wildcards accepted via -like.

        .PARAMETER MinElapsedMs
            Return only requests whose TimeElapsedMs is greater than or equal to
            this threshold. Handy to surface stuck or long-running requests.

        .EXAMPLE
            Get-IISCurrentRequest

            Returns all in-flight HTTP requests on the local IIS instance.

        .EXAMPLE
            Get-IISCurrentRequest -ComputerName 'WEB01'

            Returns in-flight requests from a single remote server.

        .EXAMPLE
            'WEB01','WEB02' | Get-IISCurrentRequest -Credential (Get-Credential)

            Queries multiple remote servers via pipeline with alternate credentials.

        .EXAMPLE
            Get-IISCurrentRequest -MinElapsedMs 5000 | Sort-Object TimeElapsedMs -Descending

            Surfaces stuck requests running for more than 5 seconds, sorted by elapsed time.

        .EXAMPLE
            Get-IISCurrentRequest -SiteName 'www.contoso.com' -AppPoolName 'API*'

            Filters in-flight requests to a specific site and application pool pattern.

        .OUTPUTS
            PSCustomObject (PSTypeName='PSWinOps.IISCurrentRequest')

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-05-15
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role
            Requires: IIS Management Scripts and Tools feature (for appcmd.exe)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/iis/get-started/getting-started-with-iis/getting-started-with-appcmdexe#list-the-currently-executing-requests
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISCurrentRequest')]
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

        [Parameter(Mandatory = $false)]
        [string[]]$AppPoolName,

        [Parameter(Mandatory = $false)]
        [string[]]$SiteName,

        [Parameter(Mandatory = $false)]
        [int]$MinElapsedMs
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            param(
                [string[]]$FilterAppPool,
                [string[]]$FilterSite,
                [int]$FilterMinElapsedMs
            )

            $results = [System.Collections.Generic.List[hashtable]]::new()
            $ts      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            # -- 1. Verify IIS (W3SVC) presence
            try {
                $null = Get-Service -Name 'W3SVC' -ErrorAction Stop
            }
            catch {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'IISNotInstalled'
                    ErrorMessage    = "W3SVC service not found: $($_.Exception.Message)"
                    Timestamp       = $ts
                })
                return $results
            }

            # -- 2. Verify appcmd.exe presence
            $appcmdExe = Join-Path -Path $env:windir -ChildPath 'system32\inetsrv\appcmd.exe'
            if (-not (Test-Path -LiteralPath $appcmdExe -PathType Leaf)) {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'AppcmdMissing'
                    ErrorMessage    = "appcmd.exe not found at '$appcmdExe'. Install the IIS Management Scripts and Tools feature."
                    Timestamp       = $ts
                })
                return $results
            }

            # -- 3. Query in-flight requests via appcmd /xml
            $rawXml = $null
            try {
                $rawXml = & $appcmdExe list requests /xml 2>$null
            }
            catch {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'Failed'
                    ErrorMessage    = "appcmd.exe execution failed: $($_.Exception.Message)"
                    Timestamp       = $ts
                })
                return $results
            }

            if ([string]::IsNullOrWhiteSpace($rawXml)) {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'NoRequests'
                    ErrorMessage    = $null
                    Timestamp       = $ts
                })
                return $results
            }

            # -- 4. Parse XML
            try {
                [xml]$doc = $rawXml
            }
            catch {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'Failed'
                    ErrorMessage    = "Failed to parse appcmd XML output: $($_.Exception.Message)"
                    Timestamp       = $ts
                })
                return $results
            }

            $requestNodes = @($doc.appcmd.REQUEST)
            if ($requestNodes.Count -eq 0 -or ($requestNodes.Count -eq 1 -and $null -eq $requestNodes[0])) {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'NoRequests'
                    ErrorMessage    = $null
                    Timestamp       = $ts
                })
                return $results
            }

            # -- 5. Valid pipeline state values
            $validStates = [System.Collections.Generic.HashSet[string]] @(
                'BeginRequest', 'AuthenticateRequest', 'AuthorizeRequest',
                'ResolveRequestCache', 'MapRequestHandler', 'AcquireRequestState',
                'PreExecuteRequestHandler', 'ExecuteRequestHandler',
                'ReleaseRequestState', 'UpdateRequestCache', 'LogRequest',
                'EndRequest', 'SendResponse'
            )

            # -- 6. Build result rows
            $matchedAny = $false
            foreach ($req in $requestNodes) {
                if ($null -eq $req) { continue }

                $poolName  = $req.'APPPOOL.NAME'
                $site      = $req.'SITE.NAME'
                $elapsedMs = [long]$req.'TIME.ELAPSED'
                $pipeRaw   = $req.'PIPELINE_STATE'

                $pipelineState = if ($validStates.Contains($pipeRaw)) { $pipeRaw } else { 'Unknown' }

                # Caller-side filtering
                if ($FilterAppPool -and $FilterAppPool.Count -gt 0) {
                    $poolMatch = $false
                    foreach ($pat in $FilterAppPool) {
                        if ($poolName -like $pat) { $poolMatch = $true; break }
                    }
                    if (-not $poolMatch) { continue }
                }

                if ($FilterSite -and $FilterSite.Count -gt 0) {
                    $siteMatch = $false
                    foreach ($pat in $FilterSite) {
                        if ($site -like $pat) { $siteMatch = $true; break }
                    }
                    if (-not $siteMatch) { continue }
                }

                if ($FilterMinElapsedMs -gt 0 -and $elapsedMs -lt $FilterMinElapsedMs) { continue }

                $matchedAny = $true
                $results.Add(@{
                    ProcessId       = if ($req.'WORKER_PROCESS.PID') { [int]$req.'WORKER_PROCESS.PID' } else { $null }
                    AppPoolName     = $poolName
                    SiteName        = $site
                    Url             = $req.URL
                    Verb            = $req.VERB
                    ClientIPAddress = $req.CLIENTIP
                    TimeElapsed     = [System.TimeSpan]::FromMilliseconds($elapsedMs)
                    TimeElapsedMs   = $elapsedMs
                    PipelineState   = $pipelineState
                    Status          = 'InFlight'
                    ErrorMessage    = $null
                    Timestamp       = $ts
                })
            }

            if (-not $matchedAny) {
                $results.Add(@{
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'NoRequests'
                    ErrorMessage    = $null
                    Timestamp       = $ts
                })
            }

            return $results
        }
    }

    process {
        foreach ($cn in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '$cn'"

            try {
                $invokeParams = @{
                    ComputerName = $cn
                    ScriptBlock  = $scriptBlock
                    ArgumentList = @($AppPoolName, $SiteName, $MinElapsedMs)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawResults = Invoke-RemoteOrLocal @invokeParams
            }
            catch {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.IISCurrentRequest'
                    ComputerName    = $cn
                    ProcessId       = $null
                    AppPoolName     = $null
                    SiteName        = $null
                    Url             = $null
                    Verb            = $null
                    ClientIPAddress = $null
                    TimeElapsed     = $null
                    TimeElapsedMs   = $null
                    PipelineState   = $null
                    Status          = 'Failed'
                    ErrorMessage    = $_.Exception.Message
                    Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
                continue
            }

            foreach ($row in $rawResults) {
                [PSCustomObject]@{
                    PSTypeName      = 'PSWinOps.IISCurrentRequest'
                    ComputerName    = $cn
                    ProcessId       = $row.ProcessId
                    AppPoolName     = $row.AppPoolName
                    SiteName        = $row.SiteName
                    Url             = $row.Url
                    Verb            = $row.Verb
                    ClientIPAddress = $row.ClientIPAddress
                    TimeElapsed     = $row.TimeElapsed
                    TimeElapsedMs   = $row.TimeElapsedMs
                    PipelineState   = $row.PipelineState
                    Status          = $row.Status
                    ErrorMessage    = $row.ErrorMessage
                    Timestamp       = $row.Timestamp
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Done"
    }
}
