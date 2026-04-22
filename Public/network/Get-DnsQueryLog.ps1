#Requires -Version 5.1

function Get-DnsQueryLog {
    <#
        .SYNOPSIS
            Retrieves DNS query events from the Windows DNS Client ETW operational log

        .DESCRIPTION
            Parses the Microsoft-Windows-DNS-Client/Operational event log to extract
            DNS query and response data. Returns structured objects with query name,
            type, result, response time, and originating process information.
            The DNS Client operational log must be enabled for events to be recorded.
            Use the -EnableLog switch to activate it automatically (requires admin).

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER MaxEvents
            Maximum number of DNS events to return. Valid range 1-10000. Defaults to 100.

        .PARAMETER DomainFilter
            Filter results by domain name. Supports wildcards (e.g. '*.google.com').

        .PARAMETER QueryType
            Filter results by DNS record type (A, AAAA, CNAME, MX, NS, PTR, SOA, SRV, TXT).

        .PARAMETER Since
            Only return events after this date/time. Useful for narrowing results to
            a specific time window.

        .PARAMETER EnableLog
            When specified, enables the DNS Client operational log if it is not already
            active. Requires administrator privileges.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.

        .EXAMPLE
            Get-DnsQueryLog

            Returns the 100 most recent DNS queries on the local machine.

        .EXAMPLE
            Get-DnsQueryLog -ComputerName 'SRV01' -MaxEvents 500 -Since (Get-Date).AddHours(-1)

            Returns up to 500 DNS queries from the last hour on SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-DnsQueryLog -DomainFilter '*.microsoft.com' -QueryType A

            Returns DNS A-record queries for Microsoft domains on two servers via pipeline.

        .OUTPUTS
            PSWinOps.DnsQueryLog
            Returns objects with QueryName, QueryType, Result, ProcessName, ProcessId,
            ResponseCode, ComputerName, and Timestamp.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-13
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (to enable log or read remote event logs)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/etw/event-tracing-portal
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.DnsQueryLog')]
    param(
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 100,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string]$DomainFilter,

        [Parameter(Mandatory = $false)]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SOA', 'SRV', 'TXT', 'ANY')]
        [string]$QueryType,

        [Parameter(Mandatory = $false)]
        [datetime]$Since,

        [Parameter(Mandatory = $false)]
        [switch]$EnableLog,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $dnsLogName = 'Microsoft-Windows-DNS-Client/Operational'

        # DNS record type mapping (RFC 1035 + extensions)
        $queryTypeMap = @{
            1 = 'A';     2 = 'NS';    5 = 'CNAME';  6 = 'SOA'
            12 = 'PTR';  15 = 'MX';   16 = 'TXT';   28 = 'AAAA'
            33 = 'SRV';  35 = 'NAPTR'; 43 = 'DS';   48 = 'DNSKEY'
            64 = 'SVCB'; 65 = 'HTTPS'; 255 = 'ANY'; 257 = 'CAA'
        }

        # Reverse map for filtering by type name
        $typeNameToId = @{}
        foreach ($kv in $queryTypeMap.GetEnumerator()) {
            $typeNameToId[$kv.Value] = $kv.Key
        }

        $enableBlock = {
            param([string]$LogName)
            $log = Get-WinEvent -ListLog $LogName -ErrorAction Stop
            if (-not $log.IsEnabled) {
                $log.IsEnabled = $true
                $log.SaveChanges()
            }
            $log.IsEnabled
        }

        $queryBlock = {
            param(
                [string]$LogName,
                [int]$Max,
                [string]$SinceStr
            )

            $filterHash = @{
                LogName = $LogName
                Id      = @(3006, 3008, 3020)
            }
            if ($SinceStr -ne '') {
                $filterHash['StartTime'] = [datetime]::Parse($SinceStr)
            }

            $events = @(Get-WinEvent -FilterHashtable $filterHash -MaxEvents $Max -ErrorAction SilentlyContinue)

            $results = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($evt in $events) {
                $xml = [xml]$evt.ToXml()
                $eventData = @{}
                foreach ($data in $xml.Event.EventData.Data) {
                    $eventData[$data.Name] = $data.'#text'
                }

                $processId = 0
                $execNode = $xml.Event.System.Execution
                if ($execNode -and $execNode.ProcessID) {
                    $processId = [int]$execNode.ProcessID
                }

                $processName = ''
                if ($processId -gt 0) {
                    try {
                        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                        if ($proc) { $processName = $proc.ProcessName }
                    }
                    catch { Write-Verbose -Message "Could not resolve PID $processId" }
                }

                $results.Add(@{
                    TimeCreated  = $evt.TimeCreated.ToString('o')
                    EventId      = $evt.Id
                    QueryName    = $eventData['QueryName']
                    QueryType    = if ($eventData['QueryType']) { [int]$eventData['QueryType'] } else { 0 }
                    QueryResults = $eventData['QueryResults']
                    QueryStatus  = if ($eventData['QueryStatus']) { [int]$eventData['QueryStatus'] } else { -1 }
                    ProcessId    = $processId
                    ProcessName  = $processName
                })
            }

            @($results)
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$machine'"

            try {
                # Enable log if requested
                if ($EnableLog.IsPresent) {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] Enabling DNS Client log on '$machine'"
                    $enableParams = @{
                        ComputerName = $machine
                        ScriptBlock  = $enableBlock
                        ArgumentList = @($dnsLogName)
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $enableParams['Credential'] = $Credential
                    }
                    try {
                        Invoke-RemoteOrLocal @enableParams | Out-Null
                    }
                    catch {
                        Write-Warning -Message "[$($MyInvocation.MyCommand)] Could not enable DNS Client log on '${machine}': $_"
                    }
                }

                # Query events
                $sinceStr = if ($PSBoundParameters.ContainsKey('Since')) { $Since.ToString('o') } else { '' }
                $invokeParams = @{
                    ComputerName = $machine
                    ScriptBlock  = $queryBlock
                    ArgumentList = @($dnsLogName, $MaxEvents, $sinceStr)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawEvents = @(Invoke-RemoteOrLocal @invokeParams)
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }

            foreach ($evt in $rawEvents) {
                if ($null -eq $evt -or $evt -isnot [hashtable]) { continue }

                $queryName = $evt.QueryName
                if ([string]::IsNullOrWhiteSpace($queryName)) { continue }

                # Clean trailing dot from FQDN
                $queryName = $queryName.TrimEnd('.')

                # Map numeric type to name
                $typeId   = [int]$evt.QueryType
                $typeName = if ($queryTypeMap.ContainsKey($typeId)) { $queryTypeMap[$typeId] } else { "TYPE$typeId" }

                # Filter by QueryType
                if ($PSBoundParameters.ContainsKey('QueryType') -and $typeName -ne $QueryType) { continue }

                # Filter by domain
                if ($PSBoundParameters.ContainsKey('DomainFilter') -and $queryName -notlike $DomainFilter) { continue }

                # Parse results — semicolons separate multiple answers
                $resultStr = if ($evt.QueryResults) {
                    ($evt.QueryResults -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join ', '
                }
                else {
                    ''
                }

                # Map status code
                $statusCode = [int]$evt.QueryStatus
                $status = switch ($statusCode) {
                    0       { 'Success' }
                    9003    { 'NameNotFound' }
                    9501    { 'Timeout' }
                    1460    { 'Timeout' }
                    default { if ($statusCode -gt 0) { "Error($statusCode)" } else { 'Unknown' } }
                }

                [PSCustomObject]@{
                    PSTypeName   = 'PSWinOps.DnsQueryLog'
                    ComputerName = $machine
                    TimeCreated  = [datetime]::Parse($evt.TimeCreated)
                    QueryName    = $queryName
                    QueryType    = $typeName
                    Result       = $resultStr
                    Status       = $status
                    ProcessName  = $evt.ProcessName
                    ProcessId    = $evt.ProcessId
                    EventId      = $evt.EventId
                    Timestamp    = Get-Date -Format 'o'
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}