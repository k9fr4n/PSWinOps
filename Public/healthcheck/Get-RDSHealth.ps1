#Requires -Version 5.1
function Get-RDSHealth {
    <#
        .SYNOPSIS
            Retrieves Remote Desktop Services health status from one or more servers

        .DESCRIPTION
            Checks the health of Remote Desktop Services on target computers by inspecting
            TermService and SessionEnv services, RDS module availability, installed RD roles,
            active and disconnected sessions, and licensing configuration.
            Returns a single typed object per server with an overall health assessment.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-RDSHealth

            Checks RDS health on the local computer.

        .EXAMPLE
            Get-RDSHealth -ComputerName 'RDS01'

            Checks RDS health on a single remote server.

        .EXAMPLE
            'RDS01', 'RDS02' | Get-RDSHealth -Credential (Get-Credential)

            Checks RDS health on multiple servers via pipeline with alternate credentials.

        .OUTPUTS
            PSWinOps.RDSHealth
            Returns one object per server with service status, session counts,
            installed roles, licensing mode, and overall health assessment.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: Admin rights on target servers for full RDS enumeration

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/remotedesktop/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.RDSHealth')]
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
            $data = @{
                ServiceStatus        = 'NotFound'
                SessionEnvStatus     = 'NotFound'
                RDModuleAvailable    = $false
                InstalledRoles       = ''
                ActiveSessions       = 0
                DisconnectedSessions = 0
                LicensingMode        = 'Unknown'
            }

            $termSvc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
            if ($termSvc) { $data.ServiceStatus = $termSvc.Status.ToString() }

            $sessionEnv = Get-Service -Name 'SessionEnv' -ErrorAction SilentlyContinue
            if ($sessionEnv) { $data.SessionEnvStatus = $sessionEnv.Status.ToString() }

            $rdModule = Get-Module -Name 'RemoteDesktop' -ListAvailable -ErrorAction SilentlyContinue
            if ($rdModule) {
                $data.RDModuleAvailable = $true

                try {
                    $rdServers = Get-RDServer -ErrorAction Stop
                    $roleList = [System.Collections.Generic.List[string]]::new()
                    foreach ($rdServer in $rdServers) {
                        if ($rdServer.Server -eq $env:COMPUTERNAME) {
                            foreach ($role in $rdServer.Roles) { $roleList.Add($role) }
                        }
                    }
                    if ($roleList.Count -gt 0) { $data.InstalledRoles = $roleList -join ', ' }

                    try {
                        $rdSessions = Get-RDUserSession -ErrorAction Stop
                        foreach ($s in $rdSessions) {
                            if ($s.SessionState -eq 'STATE_ACTIVE') { $data.ActiveSessions++ }
                            elseif ($s.SessionState -eq 'STATE_DISCONNECTED') { $data.DisconnectedSessions++ }
                        }
                    }
                    catch { Write-Verbose -Message "RD user session query failed: $_" }

                    if ($roleList -contains 'RDS-LICENSING') {
                        try {
                            $licConfig = Get-RDLicenseConfiguration -ErrorAction Stop
                            $data.LicensingMode = if ($licConfig.Mode) { $licConfig.Mode.ToString() } else { 'NotConfigured' }
                        }
                        catch { $data.LicensingMode = 'Unknown' }
                    }
                }
                catch { Write-Verbose -Message "RemoteDesktop module import/query failed: $_" }
            }

            # Fallback: quser.exe for session counts on standalone hosts
            if ($data.ActiveSessions -eq 0 -and $data.DisconnectedSessions -eq 0) {
                try {
                    $quserOutput = quser.exe 2>$null
                    if ($quserOutput) {
                        $dataLines = $quserOutput | Select-Object -Skip 1
                        foreach ($line in $dataLines) {
                            if ($line -match '\bActive\b') { $data.ActiveSessions++ }
                            elseif ($line -match '\bDisc\b') { $data.DisconnectedSessions++ }
                        }
                    }
                }
                catch { Write-Verbose -Message "quser.exe fallback failed: $_" }
            }

            $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $isLocal = $localNames -contains $machine
                if ($isLocal) {
                    $result = & $scriptBlock
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
                    $result = Invoke-Command @invokeParams
                }

                $activeSessions = [int]$result.ActiveSessions
                $disconnectedSessions = [int]$result.DisconnectedSessions
                $totalSessions = $activeSessions + $disconnectedSessions

                if ([string]$result.ServiceStatus -eq 'NotFound') {
                    $healthStatus = 'RoleUnavailable'
                }
                elseif ([string]$result.ServiceStatus -ne 'Running' -or [string]$result.SessionEnvStatus -ne 'Running') {
                    $healthStatus = 'Critical'
                }
                elseif ($disconnectedSessions -gt $activeSessions -or [string]$result.LicensingMode -eq 'NotConfigured') {
                    $healthStatus = 'Degraded'
                }
                else {
                    $healthStatus = 'Healthy'
                }

                [PSCustomObject]@{
                    PSTypeName           = 'PSWinOps.RDSHealth'
                    ComputerName         = $displayName
                    ServiceName          = 'TermService'
                    ServiceStatus        = [string]$result.ServiceStatus
                    SessionEnvStatus     = [string]$result.SessionEnvStatus
                    RDModuleAvailable    = [bool]$result.RDModuleAvailable
                    InstalledRoles       = [string]$result.InstalledRoles
                    ActiveSessions       = $activeSessions
                    DisconnectedSessions = $disconnectedSessions
                    TotalSessions        = $totalSessions
                    LicensingMode        = [string]$result.LicensingMode
                    OverallHealth        = $healthStatus
                    Timestamp            = Get-Date -Format 'o'
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