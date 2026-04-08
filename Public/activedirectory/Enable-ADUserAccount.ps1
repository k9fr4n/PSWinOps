#Requires -Version 5.1
function Enable-ADUserAccount {
    <#
    .SYNOPSIS
        Enables one or more disabled Active Directory user accounts

    .DESCRIPTION
        Enables disabled Active Directory user accounts using the Enable-ADAccount cmdlet.
        Returns a result object per user indicating success or failure for audit logging.
        Supports ShouldProcess for WhatIf and Confirm scenarios.

    .PARAMETER Identity
        One or more user identifiers (SamAccountName, DN, SID, or GUID).
        Accepts pipeline input by value and by property name.

    .PARAMETER Server
        The Active Directory domain controller to target for the operation.

    .PARAMETER Credential
        The PSCredential object used to authenticate against Active Directory.

    .EXAMPLE
        Enable-ADUserAccount -Identity 'jdoe'

        Enables the disabled user account jdoe in the current domain.

    .EXAMPLE
        Enable-ADUserAccount -Identity 'jdoe', 'asmith' -Server 'DC01.contoso.com'

        Enables two user accounts targeting a specific domain controller.

    .EXAMPLE
        'jdoe', 'asmith' | Enable-ADUserAccount -Credential (Get-Credential)

        Enables user accounts via pipeline input with alternate credentials.

    .OUTPUTS
        PSWinOps.ADAccountEnableResult
        Returns objects with Identity, UserName, Success, Message, and Timestamp properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)
        Requires: Account Operator or equivalent permissions

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/enable-adaccount
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('SamAccountName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $moduleAvailable = $false
        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop -Verbose:$false
            $moduleAvailable = $true
        }
        catch {
            Write-Error -Message "[$($MyInvocation.MyCommand)] ActiveDirectory module is not available: $_"
        }

        $adSplat = @{}
        if ($PSBoundParameters.ContainsKey('Server')) {
            $adSplat['Server'] = $Server
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adSplat['Credential'] = $Credential
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    process {
        if (-not $moduleAvailable) { return }

        foreach ($id in $Identity) {
            if (-not $PSCmdlet.ShouldProcess($id, 'Enable AD user account')) {
                continue
            }

            try {
                $adUser = Get-ADUser -Identity $id -Properties 'Enabled' -ErrorAction Stop @adSplat

                if ($adUser.Enabled) {
                    [PSCustomObject]@{
                        PSTypeName = 'PSWinOps.ADAccountEnableResult'
                        Identity   = $id
                        UserName   = $adUser.SamAccountName
                        Success    = $true
                        Message    = 'Account was already enabled'
                        Timestamp  = $timestamp
                    }
                    continue
                }

                Enable-ADAccount -Identity $adUser.DistinguishedName -ErrorAction Stop @adSplat

                [PSCustomObject]@{
                    PSTypeName = 'PSWinOps.ADAccountEnableResult'
                    Identity   = $id
                    UserName   = $adUser.SamAccountName
                    Success    = $true
                    Message    = 'Account enabled successfully'
                    Timestamp  = $timestamp
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to enable account ${id}: $_"

                [PSCustomObject]@{
                    PSTypeName = 'PSWinOps.ADAccountEnableResult'
                    Identity   = $id
                    UserName   = $null
                    Success    = $false
                    Message    = "Failed: $_"
                    Timestamp  = $timestamp
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
