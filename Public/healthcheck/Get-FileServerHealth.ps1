#Requires -Version 5.1
function Get-FileServerHealth {
    <#
        .SYNOPSIS
            Retrieves file server health metrics from local or remote servers

        .DESCRIPTION
            Collects comprehensive file server health data including the LanmanServer
            service status, non-administrative share count, open SMB sessions and files,
            FSRM quota statistics, and minimum free disk space across shared drives.
            Returns a single typed object per server with an overall health assessment.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-FileServerHealth

            Queries the local file server and returns health metrics.

        .EXAMPLE
            Get-FileServerHealth -ComputerName 'FS01'

            Queries the remote file server FS01 and returns its health metrics.

        .EXAMPLE
            'FS01', 'FS02' | Get-FileServerHealth -Credential (Get-Credential)

            Queries multiple remote file servers via pipeline with explicit credentials.

        .OUTPUTS
            PSWinOps.FileServerHealth
            Returns one object per server containing service status, share counts,
            SMB sessions, FSRM quotas, disk space, and overall health assessment.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: Run As Administrator for SMB and FSRM cmdlets

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/smbshare/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.FileServerHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')

        $scriptBlock = {
            $svcStatus = 'Unknown'
            $roleAvailable = $true
            $totalShares = 0
            $openSessions = 0
            $openFiles = 0
            $fsrmAvailable = $false
            $totalQuotas = 0
            $quotasNearLimit = 0
            $minShareDiskFreeGB = $null

            try {
                $svc = Get-Service -Name 'LanmanServer' -ErrorAction Stop
                $svcStatus = $svc.Status.ToString()
            }
            catch {
                $roleAvailable = $false
            }

            if ($roleAvailable) {
                $userShareList = @()
                try {
                    $allShares = @(Get-SmbShare -ErrorAction Stop)
                    $userShareList = @($allShares | Where-Object -FilterScript { -not $_.Special })
                    $totalShares = $userShareList.Count
                }
                catch { }

                try { $openSessions = @(Get-SmbSession -ErrorAction Stop).Count } catch { }
                try { $openFiles = @(Get-SmbOpenFile -ErrorAction Stop).Count } catch { }

                $fsrmModule = Get-Module -Name 'FileServerResourceManager' -ListAvailable -ErrorAction SilentlyContinue
                if ($fsrmModule) {
                    $fsrmAvailable = $true
                    try {
                        Import-Module -Name 'FileServerResourceManager' -ErrorAction Stop
                        $quotaList = @(Get-FsrmQuota -ErrorAction Stop)
                        $totalQuotas = $quotaList.Count
                        foreach ($quota in $quotaList) {
                            if ($quota.Size -gt 0 -and ($quota.Usage / $quota.Size) -gt 0.9) {
                                $quotasNearLimit++
                            }
                        }
                    }
                    catch { }
                }

                if ($userShareList.Count -gt 0) {
                    $driveIndex = @{}
                    foreach ($share in $userShareList) {
                        $sharePath = $share.Path
                        if ($sharePath.Length -ge 2 -and $sharePath.Substring(1, 1) -eq ':') {
                            $driveLetter = $sharePath.Substring(0, 1).ToUpper()
                            $driveIndex[$driveLetter] = $true
                        }
                    }
                    if ($driveIndex.Count -gt 0) {
                        try {
                            $filterParts = foreach ($dl in $driveIndex.Keys) { "DeviceID='${dl}:'" }
                            $wmiFilter = $filterParts -join ' OR '
                            $diskList = @(Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter $wmiFilter -ErrorAction Stop)
                            $lowestFree = $null
                            foreach ($disk in $diskList) {
                                $freeGB = [decimal]([math]::Round(($disk.FreeSpace / 1GB), 2))
                                if ($null -eq $lowestFree -or $freeGB -lt $lowestFree) { $lowestFree = $freeGB }
                            }
                            $minShareDiskFreeGB = $lowestFree
                        }
                        catch { }
                    }
                }
            }

            @{
                ServiceStatus      = $svcStatus
                RoleAvailable      = $roleAvailable
                TotalShares        = $totalShares
                OpenSessions       = $openSessions
                OpenFiles          = $openFiles
                FSRMAvailable      = $fsrmAvailable
                TotalQuotas        = $totalQuotas
                QuotasNearLimit    = $quotasNearLimit
                MinShareDiskFreeGB = $minShareDiskFreeGB
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $isLocal = $localNames -contains $machine
                if ($isLocal) {
                    $data = & $scriptBlock
                }
                else {
                    $invokeParams = @{
                        ComputerName = $machine
                        ScriptBlock  = $scriptBlock
                        ErrorAction  = 'Stop'
                    }
                    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $data = Invoke-Command @invokeParams
                }

                $overallHealth = if (-not $data.RoleAvailable) { 'RoleUnavailable' }
                elseif ($data.ServiceStatus -ne 'Running' -or
                        ($null -ne $data.MinShareDiskFreeGB -and $data.MinShareDiskFreeGB -lt 5)) { 'Critical' }
                elseif ($data.QuotasNearLimit -gt 0 -or
                        ($null -ne $data.MinShareDiskFreeGB -and $data.MinShareDiskFreeGB -lt 20)) { 'Degraded' }
                else { 'Healthy' }

                [PSCustomObject]@{
                    PSTypeName         = 'PSWinOps.FileServerHealth'
                    ComputerName       = $displayName
                    ServiceName        = 'LanmanServer'
                    ServiceStatus      = [string]$data.ServiceStatus
                    TotalShares        = [int]$data.TotalShares
                    OpenSessions       = [int]$data.OpenSessions
                    OpenFiles          = [int]$data.OpenFiles
                    FSRMAvailable      = [bool]$data.FSRMAvailable
                    TotalQuotas        = [int]$data.TotalQuotas
                    QuotasNearLimit    = [int]$data.QuotasNearLimit
                    MinShareDiskFreeGB = if ($null -ne $data.MinShareDiskFreeGB) { [decimal]$data.MinShareDiskFreeGB } else { $null }
                    OverallHealth      = $overallHealth
                    Timestamp          = Get-Date -Format 'o'
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