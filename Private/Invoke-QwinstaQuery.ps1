#Requires -Version 5.1

function Invoke-QwinstaQuery {
    <#
.SYNOPSIS
    Internal wrapper -- queries active sessions on a target computer via qwinsta.exe

.DESCRIPTION
    Private function, not exported. Executes qwinsta.exe /server:<ServerName> and
    returns both the raw output lines and the process exit code encapsulated in a
    single PSCustomObject. This design allows the caller to be unit-tested without
    depending on the automatic variable $LASTEXITCODE, which is not reliably set
    when native commands are intercepted by Pester mocks.

.PARAMETER ServerName
    The computer name to query. Passed as /server:<ServerName> to qwinsta.exe.

.EXAMPLE
    Invoke-QwinstaQuery -ServerName 'SRV01'

    Returns [PSCustomObject]@{ Output = @('...'); ExitCode = 0 }.

.EXAMPLE
    $qr = Invoke-QwinstaQuery -ServerName $ComputerName
    if ($qr.ExitCode -ne 0) { Write-Error "qwinsta failed with code $($qr.ExitCode)" }
    foreach ($line in ($qr.Output | Select-Object -Skip 1)) { # parse }

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-03-11
    Requires:      PowerShell 5.1+, qwinsta.exe (Remote Desktop Services tools)
    Permissions:   None -- internal function, not exported

    .LINK
    https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/query-session
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerName
    )

    process {
        $qwinstaPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\qwinsta.exe'
        $rawOutput = & $qwinstaPath "/server:$ServerName" 2>&1
        [PSCustomObject]@{
            Output   = $rawOutput
            ExitCode = $LASTEXITCODE
        }
    }
}
