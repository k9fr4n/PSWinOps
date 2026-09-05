#Requires -Version 5.1
function Clear-Arp {
    <#
        .SYNOPSIS
            Clears the ARP (Address Resolution Protocol) cache on the local machine

        .DESCRIPTION
            Removes all entries from the ARP cache by executing 'netsh interface ip delete arpcache'.
            This forces the system to re-resolve MAC addresses for all IP destinations, which can
            help resolve network connectivity issues caused by stale or incorrect ARP entries.

            Requires administrator privileges to execute.

        .EXAMPLE
            Clear-Arp

            Clears the entire ARP cache on the local machine.

        .EXAMPLE
            Clear-Arp -WhatIf

            Shows what would happen without actually clearing the ARP cache.

        .EXAMPLE
            Clear-Arp -Verbose

            Clears the ARP cache with verbose output showing execution details.

        .OUTPUTS
            PSWinOps.ActionResult
            Returns the action status, target, error details, and timestamp.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-20
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (netsh interface ip delete arpcache)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-interface-ip
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('PSWinOps.ActionResult')]
    param()

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting ARP cache clear operation"

        if (-not (Test-IsAdministrator)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new('Clear-Arp requires Administrator privileges.'),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }

        $netshPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
        if (-not (Test-Path -Path $netshPath -PathType Leaf)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new("netsh.exe not found at '$netshPath'."),
                    'NetshNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $netshPath
                )
            )
        }
    }

    process {
        $target = 'Local ARP cache'

        if (-not $PSCmdlet.ShouldProcess($target, 'Delete all entries')) {
            ConvertTo-ActionResult -Action $MyInvocation.MyCommand -Target $target -Status 'WhatIf'
            return
        }

        try {
            Write-Verbose "[$($MyInvocation.MyCommand)] Running: netsh interface ip delete arpcache"
            $result = Invoke-NativeCommand -FilePath $netshPath -ArgumentList @('interface', 'ip', 'delete', 'arpcache')

            if ($result.ExitCode -ne 0) {
                $errorMessage = "[$($MyInvocation.MyCommand)] netsh interface ip delete arpcache failed (exit code $($result.ExitCode)): $($result.Output)"
                Write-Error $errorMessage
                ConvertTo-ActionResult -Action $MyInvocation.MyCommand -Target $target -Status 'Failed' -ErrorMessage $errorMessage
            } else {
                Write-Verbose "[$($MyInvocation.MyCommand)] ARP cache cleared successfully"
                Write-Information -MessageData '[OK] ARP cache cleared successfully'
                ConvertTo-ActionResult -Action $MyInvocation.MyCommand -Target $target -Status 'Succeeded'
            }
        } catch {
            $errorMessage = "[$($MyInvocation.MyCommand)] Failed to clear ARP cache: $_"
            Write-Error $errorMessage
            ConvertTo-ActionResult -Action $MyInvocation.MyCommand -Target $target -Status 'Failed' -ErrorMessage $errorMessage
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed ARP cache clear operation"
    }
}
