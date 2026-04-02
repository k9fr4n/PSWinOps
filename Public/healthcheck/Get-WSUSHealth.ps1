#Requires -Version 5.1
function Get-WSUSHealth {
    <#
        .SYNOPSIS
            Retrieves WSUS server health and status information

        .DESCRIPTION
            Collects comprehensive health data from Windows Server Update Services (WSUS) servers.
            Checks service status, client statistics, database configuration, and content directory
            disk space to produce an overall health assessment per target machine.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-WSUSHealth

            Checks WSUS health on the local computer.

        .EXAMPLE
            Get-WSUSHealth -ComputerName 'WSUS01'

            Checks WSUS health on a single remote server.

        .EXAMPLE
            'WSUS01', 'WSUS02' | Get-WSUSHealth -Credential (Get-Credential)

            Checks WSUS health on multiple remote servers via pipeline with alternate credentials.

        .OUTPUTS
            PSWinOps.WSUSHealth
            Returns an object per target with service status, client statistics,
            database configuration, content directory space, and overall health.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: WSUS role (UpdateServices)
            Requires: Module UpdateServices

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/updateservices/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.WSUSHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $scriptBlock = {
            $serviceStatus = 'NotFound'
            $moduleAvailable = $false
            $wsusServerName = $null
            $wsusPort = 0
            $isSsl = $false
            $dbType = $null
            $totalClients = 0
            $clientsNeedingUpdates = 0
            $clientsWithErrors = 0
            $unapprovedUpdates = 0
            $contentDirPath = $null
            $contentDirFreeSpaceGB = [decimal]0

            try {
                $svc = Get-Service -Name 'WsusService' -ErrorAction Stop
                $serviceStatus = $svc.Status.ToString()
            }
            catch {
                $serviceStatus = 'NotFound'
            }

            $modCheck = Get-Module -Name 'UpdateServices' -ListAvailable -ErrorAction SilentlyContinue
            if ($modCheck) { $moduleAvailable = $true }

            if ($moduleAvailable -and $serviceStatus -eq 'Running') {
                try {
                    $wsusServer = Get-WsusServer
                    $wsusServerName = $wsusServer.ServerName
                    $wsusPort = $wsusServer.PortNumber
                    $isSsl = $wsusServer.UseSecureConnection

                    $wsusStatus = $wsusServer.GetStatus()
                    $totalClients = $wsusStatus.ComputerTargetCount
                    $clientsNeedingUpdates = $wsusStatus.ComputerTargetsNeedingUpdatesCount
                    $clientsWithErrors = $wsusStatus.ComputerTargetsWithUpdateErrorsCount
                    $unapprovedUpdates = $wsusStatus.NotApprovedUpdateCount

                    $dbConfig = $wsusServer.GetDatabaseConfiguration()
                    $dbType = if ($dbConfig.IsUsingWindowsInternalDatabase) { 'WID' } else { 'SQL' }

                    $regPath = 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup'
                    $contentDirPath = (Get-ItemProperty -Path $regPath -Name 'ContentDir' -ErrorAction Stop).ContentDir
                    $driveLetter = (Split-Path -Path $contentDirPath -Qualifier).TrimEnd(':')
                    $diskInfo = Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter "DeviceID='${driveLetter}:'" -ErrorAction Stop
                    $contentDirFreeSpaceGB = [math]::Round($diskInfo.FreeSpace / 1GB, 2)
                }
                catch {
                    Write-Warning -Message "Failed to collect WSUS data: $_"
                }
            }

            @{
                ServiceStatus         = $serviceStatus
                ModuleAvailable       = $moduleAvailable
                WSUSServerName        = $wsusServerName
                WSUSPort              = $wsusPort
                IsSSL                 = $isSsl
                DatabaseType          = $dbType
                TotalClients          = $totalClients
                ClientsNeedingUpdates = $clientsNeedingUpdates
                ClientsWithErrors     = $clientsWithErrors
                UnapprovedUpdates     = $unapprovedUpdates
                ContentDirPath        = $contentDirPath
                ContentDirFreeSpaceGB = $contentDirFreeSpaceGB
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $data = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                if (-not $data.ModuleAvailable) {
                    $healthStatus = 'RoleUnavailable'
                }
                elseif ($data.ServiceStatus -ne 'Running' -or $data.ClientsWithErrors -gt 0 -or $data.ContentDirFreeSpaceGB -lt 5) {
                    $healthStatus = 'Critical'
                }
                elseif (($data.TotalClients -gt 0 -and $data.ClientsNeedingUpdates -gt ($data.TotalClients * 0.3)) -or
                        $data.ContentDirFreeSpaceGB -lt 20 -or $data.UnapprovedUpdates -gt 100) {
                    $healthStatus = 'Degraded'
                }
                else {
                    $healthStatus = 'Healthy'
                }

                [PSCustomObject]@{
                    PSTypeName            = 'PSWinOps.WSUSHealth'
                    ComputerName          = $displayName
                    ServiceName           = 'WsusService'
                    ServiceStatus         = $data.ServiceStatus
                    WSUSServerName        = $data.WSUSServerName
                    WSUSPort              = [int]$data.WSUSPort
                    IsSSL                 = [bool]$data.IsSSL
                    DatabaseType          = $data.DatabaseType
                    TotalClients          = [int]$data.TotalClients
                    ClientsNeedingUpdates = [int]$data.ClientsNeedingUpdates
                    ClientsWithErrors     = [int]$data.ClientsWithErrors
                    UnapprovedUpdates     = [int]$data.UnapprovedUpdates
                    ContentDirPath        = $data.ContentDirPath
                    ContentDirFreeSpaceGB = [decimal]$data.ContentDirFreeSpaceGB
                    OverallHealth         = $healthStatus
                    Timestamp             = Get-Date -Format 'o'
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