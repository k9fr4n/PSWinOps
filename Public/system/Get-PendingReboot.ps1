#Requires -Version 5.1
function Get-PendingReboot {
    <#
        .SYNOPSIS
            Checks pending reboot status from multiple Windows sources

        .DESCRIPTION
            Queries multiple system sources to determine if a Windows machine has a pending
            reboot. Sources include Component Based Servicing, Windows Update, pending file
            rename operations, pending computer rename, and SCCM client SDK.

        .PARAMETER ComputerName
            One or more computer names to check. Defaults to the local machine name.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential object for authenticating to remote machines.
            Not used for local machine checks.

        .EXAMPLE
            Get-PendingReboot

            Checks the local machine for any pending reboot indicators.

        .EXAMPLE
            Get-PendingReboot -ComputerName 'SERVER01'

            Checks a single remote machine for pending reboot status.

        .EXAMPLE
            'SERVER01', 'SERVER02' | Get-PendingReboot -Credential (Get-Credential)

            Checks multiple remote machines via pipeline input with alternate credentials.

        .OUTPUTS
            PSWinOps.PendingReboot
            Pending reboot status from multiple detection sources.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-18
            Requires: PowerShell 5.1+ / Windows only
            Permissions: Some checks may require administrative privileges.
            Remote checks require WinRM to be enabled on target machines.
            SCCM checks require the ConfigMgr client to be installed.
            Local computer name detection covers $env:COMPUTERNAME, 'localhost', and '.'.
            FQDN or IP of the local machine will be treated as a remote target.

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.PendingReboot')]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting pending reboot check"

        $checkScript = {
            $cbsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            $wuPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            $smPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
            $activeNamePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
            $pendingNamePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'

            $componentBasedServicing = Test-Path -Path $cbsPath
            $windowsUpdate = Test-Path -Path $wuPath

            $pfroValue = (Get-ItemProperty -Path $smPath -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue).PendingFileRenameOperations
            $pendingFileRename = ($null -ne $pfroValue) -and (@($pfroValue).Count -gt 0)

            $activeName = (Get-ItemProperty -Path $activeNamePath -Name 'ComputerName' -ErrorAction SilentlyContinue).ComputerName
            $pendingName = (Get-ItemProperty -Path $pendingNamePath -Name 'ComputerName' -ErrorAction SilentlyContinue).ComputerName
            $pendingComputerRename = $activeName -ne $pendingName

            $ccmClientSDK = $null
            try {
                $ccmResult = Invoke-CimMethod -Namespace 'ROOT\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction Stop
                $ccmClientSDK = [bool]($ccmResult.IsHardRebootPending -or $ccmResult.RebootPending)
            } catch {
                $ccmClientSDK = $null
            }

            @{
                ComponentBasedServicing = $componentBasedServicing
                WindowsUpdate           = $windowsUpdate
                PendingFileRename       = $pendingFileRename
                PendingComputerRename   = $pendingComputerRename
                CCMClientSDK            = $ccmClientSDK
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Checking pending reboot on '$computer'"

            try {
                $checkResult = Invoke-RemoteOrLocal -ComputerName $computer -ScriptBlock $checkScript -Credential $Credential

                $isRebootPending = (
                    $checkResult['ComponentBasedServicing'] -or
                    $checkResult['WindowsUpdate'] -or
                    $checkResult['PendingFileRename'] -or
                    $checkResult['PendingComputerRename'] -or
                    ($checkResult['CCMClientSDK'] -eq $true)
                )

                [PSCustomObject]@{
                    PSTypeName              = 'PSWinOps.PendingReboot'
                    ComputerName            = $computer
                    IsRebootPending         = [bool]$isRebootPending
                    ComponentBasedServicing = [bool]$checkResult['ComponentBasedServicing']
                    WindowsUpdate           = [bool]$checkResult['WindowsUpdate']
                    PendingFileRename       = [bool]$checkResult['PendingFileRename']
                    PendingComputerRename   = [bool]$checkResult['PendingComputerRename']
                    CCMClientSDK            = $checkResult['CCMClientSDK']
                    Timestamp               = (Get-Date -Format 'o')
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to check pending reboot on '$computer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed pending reboot check"
    }
}
