#Requires -Version 5.1
function Get-ExchangeServerHealth {
    <#
        .SYNOPSIS
            Checks Exchange Server health on Windows servers

        .DESCRIPTION
            Retrieves comprehensive Exchange Server health information including service status,
            mailbox database mount status, mail queue lengths, DAG database copy health,
            and certificate expiry. Returns a single typed object per server with an overall
            health assessment suitable for dashboards and alerting pipelines.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .PARAMETER QueueWarningThreshold
            Number of messages in a single queue that triggers a Degraded health status.
            Defaults to 100.

        .PARAMETER QueueCriticalThreshold
            Number of messages in a single queue that triggers a Critical health status.
            Defaults to 500.

        .PARAMETER CertificateWarningDays
            Number of days before certificate expiry that triggers a Degraded health status.
            Defaults to 30.

        .EXAMPLE
            Get-ExchangeServerHealth

            Checks Exchange Server health on the local machine using default thresholds.

        .EXAMPLE
            Get-ExchangeServerHealth -ComputerName 'EX01' -QueueWarningThreshold 50

            Checks Exchange Server health on a single remote server with a custom queue warning threshold.

        .EXAMPLE
            'EX01', 'EX02' | Get-ExchangeServerHealth -Credential (Get-Credential)

            Checks Exchange Server health on multiple remote servers via pipeline with alternate credentials.

        .OUTPUTS
            PSWinOps.ExchangeServerHealth
            Returns one object per server with Exchange service statuses, database counts,
            queue metrics, DAG copy health, certificate expiry counts, and overall health.

        .NOTES
            Author: Franck SALLET
            Version: 1.1.0
            Last Modified: 2026-04-02
            Requires: PowerShell 5.1+ / Windows only
            Requires: Exchange Server 2016+ Management Tools
            Requires: Module ExchangeManagementShell

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/exchange/exchange-management-shell
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ExchangeServerHealth')]
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
        [ValidateRange(1, 10000)]
        [int]$QueueWarningThreshold = 100,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100000)]
        [int]$QueueCriticalThreshold = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 365)]
        [int]$CertificateWarningDays = 30
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            param($certWarnDays)

            $data = @{
                TransportStatus          = 'NotFound'
                InformationStoreStatus   = 'NotFound'
                ADTopologyStatus         = 'NotFound'
                ServiceHostStatus        = 'NotFound'
                SnapinAvailable          = $false
                TotalDatabases           = 0
                MountedDatabases         = 0
                DismountedDatabases      = 0
                TotalQueues              = 0
                TotalQueueMessages       = 0
                HighestQueueLength       = 0
                DAGCopiesTotal           = 0
                DAGCopiesHealthy         = 0
                DAGCopiesUnhealthy       = 0
                CertificatesTotal        = 0
                CertificatesExpiringSoon = 0
                CertificatesExpired      = 0
            }

            # Check Exchange services
            $exchangeServices = @{
                'MSExchangeTransport'   = 'TransportStatus'
                'MSExchangeIS'          = 'InformationStoreStatus'
                'MSExchangeADTopology'  = 'ADTopologyStatus'
                'MSExchangeServiceHost' = 'ServiceHostStatus'
            }
            foreach ($svcName in $exchangeServices.Keys) {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc) {
                    $data[$exchangeServices[$svcName]] = $svc.Status.ToString()
                }
            }

            # Try loading Exchange Management Shell
            # Add-PSSnapin is Desktop-edition only; on PS 7 Core skip straight to Import-Module
            if ($PSVersionTable.PSEdition -ne 'Core') {
                try {
                    Add-PSSnapin -Name 'Microsoft.Exchange.Management.PowerShell.SnapIn' -ErrorAction Stop
                    $data.SnapinAvailable = $true
                }
                catch {
                    # Snapin not registered — fall through to Import-Module
                }
            }

            if (-not $data.SnapinAvailable) {
                try {
                    Import-Module -Name 'ExchangeManagementShell' -ErrorAction Stop
                    $data.SnapinAvailable = $true
                }
                catch {
                    $data.SnapinAvailable = $false
                }
            }

            if ($data.SnapinAvailable) {
                # Mailbox databases
                $databases = Get-MailboxDatabase -Status -ErrorAction SilentlyContinue
                if ($databases) {
                    $data.TotalDatabases     = @($databases).Count
                    $data.MountedDatabases   = @($databases | Where-Object { $_.Mounted -eq $true }).Count
                    $data.DismountedDatabases = $data.TotalDatabases - $data.MountedDatabases
                }

                # Mail queues
                $queues = Get-Queue -ErrorAction SilentlyContinue
                if ($queues) {
                    $data.TotalQueues        = @($queues).Count
                    $data.TotalQueueMessages = ($queues | Measure-Object -Property MessageCount -Sum).Sum
                    $data.HighestQueueLength = ($queues | Measure-Object -Property MessageCount -Maximum).Maximum
                }

                # DAG database copy status
                $copies = Get-MailboxDatabaseCopyStatus -ErrorAction SilentlyContinue
                if ($copies) {
                    $data.DAGCopiesTotal     = @($copies).Count
                    $healthyCopyStatuses     = @('Mounted', 'Healthy')
                    $data.DAGCopiesHealthy   = @($copies | Where-Object { $_.Status -in $healthyCopyStatuses }).Count
                    $data.DAGCopiesUnhealthy = $data.DAGCopiesTotal - $data.DAGCopiesHealthy
                }

                # Exchange certificates
                $certs = Get-ExchangeCertificate -ErrorAction SilentlyContinue
                if ($certs) {
                    $now = Get-Date
                    $data.CertificatesTotal       = @($certs).Count
                    $data.CertificatesExpired     = @($certs | Where-Object { $_.NotAfter -lt $now }).Count
                    $data.CertificatesExpiringSoon = @($certs | Where-Object {
                        $_.NotAfter -ge $now -and $_.NotAfter -lt $now.AddDays($certWarnDays)
                    }).Count
                }
            }

            $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $result = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock `
                    -Credential $Credential `
                    -ArgumentList @($CertificateWarningDays)

                # Compute OverallHealth outside the scriptblock
                if (-not $result.SnapinAvailable) {
                    $healthStatus = 'RoleUnavailable'
                }
                elseif (
                    $result.TransportStatus -ne 'Running' -or
                    $result.InformationStoreStatus -ne 'Running' -or
                    $result.DismountedDatabases -gt 0 -or
                    $result.HighestQueueLength -ge $QueueCriticalThreshold
                ) {
                    $healthStatus = 'Critical'
                }
                elseif (
                    $result.HighestQueueLength -ge $QueueWarningThreshold -or
                    $result.DAGCopiesUnhealthy -gt 0 -or
                    $result.CertificatesExpiringSoon -gt 0 -or
                    $result.CertificatesExpired -gt 0 -or
                    $result.ADTopologyStatus -ne 'Running' -or
                    $result.ServiceHostStatus -ne 'Running'
                ) {
                    $healthStatus = 'Degraded'
                }
                else {
                    $healthStatus = 'Healthy'
                }

                [PSCustomObject]@{
                    PSTypeName               = 'PSWinOps.ExchangeServerHealth'
                    ComputerName             = $displayName
                    TransportStatus          = $result.TransportStatus
                    InformationStoreStatus   = $result.InformationStoreStatus
                    ADTopologyStatus         = $result.ADTopologyStatus
                    ServiceHostStatus        = $result.ServiceHostStatus
                    TotalDatabases           = [int]$result.TotalDatabases
                    MountedDatabases         = [int]$result.MountedDatabases
                    DismountedDatabases      = [int]$result.DismountedDatabases
                    TotalQueues              = [int]$result.TotalQueues
                    TotalQueueMessages       = [int]$result.TotalQueueMessages
                    HighestQueueLength       = [int]$result.HighestQueueLength
                    DAGCopiesTotal           = [int]$result.DAGCopiesTotal
                    DAGCopiesHealthy         = [int]$result.DAGCopiesHealthy
                    DAGCopiesUnhealthy       = [int]$result.DAGCopiesUnhealthy
                    CertificatesTotal        = [int]$result.CertificatesTotal
                    CertificatesExpiringSoon = [int]$result.CertificatesExpiringSoon
                    CertificatesExpired      = [int]$result.CertificatesExpired
                    OverallHealth            = $healthStatus
                    Timestamp                = Get-Date -Format 'o'
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
