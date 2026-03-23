#Requires -Version 5.1

function Edit-HostsFile {
    <#
        .SYNOPSIS
            Opens the Windows hosts file in an elevated editor

        .DESCRIPTION
            Launches the specified text editor (default: notepad.exe) as Administrator
            to edit the hosts file located at C:\Windows\System32\drivers\etc\hosts.

            The editor process is started with the -Verb RunAs flag, which triggers
            a UAC elevation prompt if the current session is not already elevated.

        .PARAMETER Editor
            Path or name of the text editor to use. Defaults to 'notepad.exe'.
            Examples: 'notepad.exe', 'code', 'notepad++.exe'

        .EXAMPLE
            Edit-HostsFile

            Opens the hosts file in Notepad as Administrator.

        .EXAMPLE
            Edit-HostsFile -Editor 'notepad++.exe'

            Opens the hosts file in Notepad++ as Administrator.

        .EXAMPLE
            Edit-HostsFile -Editor 'code'

            Opens the hosts file in VS Code as Administrator.

        .OUTPUTS
            None
            This function does not produce pipeline output.

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-03-20
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   Triggers UAC elevation prompt

        .LINK
            https://github.com/k9fr4n/PSWinOps
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Editor = 'notepad.exe'
    )

    begin {
        $hostsPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\drivers\etc\hosts'
    }

    process {
        if (-not (Test-Path -Path $hostsPath -PathType Leaf)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.FileNotFoundException]::new("Hosts file not found: '$hostsPath'"),
                    'HostsFileNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $hostsPath
                )
            )
        }

        if (-not $PSCmdlet.ShouldProcess($hostsPath, "Open with '$Editor' as Administrator")) {
            return
        }

        try {
            Write-Verbose "[$($MyInvocation.MyCommand)] Opening '$hostsPath' with '$Editor' as Administrator"
            Start-Process -FilePath $Editor -ArgumentList $hostsPath -Verb RunAs -ErrorAction Stop
        } catch {
            Write-Error "[$($MyInvocation.MyCommand)] Failed to open hosts file: $_"
        }
    }
}
