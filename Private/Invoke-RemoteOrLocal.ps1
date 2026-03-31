#Requires -Version 5.1

function Invoke-RemoteOrLocal {
    <#
        .SYNOPSIS
            Executes a scriptblock locally or remotely via Invoke-Command

        .DESCRIPTION
            Centralises the local-vs-remote execution decision that is repeated
            across most PSWinOps public functions. When the target computer name
            matches the local machine ($env:COMPUTERNAME, 'localhost', or '.'),
            the scriptblock is invoked directly with the call operator (&).
            Otherwise it is dispatched via Invoke-Command over WinRM.

            This eliminates ~300 lines of duplicated if/else blocks across the
            module and provides a single place to maintain the remoting logic.

        .PARAMETER ComputerName
            The target computer. When it matches the local machine, the
            scriptblock runs in-process without WinRM overhead.

        .PARAMETER ScriptBlock
            The scriptblock to execute. Must accept positional parameters
            matching the ArgumentList array when ArgumentList is provided.

        .PARAMETER ArgumentList
            Optional array of arguments passed positionally to the scriptblock.
            For local execution they are splatted; for remote execution they
            are forwarded to Invoke-Command -ArgumentList.

        .PARAMETER Credential
            Optional credential for remote execution. Ignored for local calls.
            When not supplied (or set to [PSCredential]::Empty), Invoke-Command
            runs under the current user context.

        .EXAMPLE
            Invoke-RemoteOrLocal -ComputerName $env:COMPUTERNAME -ScriptBlock { Get-Service }

            Executes the scriptblock locally via the call operator.

        .EXAMPLE
            Invoke-RemoteOrLocal -ComputerName 'SRV01' -ScriptBlock { param($svc) Get-Service -Name $svc } -ArgumentList @('w32time')

            Executes the scriptblock on SRV01 via Invoke-Command, passing 'w32time' as argument.

        .EXAMPLE
            Invoke-RemoteOrLocal -ComputerName 'SRV01' -ScriptBlock { Get-Process } -Credential $cred

            Executes the scriptblock on SRV01 via Invoke-Command with explicit credentials.

        .OUTPUTS
            System.Object
            Returns whatever the scriptblock produces.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-31
            Requires: PowerShell 5.1+ / Windows only
            Scope: Private - not exported

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object[]]$ArgumentList,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    $localNames = @($env:COMPUTERNAME, 'localhost', '.')

    if ($localNames -contains $ComputerName) {
        Write-Verbose -Message "[Invoke-RemoteOrLocal] Executing locally on '$ComputerName'"
        if ($ArgumentList) {
            return & $ScriptBlock @ArgumentList
        }
        return & $ScriptBlock
    }

    Write-Verbose -Message "[Invoke-RemoteOrLocal] Executing remotely on '$ComputerName' via Invoke-Command"
    $invokeParams = @{
        ComputerName = $ComputerName
        ScriptBlock  = $ScriptBlock
        ErrorAction  = 'Stop'
    }
    if ($ArgumentList) {
        $invokeParams['ArgumentList'] = $ArgumentList
    }
    if ($null -ne $Credential -and $Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $invokeParams['Credential'] = $Credential
    }

    Invoke-Command @invokeParams
}
