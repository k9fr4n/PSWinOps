#Requires -Version 5.1
function Set-EnvironmentVariable {
    <#
        .SYNOPSIS
            Sets or deletes a Machine- or User-scoped environment variable on local or remote computers

        .DESCRIPTION
            Sets a Machine- or User-scoped environment variable using [Environment]::SetEnvironmentVariable,
            the symmetric writer for Get-EnvironmentVariable. Supports -WhatIf/-Confirm (ConfirmImpact Medium).
            An empty Value deletes the variable. User scope targets the executing account profile when run
            remotely (the WinRM logon identity), not the console user; already-running processes will not
            see the change until restarted regardless of scope.

        .PARAMETER Name
            Environment variable name to set or delete.

        .PARAMETER Value
            New value. An EMPTY string deletes the variable via
            [Environment]::SetEnvironmentVariable($Name, $null, $Scope).

        .PARAMETER Scope
            Machine (default) or User scope. Writing Machine scope requires Administrator
            privileges. User scope on a remote computer applies to the executing account's
            profile (the WinRM logon identity), not the interactive console user.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local operations.

        .EXAMPLE
            Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -Scope Machine

            Sets the Machine-scoped 'FOO' variable to 'bar' on the local computer.

        .EXAMPLE
            Set-EnvironmentVariable -Name 'FOO' -Value 'bar' -ComputerName 'SRV01' -Credential (Get-Credential)

            Sets the Machine-scoped 'FOO' variable to 'bar' on SRV01 using explicit credentials.

        .EXAMPLE
            'SRV01', 'SRV02' | Set-EnvironmentVariable -Name 'FOO' -Value ''

            Deletes the 'FOO' variable on both SRV01 and SRV02 via pipeline (empty Value = delete).

        .OUTPUTS
            PSWinOps.EnvironmentVariable
            Returns one object per computer with the read-back Name/Value/Scope after the
            operation. Value is an empty string when the variable was deleted.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-07-06
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges for Machine scope

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType('PSWinOps.EnvironmentVariable')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Machine', 'User')]
        [string]$Scope = 'Machine',

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting with Name='$Name', Scope=$Scope"

        $isDelete = [string]::IsNullOrEmpty($Value)

        $scriptBlock = {
            param(
                [string]$VariableName,
                [string]$VariableValue,
                [string]$VariableScope,
                [bool]$DeleteRequested
            )

            $valueToSet = if ($DeleteRequested) {
                $null
            } else {
                $VariableValue
            }

            [Environment]::SetEnvironmentVariable($VariableName, $valueToSet, $VariableScope)

            $readBack = [Environment]::GetEnvironmentVariable($VariableName, $VariableScope)
            if ($null -eq $readBack) {
                $readBack = ''
            }

            [PSCustomObject]@{
                Name  = $VariableName
                Value = $readBack
                Scope = $VariableScope
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$targetComputer'"

            try {
                $actionDescription = if ($isDelete) {
                    "Delete $Scope environment variable '$Name'"
                } else {
                    "Set $Scope environment variable '$Name' = '$Value'"
                }

                if ($PSCmdlet.ShouldProcess($targetComputer, $actionDescription)) {
                    $result = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $scriptBlock -ArgumentList @($Name, $Value, $Scope, $isDelete) -Credential $Credential

                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.EnvironmentVariable'
                        ComputerName = $targetComputer
                        Name         = $result.Name
                        Value        = $result.Value
                        Scope        = $result.Scope
                        Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${targetComputer}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
