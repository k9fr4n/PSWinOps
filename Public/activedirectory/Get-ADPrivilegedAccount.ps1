#Requires -Version 5.1

function Get-ADPrivilegedAccount {
    <#
    .SYNOPSIS
        Lists members of privileged Active Directory groups

    .DESCRIPTION
        Enumerates members of high-privilege AD groups such as Domain Admins, Enterprise Admins,
        and Schema Admins. Supports custom group lists and optional recursive enumeration.
        For user members, additional properties like Enabled status and last logon are retrieved.

    .PARAMETER GroupName
        One or more privileged group names to audit. Defaults to a standard set of built-in
        privileged groups: Domain Admins, Enterprise Admins, Schema Admins, Administrators,
        Account Operators, Server Operators, Backup Operators, and Print Operators.

    .PARAMETER DirectOnly
        When specified, returns only direct group members without recursing into nested
        groups. By default, all nested members are enumerated recursively to ensure
        complete coverage of privileged access.

    .PARAMETER Server
        Specifies the Active Directory Domain Services instance to connect to.

    .PARAMETER Credential
        Specifies the credentials to use for the Active Directory query.

    .EXAMPLE
        Get-ADPrivilegedAccount

        Lists members of all default privileged groups.

    .EXAMPLE
        Get-ADPrivilegedAccount -GroupName 'Domain Admins', 'Enterprise Admins' -Server 'dc01.contoso.com'

        Audits specific groups from a targeted domain controller.

    .EXAMPLE
        Get-ADPrivilegedAccount -DirectOnly -GroupName 'Domain Admins'

        Lists only direct members of Domain Admins without recursing nested groups.

    .OUTPUTS
        PSWinOps.ADPrivilegedAccount
        Returns objects with group name, member identity, object class, enabled status,
        and last logon date sorted by group name then member name.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-03
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroupmember
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$GroupName = @(
            'Domain Admins'
            'Enterprise Admins'
            'Schema Admins'
            'Administrators'
            'Account Operators'
            'Server Operators'
            'Backup Operators'
            'Print Operators'
        ),

        [Parameter()]
        [switch]$DirectOnly,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop
        }
        catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'ActiveDirectory module is not available. Install RSAT-AD-PowerShell.',
                        $_.Exception
                    ),
                    'ActiveDirectoryModuleMissing',
                    [System.Management.Automation.ErrorCategory]::NotInstalled,
                    'ActiveDirectory'
                )
            )
        }

        $adParams = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adParams['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adParams['Credential'] = $Credential
        }

        $allResults = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($groupIdentity in $GroupName) {
            try {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying group: $groupIdentity"

                $group = Get-ADGroup -Identity $groupIdentity @adParams -ErrorAction Stop

                $memberParams = @{
                    Identity    = $groupIdentity
                    ErrorAction = 'Stop'
                }
                if (-not $DirectOnly) {
                    $memberParams['Recursive'] = $true
                }

                $members = Get-ADGroupMember @memberParams @adParams

                foreach ($member in $members) {
                    $enabled = $null
                    $lastLogon = $null

                    if ($member.ObjectClass -eq 'user') {
                        $userDetail = Get-ADUser -Identity $member.SamAccountName `
                            -Properties 'Enabled', 'LastLogonDate' `
                            @adParams -ErrorAction SilentlyContinue
                        if ($userDetail) {
                            $enabled = $userDetail.Enabled
                            $lastLogon = $userDetail.LastLogonDate
                        }
                    }

                    $allResults.Add([PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.ADPrivilegedAccount'
                        GroupName         = $group.Name
                        MemberName        = $member.Name
                        SamAccountName    = $member.SamAccountName
                        ObjectClass       = $member.ObjectClass
                        Enabled           = $enabled
                        LastLogonDate     = $lastLogon
                        DistinguishedName = $member.DistinguishedName
                        Timestamp         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    })
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query group '$groupIdentity': $_"
                continue
            }
        }
    }

    end {
        $allResults | Sort-Object -Property 'GroupName', 'MemberName'
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed — found $($allResults.Count) privileged account(s)"
    }
}
