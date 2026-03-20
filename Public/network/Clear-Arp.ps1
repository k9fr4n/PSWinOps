#Requires -Version 5.1
function Clear-Arp {
    <#
    .SYNOPSIS
        Clears the ARP (Address Resolution Protocol) cache on the local machine.
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
    None
        This function does not produce pipeline output.
    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-03-20
        Requires: PowerShell 5.1+ / Windows only
        Requires: Administrator privileges (netsh interface ip delete arpcache)

        Inspired by AdminToolbox.Networking Clear-Arp by TheTaylorLee.
    .LINK
    https://docs.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-interface-ip
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
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
        if ($PSCmdlet.ShouldProcess('Local ARP cache', 'Delete all entries')) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Running: netsh interface ip delete arpcache"
                $result = Invoke-NativeCommand -FilePath $netshPath -ArgumentList @('interface', 'ip', 'delete', 'arpcache')

                if ($result.ExitCode -ne 0) {
                    Write-Error "[$($MyInvocation.MyCommand)] netsh interface ip delete arpcache failed (exit code $($result.ExitCode)): $($result.Output)"
                } else {
                    Write-Verbose "[$($MyInvocation.MyCommand)] ARP cache cleared successfully"
                    Write-Information -MessageData '[OK] ARP cache cleared successfully' -InformationAction Continue
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to clear ARP cache: $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed ARP cache clear operation"
    }
}
