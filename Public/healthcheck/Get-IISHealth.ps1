#Requires -Version 5.1
function Get-IISHealth {
    <#
        .SYNOPSIS
            Retrieves IIS Web Server health status for one or more computers

        .DESCRIPTION
            Checks the health of IIS Web Server components including the W3SVC service,
            individual site states, application pool states, and binding configurations.
            Returns one object per IIS site with an overall health assessment.
            Supports local and remote execution via WinRM with graceful fallback
            to CIM when IIS PowerShell modules are unavailable.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-IISHealth

            Checks IIS health on the local computer and returns one object per site.

        .EXAMPLE
            Get-IISHealth -ComputerName 'WEB01'

            Checks IIS health on a single remote server.

        .EXAMPLE
            'WEB01', 'WEB02' | Get-IISHealth -Credential (Get-Credential)

            Checks IIS health on multiple remote servers via pipeline with alternate credentials.

        .OUTPUTS
            PSWinOps.IISHealth
            Returns one object per IIS site with service status, site state,
            app pool state, bindings, physical path, and overall health assessment.

        .NOTES
            Author: Franck SALLET
            Version: 1.1.0
            Last Modified: 2026-03-31
            Requires: PowerShell 5.1+ / Windows only
            Requires: Web-Server (IIS) role
            Requires: Module WebAdministration or IISAdministration

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/webadministration/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.IISHealth')]
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
            $siteResults = [System.Collections.Generic.List[hashtable]]::new()

            # Check W3SVC service
            $w3svcStatus = 'NotInstalled'
            try {
                $w3svc = Get-Service -Name 'W3SVC' -ErrorAction Stop
                $w3svcStatus = $w3svc.Status.ToString()
            }
            catch {
                $siteResults.Add(@{
                    ServiceStatus = 'NotInstalled'
                    SiteName      = 'N/A'
                    SiteState     = 'N/A'
                    Bindings      = 'N/A'
                    PhysicalPath  = 'N/A'
                    AppPoolName   = 'N/A'
                    AppPoolState  = 'N/A'
                })
                return $siteResults
            }

            # Determine available IIS module
            $iisModule = $null
            if (Get-Module -Name 'WebAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'WebAdministration'
            }
            elseif (Get-Module -Name 'IISAdministration' -ListAvailable -ErrorAction SilentlyContinue) {
                $iisModule = 'IISAdministration'
            }

            # Collect site data
            $sitesData = $null

            if ($iisModule -eq 'WebAdministration') {
                try {
                    Import-Module -Name 'WebAdministration' -ErrorAction Stop

                    # Build app pool state index
                    $appPoolIndex = @{}
                    foreach ($pool in (Get-ChildItem -Path 'IIS:\AppPools' -ErrorAction SilentlyContinue)) {
                        $poolState = 'Unknown'
                        try {
                            $poolState = (Get-WebAppPoolState -Name $pool.Name -ErrorAction Stop).Value
                        }
                        catch { $poolState = 'Unknown' }
                        $appPoolIndex[$pool.Name] = $poolState
                    }

                    $sitesData = [System.Collections.Generic.List[hashtable]]::new()
                    foreach ($site in (Get-Website -ErrorAction Stop)) {
                        $bindingStrings = [System.Collections.Generic.List[string]]::new()
                        foreach ($binding in $site.Bindings.Collection) {
                            $bindingStrings.Add("$($binding.protocol) $($binding.bindingInformation)")
                        }

                        $poolName  = $site.applicationPool
                        $poolState = if ($appPoolIndex.ContainsKey($poolName)) { $appPoolIndex[$poolName] } else { 'Unknown' }

                        $sitesData.Add(@{
                            SiteName     = $site.Name
                            SiteState    = $site.State
                            Bindings     = ($bindingStrings -join ', ')
                            PhysicalPath = $site.physicalPath
                            AppPoolName  = $poolName
                            AppPoolState = $poolState
                        })
                    }
                }
                catch { $sitesData = $null }
            }
            elseif ($iisModule -eq 'IISAdministration') {
                try {
                    Import-Module -Name 'IISAdministration' -ErrorAction Stop

                    $appPoolIndex = @{}
                    foreach ($pool in (Get-IISAppPool -ErrorAction Stop)) {
                        $appPoolIndex[$pool.Name] = $pool.State.ToString()
                    }

                    $sitesData = [System.Collections.Generic.List[hashtable]]::new()
                    foreach ($site in (Get-IISSite -ErrorAction Stop)) {
                        $bindingStrings = [System.Collections.Generic.List[string]]::new()
                        foreach ($binding in $site.Bindings) {
                            $bindingStrings.Add("$($binding.Protocol) $($binding.BindingInformation)")
                        }

                        $poolName  = $site.Applications['/'].ApplicationPoolName
                        $poolState = if ($appPoolIndex.ContainsKey($poolName)) { $appPoolIndex[$poolName] } else { 'Unknown' }

                        $sitesData.Add(@{
                            SiteName     = $site.Name
                            SiteState    = $site.State.ToString()
                            Bindings     = ($bindingStrings -join ', ')
                            PhysicalPath = $site.Applications['/'].VirtualDirectories['/'].PhysicalPath
                            AppPoolName  = $poolName
                            AppPoolState = $poolState
                        })
                    }
                }
                catch { $sitesData = $null }
            }

            # CIM fallback
            if ($null -eq $sitesData) {
                try {
                    $cimSites = Get-CimInstance -Namespace 'root/webadministration' -ClassName 'Site' -ErrorAction Stop
                    $sitesData = [System.Collections.Generic.List[hashtable]]::new()

                    # Build app pool index via CIM
                    $cimPoolIndex = @{}
                    $cimPoolStateMap = @{ 1 = 'Started'; 2 = 'Starting'; 3 = 'Stopped'; 4 = 'Stopping' }
                    try {
                        $cimPools = Get-CimInstance -Namespace 'root/webadministration' -ClassName 'ApplicationPool' -ErrorAction Stop
                        foreach ($pool in $cimPools) {
                            $poolState = 'Unknown'
                            try {
                                $poolCimState = Invoke-CimMethod -InputObject $pool -MethodName 'GetState' -ErrorAction Stop
                                if ($cimPoolStateMap.ContainsKey([int]$poolCimState.ReturnValue)) {
                                    $poolState = $cimPoolStateMap[[int]$poolCimState.ReturnValue]
                                }
                            }
                            catch { $poolState = 'Unknown' }
                            $cimPoolIndex[$pool.Name] = $poolState
                        }
                    }
                    catch { Write-Verbose -Message 'CIM ApplicationPool query failed; pool data unavailable' }

                    # Build site-to-pool mapping via CIM Application class
                    $sitePoolMap = @{}
                    try {
                        $cimApps = Get-CimInstance -Namespace 'root/webadministration' -ClassName 'Application' -ErrorAction Stop
                        foreach ($app in $cimApps) {
                            if ($app.Path -eq '/') {
                                $sitePoolMap[$app.SiteName] = $app.ApplicationPool
                            }
                        }
                    }
                    catch { Write-Verbose -Message 'CIM Application query failed; site-to-pool mapping unavailable' }

                    $siteStateMap = @{ 1 = 'Started'; 2 = 'Starting'; 3 = 'Stopped'; 4 = 'Stopping' }
                    foreach ($site in $cimSites) {
                        $siteState = 'Unknown'
                        try {
                            $cimState = Invoke-CimMethod -InputObject $site -MethodName 'GetState' -ErrorAction Stop
                            if ($siteStateMap.ContainsKey([int]$cimState.ReturnValue)) {
                                $siteState = $siteStateMap[[int]$cimState.ReturnValue]
                            }
                        }
                        catch { $siteState = 'Unknown' }

                        $poolName  = if ($sitePoolMap.ContainsKey($site.Name)) { $sitePoolMap[$site.Name] } else { 'Unknown' }
                        $poolState = if ($cimPoolIndex.ContainsKey($poolName)) { $cimPoolIndex[$poolName] } else { 'Unknown' }

                        $sitesData.Add(@{
                            SiteName     = $site.Name
                            SiteState    = $siteState
                            Bindings     = 'N/A'
                            PhysicalPath = 'N/A'
                            AppPoolName  = $poolName
                            AppPoolState = $poolState
                        })
                    }
                }
                catch {
                    $siteResults.Add(@{
                        ServiceStatus = $w3svcStatus
                        SiteName      = 'N/A'
                        SiteState     = 'N/A'
                        Bindings      = 'N/A'
                        PhysicalPath  = 'N/A'
                        AppPoolName   = 'N/A'
                        AppPoolState  = 'N/A'
                        })
                    return $siteResults
                }
            }

            # Build results with health assessment
            if ($sitesData.Count -eq 0) {
                $siteResults.Add(@{
                    ServiceStatus = $w3svcStatus
                    SiteName      = 'NoSitesFound'
                    SiteState     = 'N/A'
                    Bindings      = 'N/A'
                    PhysicalPath  = 'N/A'
                    AppPoolName   = 'N/A'
                    AppPoolState  = 'N/A'
                })
            }
            else {
                foreach ($siteInfo in $sitesData) {

                    $siteResults.Add(@{
                        ServiceStatus = $w3svcStatus
                        SiteName      = $siteInfo.SiteName
                        SiteState     = $siteInfo.SiteState
                        Bindings      = $siteInfo.Bindings
                        PhysicalPath  = $siteInfo.PhysicalPath
                        AppPoolName   = $siteInfo.AppPoolName
                        AppPoolState  = $siteInfo.AppPoolState
                    })
                }
            }

            return $siteResults
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $rawResults = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                foreach ($entry in $rawResults) {
                    # Compute OverallHealth outside the scriptblock
                    $healthStatus = if ($entry.ServiceStatus -eq 'NotInstalled') {
                        [PSWinOpsHealthStatus]::RoleUnavailable
                    }
                    elseif ($entry.SiteName -eq 'N/A') {
                        [PSWinOpsHealthStatus]::RoleUnavailable
                    }
                    elseif ($entry.SiteName -eq 'NoSitesFound') {
                        if ($entry.ServiceStatus -ne 'Running') { [PSWinOpsHealthStatus]::Critical } else { [PSWinOpsHealthStatus]::Healthy }
                    }
                    elseif ($entry.ServiceStatus -ne 'Running') {
                        [PSWinOpsHealthStatus]::Critical
                    }
                    elseif ($entry.SiteState -notin @('Started', 'Unknown')) {
                        [PSWinOpsHealthStatus]::Critical
                    }
                    elseif ($entry.AppPoolState -notin @('Started', 'Unknown')) {
                        [PSWinOpsHealthStatus]::Degraded
                    }
                    else {
                        [PSWinOpsHealthStatus]::Healthy
                    }

                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.IISHealth'
                        ComputerName  = $displayName
                        ServiceName   = 'W3SVC'
                        ServiceStatus = $entry.ServiceStatus
                        SiteName      = $entry.SiteName
                        SiteState     = $entry.SiteState
                        Bindings      = $entry.Bindings
                        PhysicalPath  = $entry.PhysicalPath
                        AppPoolName   = $entry.AppPoolName
                        AppPoolState  = $entry.AppPoolState
                        OverallHealth = $healthStatus
                        Timestamp     = Get-Date -Format 'o'
                    }
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