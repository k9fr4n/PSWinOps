#Requires -Version 5.1
function Reset-ADUserPassword {
    <#
    .SYNOPSIS
        Resets the password of one or more Active Directory user accounts

    .DESCRIPTION
        Resets Active Directory user account passwords using Set-ADAccountPassword with
        the -Reset parameter. Optionally forces the user to change password at next logon.
        Returns a result object per user indicating success or failure for audit logging.
        Supports ShouldProcess for WhatIf and Confirm scenarios.

    .PARAMETER Identity
        One or more user identifiers (SamAccountName, DN, SID, or GUID).
        Accepts pipeline input by value and by property name.

    .PARAMETER NewPassword
        The new password as a SecureString. This parameter is mandatory.

    .PARAMETER MustChangePasswordAtLogon
        When specified, forces the user to change their password at next logon
        by setting the ChangePasswordAtLogon attribute to true.

    .PARAMETER Server
        The Active Directory domain controller to target for the operation.

    .PARAMETER Credential
        The PSCredential object used to authenticate against Active Directory.

    .EXAMPLE
        Reset-ADUserPassword -Identity 'jdoe' -NewPassword (Read-Host -AsSecureString 'New password')

        Resets the password for user jdoe with a prompted secure password.

    .EXAMPLE
        Reset-ADUserPassword -Identity 'jdoe' -NewPassword $securePass -MustChangePasswordAtLogon -Server 'DC01'

        Resets password and forces change at next logon, targeting a specific DC.

    .EXAMPLE
        'jdoe', 'asmith' | Reset-ADUserPassword -NewPassword $securePass -Credential (Get-Credential)

        Resets passwords for multiple users via pipeline with alternate credentials.

    .OUTPUTS
        PSWinOps.ADPasswordResetResult
        Returns objects with Identity, UserName, Success, MustChangeAtLogon, Message,
        and Timestamp properties.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-04-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT)
        Requires: Account Operator or Reset Password delegation

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-adaccountpassword
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('SamAccountName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Security.SecureString]$NewPassword,

        [Parameter()]
        [switch]$MustChangePasswordAtLogon,

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
            if (-not $PSCmdlet.ShouldProcess($id, 'Reset AD user password')) {
                continue
            }

            try {
                $adUser = Get-ADUser -Identity $id -ErrorAction Stop @adSplat

                Set-ADAccountPassword -Identity $adUser.DistinguishedName -Reset -NewPassword $NewPassword -ErrorAction Stop @adSplat

                if ($MustChangePasswordAtLogon) {
                    Set-ADUser -Identity $adUser.DistinguishedName -ChangePasswordAtLogon $true -ErrorAction Stop @adSplat
                }

                [PSCustomObject]@{
                    PSTypeName        = 'PSWinOps.ADPasswordResetResult'
                    Identity          = $id
                    UserName          = $adUser.SamAccountName
                    Success           = $true
                    MustChangeAtLogon = [bool]$MustChangePasswordAtLogon
                    Message           = 'Password reset successfully'
                    Timestamp         = $timestamp
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to reset password for ${id}: $_"

                [PSCustomObject]@{
                    PSTypeName        = 'PSWinOps.ADPasswordResetResult'
                    Identity          = $id
                    UserName          = $null
                    Success           = $false
                    MustChangeAtLogon = $false
                    Message           = "Failed: $_"
                    Timestamp         = $timestamp
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
