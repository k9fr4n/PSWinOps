#Requires -Version 5.1
function Remove-ProxyConfiguration {
    <#
        .SYNOPSIS
            Removes proxy configuration from one or more Windows proxy layers

        .DESCRIPTION
            Disables and clears proxy settings from one or more of the three Windows proxy layers:
            - WinINET (HKCU registry): disables proxy, removes server, bypass list, and PAC URL
            - WinHTTP (netsh winhttp): resets to direct access
            - Environment variables: clears HTTP_PROXY, HTTPS_PROXY, NO_PROXY

            Each layer can be targeted independently via the -Scope parameter.
            WinHTTP scope requires administrator privileges (netsh winhttp reset proxy).

        .PARAMETER Scope
            One or more proxy layers to clear. Valid values:
            - WinINET      : Internet Settings registry (HKCU)
            - WinHTTP      : System-level proxy (requires admin)
            - Environment  : HTTP_PROXY / HTTPS_PROXY / NO_PROXY user variables
            - All          : All three layers (default)

        .EXAMPLE
            Remove-ProxyConfiguration

            Removes proxy configuration from all three layers.

        .EXAMPLE
            Remove-ProxyConfiguration -Scope WinINET

            Removes only WinINET (browser) proxy settings.

        .EXAMPLE
            Remove-ProxyConfiguration -Scope WinINET, Environment -WhatIf

            Shows what changes would be made without applying them.

        .EXAMPLE
            Remove-ProxyConfiguration -Scope Environment -Confirm:$false

            Clears proxy environment variables without confirmation prompt.

        .OUTPUTS
            None
            This function does not produce pipeline output.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-20
            Requires: PowerShell 5.1+ / Windows only

            WinHTTP scope requires local administrator privileges (netsh winhttp reset proxy).
            WinINET writes to HKCU (no elevation needed, applies to current user).
            Environment scope clears both User-level (persistent) and Process-level variables.

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-winhttp
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('WinINET', 'WinHTTP', 'Environment', 'All')]
        [string[]]$Scope = 'All'
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting proxy configuration removal"

        # Resolve 'All' to individual scopes
        if ($Scope -contains 'All') {
            $resolvedScopes = @('WinINET', 'WinHTTP', 'Environment')
        } else {
            $resolvedScopes = $Scope | Select-Object -Unique
        }

        Write-Verbose "[$($MyInvocation.MyCommand)] Target scopes: $($resolvedScopes -join ', ')"
    }

    process {
        # -- WinINET (HKCU Internet Settings) --
        if ($resolvedScopes -contains 'WinINET') {
            $winInetPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

            if ($PSCmdlet.ShouldProcess('WinINET (Internet Settings registry)', 'Remove proxy configuration')) {
                try {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Removing WinINET proxy settings"

                    Set-ItemProperty -Path $winInetPath -Name 'ProxyEnable' -Value 0 -Type DWord -ErrorAction Stop

                    foreach ($propertyName in @('ProxyServer', 'ProxyOverride', 'AutoConfigURL')) {
                        # Remove property if it exists; ignore if absent
                        Remove-ItemProperty -Path $winInetPath -Name $propertyName -ErrorAction SilentlyContinue
                    }

                    Write-Information -MessageData '[OK] WinINET proxy configuration removed'
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to remove WinINET proxy configuration: $_"
                }
            }
        }

        # -- WinHTTP (netsh winhttp) --
        if ($resolvedScopes -contains 'WinHTTP') {
            if ($PSCmdlet.ShouldProcess('WinHTTP (netsh winhttp)', 'Reset proxy to direct access')) {
                try {
                    if (-not (Test-IsAdministrator)) {
                        throw [System.UnauthorizedAccessException]::new('WinHTTP scope requires Administrator privileges.')
                    }

                    Write-Verbose "[$($MyInvocation.MyCommand)] Resetting WinHTTP proxy settings"

                    $netshPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
                    if (-not (Test-Path -Path $netshPath -PathType Leaf)) {
                        throw "netsh.exe not found at '$netshPath'"
                    }

                    Write-Verbose "[$($MyInvocation.MyCommand)] Running: netsh winhttp reset proxy"
                    $netshResult = Invoke-NativeCommand -FilePath $netshPath -ArgumentList @('winhttp', 'reset', 'proxy')
                    $netshExitCode = $netshResult.ExitCode

                    if ($netshExitCode -ne 0) {
                        $outputText = $netshResult.Output
                        Write-Error "[$($MyInvocation.MyCommand)] netsh winhttp reset proxy failed (exit code $netshExitCode): $outputText"
                    } else {
                        Write-Information -MessageData '[OK] WinHTTP proxy configuration reset to direct access'
                    }
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to reset WinHTTP proxy: $_"
                }
            }
        }

        # -- Environment variables --
        if ($resolvedScopes -contains 'Environment') {
            if ($PSCmdlet.ShouldProcess('Environment variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY)', 'Remove proxy configuration')) {
                try {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Clearing proxy environment variables"

                    # Clear Process-level (immediate effect)
                    $env:HTTP_PROXY  = $null
                    $env:HTTPS_PROXY = $null
                    $env:NO_PROXY    = $null

                    # Clear User-level (persistent)
                    try {
                        [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', $null, [System.EnvironmentVariableTarget]::User)
                        [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', $null, [System.EnvironmentVariableTarget]::User)
                        [System.Environment]::SetEnvironmentVariable('NO_PROXY', $null, [System.EnvironmentVariableTarget]::User)
                        Write-Verbose "[$($MyInvocation.MyCommand)] User-level environment variables cleared"
                    } catch {
                        Write-Warning "[$($MyInvocation.MyCommand)] Failed to clear User-level environment variables: $_. Process-level variables were cleared successfully."
                    }

                    Write-Information -MessageData '[OK] Proxy environment variables cleared'
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to clear proxy environment variables: $_"
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed proxy configuration removal"
    }
}
