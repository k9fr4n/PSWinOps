#Requires -Version 5.1
function Get-ServiceAccount {
    <#
    .SYNOPSIS
        Audit service logon accounts across local or remote computers

    .DESCRIPTION
        Projects Win32_Service into a security-oriented view of service logon accounts,
        reporting which account (Log On As / StartName) runs each service, its start mode,
        delayed auto-start flag, current state, and full binary path. Supports wildcard
        filtering by account and exclusion of built-in system accounts for multi-machine
        service-account auditing.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Account
        Wildcard filter (-like) applied to StartName, e.g. 'DOMAIN\svc-*'. When omitted,
        all service accounts are returned. Case-insensitive (PowerShell -like default).

    .PARAMETER NonSystemOnly
        Excludes built-in system logon accounts (LocalSystem, NT AUTHORITY\LocalService,
        NT AUTHORITY\NetworkService, and their short forms) to isolate custom service
        accounts. Comparison is case-insensitive. A null or empty StartName is treated
        as a system account and excluded.

    .PARAMETER Credential
        Optional PSCredential object for authenticating to remote computers.
        Not used for local queries.

    .EXAMPLE
        Get-ServiceAccount

        Retrieves the logon account for every service on the local computer.

    .EXAMPLE
        Get-ServiceAccount -ComputerName 'SRV01' -Account 'CONTOSO\svc-*' -Credential (Get-Credential)

        Retrieves services on SRV01 whose logon account matches 'CONTOSO\svc-*' using alternate credentials.

    .EXAMPLE
        'SRV01', 'SRV02' | Get-ServiceAccount -NonSystemOnly

        Retrieves custom (non built-in) service accounts from multiple servers via pipeline.

    .OUTPUTS
        PSWinOps.ServiceAccount
        Returns one object per matching service, with ComputerName, ServiceName,
        DisplayName, StartName, StartMode, DelayedAutoStart, State, PathName, and Timestamp.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-06
        Requires: PowerShell 5.1+ / Windows only

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-service
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ServiceAccount')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Account,

        [Parameter(Mandatory = $false)]
        [switch]$NonSystemOnly,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting"

        $excludedSystemAccounts = @(
            'LocalSystem',
            'NT AUTHORITY\LocalService',
            'NT AUTHORITY\NetworkService',
            'LocalService',
            'NetworkService'
        )

        $scriptBlock = {
            Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
                Select-Object -Property Name, DisplayName, StartName, StartMode, DelayedAutoStart, State, PathName
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing $computer"

            try {
                $services = Invoke-RemoteOrLocal -ComputerName $computer -ScriptBlock $scriptBlock -Credential $Credential

                foreach ($service in $services) {
                    $startName = $service.StartName

                    if ($Account -and ($startName -notlike $Account)) {
                        continue
                    }

                    if ($NonSystemOnly) {
                        $isSystemAccount = [string]::IsNullOrEmpty($startName)
                        if (-not $isSystemAccount) {
                            foreach ($excludedAccount in $excludedSystemAccounts) {
                                if ($startName -eq $excludedAccount) {
                                    $isSystemAccount = $true
                                    break
                                }
                            }
                        }
                        if ($isSystemAccount) {
                            continue
                        }
                    }

                    [PSCustomObject]@{
                        PSTypeName       = 'PSWinOps.ServiceAccount'
                        ComputerName     = $computer
                        ServiceName      = $service.Name
                        DisplayName      = $service.DisplayName
                        StartName        = $startName
                        StartMode        = $service.StartMode
                        DelayedAutoStart = $service.DelayedAutoStart
                        State            = $service.State
                        PathName         = $service.PathName
                        Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query service accounts on ${computer}: $_"
                continue
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
