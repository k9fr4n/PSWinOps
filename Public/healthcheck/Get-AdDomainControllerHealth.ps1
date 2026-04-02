#Requires -Version 5.1
function Get-AdDomainControllerHealth {
    <#
        .SYNOPSIS
            Checks Active Directory Domain Services health on a Domain Controller

        .DESCRIPTION
            Performs comprehensive AD DS health diagnostics on one or more Domain Controllers.
            Verifies the executing account has sufficient privileges (local Administrator plus
            Domain Admins or Enterprise Admins membership) before running diagnostics.
            Checks NTDS service status, replication health via repadmin, dcdiag test results,
            SYSVOL and NETLOGON share accessibility, and returns a typed health object per DC.
            If privileges are insufficient, OverallHealth is set to 'InsufficientPrivilege'
            and partial results are still returned where possible.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-AdDomainControllerHealth

            Checks AD DS health on the local Domain Controller.

        .EXAMPLE
            Get-AdDomainControllerHealth -ComputerName 'DC01' -Credential (Get-Credential)

            Checks AD DS health on a remote Domain Controller using explicit credentials.

        .EXAMPLE
            'DC01', 'DC02' | Get-AdDomainControllerHealth

            Checks AD DS health on multiple Domain Controllers via pipeline input.

        .OUTPUTS
            PSWinOps.AdDomainControllerHealth
            Returns one object per queried Domain Controller with service status,
            privilege validation, replication counters, dcdiag results, share
            accessibility, and overall health.

        .NOTES
            Author: Franck SALLET
            Version: 1.1.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: AD-Domain-Services role
            Requires: Module ActiveDirectory (RSAT-AD-PowerShell)
            Requires: Local Administrator + Domain Admins or Enterprise Admins

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/activedirectory/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.AdDomainControllerHealth')]
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

        $scriptBlock = {
            $data = @{
                ServiceStatus         = 'NotFound'
                ADModuleAvailable     = $false
                RunAsAccount          = $null
                IsLocalAdmin          = $false
                IsDomainAdmin         = $false
                HasRequiredPrivileges = $false
                DCName                = $null
                DomainName            = $null
                ForestName            = $null
                DomainMode            = $null
                SiteName              = $null
                IsGlobalCatalog       = $false
                IsReadOnly            = $false
                OperatingSystem       = $null
                SysvolAccessible      = $false
                NetlogonAccessible    = $false
                ReplicationSuccesses  = 0
                ReplicationFailures   = 0
                DcDiagPassedTests     = 0
                DcDiagFailedTests     = 0
            }

            # ---------------------------------------------------------------
            # 0. Privilege check
            # ---------------------------------------------------------------
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
            $data['RunAsAccount'] = $identity.Name

            # Local Administrator check
            $data['IsLocalAdmin'] = $principal.IsInRole(
                [System.Security.Principal.WindowsBuiltInRole]::Administrator
            )

            # Domain Admins (RID -512) or Enterprise Admins (RID -519)
            foreach ($group in $identity.Groups) {
                if ($group.Value -match '-512$|-519') {
                    $data['IsDomainAdmin'] = $true
                    break
                }
            }

            $data['HasRequiredPrivileges'] = $data['IsLocalAdmin'] -and $data['IsDomainAdmin']

            if (-not $data['HasRequiredPrivileges']) {
                $missing = [System.Collections.Generic.List[string]]::new()
                if (-not $data['IsLocalAdmin']) {
                    $missing.Add('Local Administrator')
                }
                if (-not $data['IsDomainAdmin']) {
                    $missing.Add('Domain Admins or Enterprise Admins')
                }
                Write-Warning -Message (
                    "Insufficient privileges for full AD DS diagnostics on $env:COMPUTERNAME. " +
                    "Missing: $($missing -join ', '). " +
                    "Account: $($data['RunAsAccount']). " +
                    'Results may be incomplete (repadmin/dcdiag require Domain Admin + local admin).'
                )
            }

            # ---------------------------------------------------------------
            # 1. NTDS service status
            # ---------------------------------------------------------------
            $ntdsSvc = Get-Service -Name 'NTDS' -ErrorAction SilentlyContinue
            if ($ntdsSvc) {
                $data['ServiceStatus'] = $ntdsSvc.Status.ToString()
            }

            # ---------------------------------------------------------------
            # 2. ActiveDirectory module availability
            # ---------------------------------------------------------------
            $adModule = Get-Module -Name 'ActiveDirectory' -ListAvailable -ErrorAction SilentlyContinue
            if ($adModule) {
                $data['ADModuleAvailable'] = $true
            }

            if (-not $data['ADModuleAvailable']) {
                return $data
            }

            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop

            # ---------------------------------------------------------------
            # 3a. Get-ADDomainController
            # ---------------------------------------------------------------
            try {
                $dcInfo = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop
                $data['DCName'] = $dcInfo.HostName
                $data['SiteName'] = $dcInfo.Site
                $data['IsGlobalCatalog'] = $dcInfo.IsGlobalCatalog
                $data['IsReadOnly'] = $dcInfo.IsReadOnly
                $data['OperatingSystem'] = $dcInfo.OperatingSystem
            } catch {
                Write-Warning -Message "Get-ADDomainController failed: $_"
            }

            # ---------------------------------------------------------------
            # 3b. Get-ADDomain
            # ---------------------------------------------------------------
            try {
                $domainInfo = Get-ADDomain -ErrorAction Stop
                $data['DomainName'] = $domainInfo.DNSRoot
                $data['ForestName'] = $domainInfo.Forest
                $data['DomainMode'] = $domainInfo.DomainMode.ToString()
            } catch {
                Write-Warning -Message "Get-ADDomain failed: $_"
            }

            # ---------------------------------------------------------------
            # 3c. repadmin /showrepl
            # ---------------------------------------------------------------
            $repadminPath = Get-Command -Name 'repadmin' -ErrorAction SilentlyContinue
            if ($repadminPath) {
                try {
                    $replOutput = & repadmin /showrepl 2>&1
                    $replText = $replOutput | Out-String
                    $successCount = ([regex]::Matches($replText, 'successful', 'IgnoreCase')).Count
                    $failCount = ([regex]::Matches($replText, 'failed', 'IgnoreCase')).Count
                    $data['ReplicationSuccesses'] = $successCount
                    $data['ReplicationFailures'] = $failCount
                } catch {
                    $data['ReplicationSuccesses'] = -1
                    $data['ReplicationFailures'] = -1
                }
            } else {
                $data['ReplicationSuccesses'] = -1
                $data['ReplicationFailures'] = -1
            }

            # ---------------------------------------------------------------
            # 3d. dcdiag /q
            # ---------------------------------------------------------------
            $dcdiagPath = Get-Command -Name 'dcdiag' -ErrorAction SilentlyContinue
            if ($dcdiagPath) {
                try {
                    $dcdiagOutput = & dcdiag /s:$env:COMPUTERNAME /test:Connectivity /test:Replications /test:Services /test:Advertising /test:FsmoCheck 2>&1
                    $dcdiagText = $dcdiagOutput | Out-String
                    $passedCount = ([regex]::Matches($dcdiagText, 'passed test', 'IgnoreCase')).Count
                    $failedCount = ([regex]::Matches($dcdiagText, 'failed test', 'IgnoreCase')).Count
                    $data['DcDiagPassedTests'] = $passedCount
                    $data['DcDiagFailedTests'] = $failedCount
                } catch {
                    $data['DcDiagPassedTests'] = -1
                    $data['DcDiagFailedTests'] = -1
                }
            } else {
                $data['DcDiagPassedTests'] = -1
                $data['DcDiagFailedTests'] = -1
            }

            # ---------------------------------------------------------------
            # 3e-f. SYSVOL and NETLOGON share accessibility
            # ---------------------------------------------------------------
            $sysvolPath = "\\$env:COMPUTERNAME\SYSVOL"
            $netlogonPath = "\\$env:COMPUTERNAME\NETLOGON"
            $data['SysvolAccessible'] = Test-Path -Path $sysvolPath
            $data['NetlogonAccessible'] = Test-Path -Path $netlogonPath

            return $data
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $result = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -Credential $Credential

                # Compute OverallHealth outside the scriptblock
                if (-not $result['ADModuleAvailable']) {
                    $healthStatus = 'RoleUnavailable'
                } elseif (-not $result['HasRequiredPrivileges']) {
                    $healthStatus = 'InsufficientPrivilege'
                } elseif ($result['ServiceStatus'] -ne 'Running' -or
                    $result['ReplicationFailures'] -gt 0 -or
                    $result['DcDiagFailedTests'] -gt 0) {
                    $healthStatus = 'Critical'
                } elseif (-not $result['SysvolAccessible'] -or
                    -not $result['NetlogonAccessible']) {
                    $healthStatus = 'Degraded'
                } else {
                    $healthStatus = 'Healthy'
                }

                [PSCustomObject]@{
                    PSTypeName            = 'PSWinOps.AdDomainControllerHealth'
                    ComputerName          = $displayName
                    ServiceName           = 'NTDS'
                    ServiceStatus         = $result['ServiceStatus']
                    RunAsAccount          = $result['RunAsAccount']
                    HasRequiredPrivileges = [bool]$result['HasRequiredPrivileges']
                    DomainName            = $result['DomainName']
                    ForestName            = $result['ForestName']
                    SiteName              = $result['SiteName']
                    IsGlobalCatalog       = $result['IsGlobalCatalog']
                    IsReadOnly            = $result['IsReadOnly']
                    SysvolAccessible      = $result['SysvolAccessible']
                    NetlogonAccessible    = $result['NetlogonAccessible']
                    ReplicationSuccesses  = $result['ReplicationSuccesses']
                    ReplicationFailures   = $result['ReplicationFailures']
                    DcDiagPassedTests     = $result['DcDiagPassedTests']
                    DcDiagFailedTests     = $result['DcDiagFailedTests']
                    OverallHealth         = $healthStatus
                    Timestamp             = Get-Date -Format 'o'
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
