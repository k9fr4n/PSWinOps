#Requires -Version 5.1

function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Executes a native command and returns structured output with exit code.
    .DESCRIPTION
        Wrapper around the call operator (&) for native executables. Returns a
        PSCustomObject with Output (string) and ExitCode (int) properties.

        This indirection allows Pester to mock native calls reliably, since
        $LASTEXITCODE cannot be controlled from a Pester mock (mocks are
        PowerShell functions, not native processes).
    .PARAMETER FilePath
        Full path to the native executable.
    .PARAMETER ArgumentList
        Arguments to pass to the executable.
    .OUTPUTS
    PSCustomObject
        Object with Output [string] and ExitCode [int] properties.
    .NOTES
        Author:  Franck SALLET
        Version: 1.0.0
        Scope:   Private — not exported
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList
    )

    $rawOutput = if ($ArgumentList) {
        & $FilePath @ArgumentList 2>&1
    } else {
        & $FilePath 2>&1
    }

    [PSCustomObject]@{
        Output   = ($rawOutput | Out-String).Trim()
        ExitCode = $LASTEXITCODE
    }
}
