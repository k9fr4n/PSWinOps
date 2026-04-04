#Requires -Version 5.1
function Unlock-ADUserAccount {
    <#
    .SYNOPSIS
        Unlocks one or more Active Directory user accounts

    .DESCRIPTION
        Unlocks locked Active Directory user accounts using the Unlock-ADAccount cmdlet.
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
        Unlock-ADUserAccount -Identity 'jdoe'

        Unlocks the user account jdoe in the current domain.

    .EXAMPLE
        Unlock-ADUserAccount -Identity 'jdoe', 'asmith' -Server 'DC01.contoso.com'

        Unlocks two user accounts targeting a specific domain controller.

    .EXAMPLE
        'jdoe', 'asmith' | Unlock-ADUserAccount -Credential (Get-Credential)

        Unlocks user accounts via pipeline input with alternate credentials.

    .OUTPUTS
        PSWinOps.ADAccountUnlockResult
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
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/unlock-adaccount
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

        $timestamp = Get-Date -Format 'o'
    }

    process {
        if (-not $moduleAvailable) { return }

        foreach ($id in $Identity) {
            if (-not $PSCmdlet.ShouldProcess($id, 'Unlock AD user account')) {
                continue
            }

            try {
                $adUser = Get-ADUser -Identity $id -Properties 'LockedOut' -ErrorAction Stop @adSplat

                if (-not $adUser.LockedOut) {
                    [PSCustomObject]@{
                        PSTypeName = 'PSWinOps.ADAccountUnlockResult'
                        Identity   = $id
                        UserName   = $adUser.SamAccountName
                        Success    = $true
                        Message    = 'Account was not locked'
                        Timestamp  = $timestamp
                    }
                    continue
                }

                Unlock-ADAccount -Identity $adUser.DistinguishedName -ErrorAction Stop @adSplat

                [PSCustomObject]@{
                    PSTypeName = 'PSWinOps.ADAccountUnlockResult'
                    Identity   = $id
                    UserName   = $adUser.SamAccountName
                    Success    = $true
                    Message    = 'Account unlocked successfully'
                    Timestamp  = $timestamp
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to unlock account ${id}: $_"

                [PSCustomObject]@{
                    PSTypeName = 'PSWinOps.ADAccountUnlockResult'
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
