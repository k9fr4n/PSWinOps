function Test-IsAdministrator {
    <#
        .SYNOPSIS
            Tests whether the current PowerShell session is running with Administrator privileges

        .DESCRIPTION
            Returns $true if the current Windows identity has the Administrator role,
            $false otherwise. Used internally by PSWinOps functions that require elevation
            (e.g., Set-NTPClient, Sync-NTPTime, WinHTTP proxy operations).

        .EXAMPLE
            Test-IsAdministrator
            Returns $true if the current session is elevated, $false otherwise.

        .EXAMPLE
            if (-not (Test-IsAdministrator)) { throw 'Elevation required.' }
            Guards a code path that requires Administrator privileges.

        .OUTPUTS
            System.Boolean
            $true if the current session is elevated; $false otherwise.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-20
            Requires: PowerShell 5.1+ / Windows only

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/dotnet/api/system.security.principal.windowsprincipal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}
