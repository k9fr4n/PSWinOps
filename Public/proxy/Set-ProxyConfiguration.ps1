#Requires -Version 5.1
function Set-ProxyConfiguration {
    <#
        .SYNOPSIS
            Configures proxy settings on one or more Windows proxy layers

        .DESCRIPTION
            Applies proxy configuration to one or more of the three Windows proxy layers:
            - WinINET (HKCU registry): used by browsers, .NET apps, Internet Explorer/Edge
            - WinHTTP (netsh winhttp): used by system services and PowerShell default proxy
            - Environment variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY)

            Each layer can be targeted independently via the -Scope parameter.
            WinHTTP scope requires administrator privileges (netsh winhttp set proxy).
            Environment variables are set at the User level (persistent across sessions).

        .PARAMETER ProxyServer
            Proxy server address in the format 'host:port' (e.g., 'proxy.example.com:8080')
            or protocol-specific format (e.g., 'http=proxy:80;https=proxy:443').

        .PARAMETER BypassList
            Semicolon-separated list of addresses that bypass the proxy.
            Example: '*.local;*.example.com;<local>'
            For Environment scope, semicolons are converted to commas (NO_PROXY convention).

        .PARAMETER AutoConfigURL
            URL of a PAC (Proxy Auto-Configuration) file.
            Only applies to WinINET scope. Ignored for WinHTTP and Environment scopes.

        .PARAMETER Scope
            One or more proxy layers to configure. Valid values:
            - WinINET      : Internet Settings registry (HKCU)
            - WinHTTP      : System-level proxy (requires admin)
            - Environment  : HTTP_PROXY / HTTPS_PROXY / NO_PROXY user variables
            - All          : All three layers (default)

        .EXAMPLE
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080'

            Configures all three proxy layers with the specified proxy server.

        .EXAMPLE
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -BypassList '*.local;*.example.com;<local>' -Scope WinINET

            Configures only WinINET (browser/IE) proxy with a bypass list.

        .EXAMPLE
            Set-ProxyConfiguration -ProxyServer 'proxy.example.com:8080' -Scope WinINET, Environment -WhatIf

            Shows what changes would be made to WinINET and environment variables without applying them.

        .EXAMPLE
            Set-ProxyConfiguration -AutoConfigURL 'http://wpad.example.com/proxy.pac' -Scope WinINET

            Configures WinINET to use a PAC auto-configuration URL (no static proxy).

        .OUTPUTS
            None
            This function does not produce pipeline output.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.1
            Last Modified: 2026-04-02
            Requires: PowerShell 5.1+ / Windows only

            WinHTTP scope requires local administrator privileges (netsh winhttp set proxy).
            WinINET writes to HKCU (no elevation needed, applies to current user).
            Environment scope sets User-level variables via
            [System.Environment]::SetEnvironmentVariable(..., [User]) — these persist across
            sessions and are visible to all processes running as the current user.
            Process-level env vars ($env:) are also updated for immediate effect.

            WARNING: The Environment scope writes proxy URLs to User-level environment
            variables that survive logoff/reboot. Use Remove-ProxyConfiguration to clean up.

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-winhttp
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ProxyServer,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$BypassList,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^https?://')]
        [string]$AutoConfigURL,

        [Parameter(Mandatory = $false)]
        [ValidateSet('WinINET', 'WinHTTP', 'Environment', 'All')]
        [string[]]$Scope = 'All'
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting proxy configuration"

        # Validate that at least one actionable parameter is provided
        if (-not $ProxyServer -and -not $AutoConfigURL) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new('You must specify at least -ProxyServer or -AutoConfigURL.'),
                    'MissingProxyParameter',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $null
                )
            )
        }

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

            if ($PSCmdlet.ShouldProcess('WinINET (Internet Settings registry)', 'Set proxy configuration')) {
                try {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Configuring WinINET proxy settings"

                    if ($ProxyServer) {
                        Set-ItemProperty -Path $winInetPath -Name 'ProxyEnable' -Value 1 -Type DWord -ErrorAction Stop
                        Set-ItemProperty -Path $winInetPath -Name 'ProxyServer' -Value $ProxyServer -Type String -ErrorAction Stop
                        Write-Verbose "[$($MyInvocation.MyCommand)] WinINET proxy enabled: $ProxyServer"
                    }

                    if ($BypassList) {
                        Set-ItemProperty -Path $winInetPath -Name 'ProxyOverride' -Value $BypassList -Type String -ErrorAction Stop
                        Write-Verbose "[$($MyInvocation.MyCommand)] WinINET bypass list: $BypassList"
                    }

                    if ($AutoConfigURL) {
                        Set-ItemProperty -Path $winInetPath -Name 'AutoConfigURL' -Value $AutoConfigURL -Type String -ErrorAction Stop
                        Write-Verbose "[$($MyInvocation.MyCommand)] WinINET auto-config URL: $AutoConfigURL"
                    }

                    Write-Information -MessageData '[OK] WinINET proxy configured successfully'
                } catch {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to configure WinINET proxy: $_"
                }
            }
        }

        # -- WinHTTP (netsh winhttp) --
        if ($resolvedScopes -contains 'WinHTTP') {
            if (-not $ProxyServer) {
                Write-Warning "[$($MyInvocation.MyCommand)] WinHTTP scope requires -ProxyServer. Skipping WinHTTP configuration."
            } else {
                if ($PSCmdlet.ShouldProcess('WinHTTP (netsh winhttp)', 'Set proxy configuration')) {
                    try {
                        if (-not (Test-IsAdministrator)) {
                            throw [System.UnauthorizedAccessException]::new('WinHTTP scope requires Administrator privileges.')
                        }

                        Write-Verbose "[$($MyInvocation.MyCommand)] Configuring WinHTTP proxy settings"

                        $netshPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
                        if (-not (Test-Path -Path $netshPath -PathType Leaf)) {
                            throw "netsh.exe not found at '$netshPath'"
                        }

                        $netshArgs = @('winhttp', 'set', 'proxy', "proxy-server=$ProxyServer")
                        if ($BypassList) {
                            $netshArgs += "bypass-list=$BypassList"
                        }

                        Write-Verbose "[$($MyInvocation.MyCommand)] Running: netsh $($netshArgs -join ' ')"
                        $netshResult = Invoke-NativeCommand -FilePath $netshPath -ArgumentList $netshArgs
                        $netshExitCode = $netshResult.ExitCode

                        if ($netshExitCode -ne 0) {
                            $outputText = $netshResult.Output
                            Write-Error "[$($MyInvocation.MyCommand)] netsh winhttp set proxy failed (exit code $netshExitCode): $outputText"
                        } else {
                            Write-Information -MessageData '[OK] WinHTTP proxy configured successfully'
                        }
                    } catch {
                        Write-Error "[$($MyInvocation.MyCommand)] Failed to configure WinHTTP proxy: $_"
                    }
                }
            }
        }

        # -- Environment variables --
        if ($resolvedScopes -contains 'Environment') {
            if (-not $ProxyServer) {
                Write-Warning "[$($MyInvocation.MyCommand)] Environment scope requires -ProxyServer. Skipping environment configuration."
            } else {
                if ($PSCmdlet.ShouldProcess('Environment variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY)', 'Set proxy configuration')) {
                    try {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Configuring proxy environment variables"

                        # Build proxy URL (add http:// scheme if not present)
                        $proxyUrl = if ($ProxyServer -match '^https?://') { $ProxyServer } else { "http://$ProxyServer" }

                        # Set Process-level (immediate effect)
                        $env:HTTP_PROXY  = $proxyUrl
                        $env:HTTPS_PROXY = $proxyUrl
                        Write-Verbose "[$($MyInvocation.MyCommand)] HTTP_PROXY and HTTPS_PROXY set to: $proxyUrl"

                        if ($BypassList) {
                            # Convert semicolon-separated WinINET format to comma-separated NO_PROXY format
                            $noProxy = ($BypassList -replace '<local>', 'localhost' -replace ';', ',').Trim()
                            $env:NO_PROXY = $noProxy
                            Write-Verbose "[$($MyInvocation.MyCommand)] NO_PROXY set to: $noProxy"
                        }

                        # Set User-level (persistent across sessions)
                        try {
                            [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', $proxyUrl, [System.EnvironmentVariableTarget]::User)
                            [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', $proxyUrl, [System.EnvironmentVariableTarget]::User)
                            if ($BypassList) {
                                [System.Environment]::SetEnvironmentVariable('NO_PROXY', $noProxy, [System.EnvironmentVariableTarget]::User)
                            }
                            Write-Verbose "[$($MyInvocation.MyCommand)] User-level environment variables persisted"
                        } catch {
                            Write-Warning "[$($MyInvocation.MyCommand)] Failed to persist User-level environment variables: $_. Process-level variables were set successfully."
                        }

                        Write-Information -MessageData '[OK] Proxy environment variables configured successfully'
                    } catch {
                        Write-Error "[$($MyInvocation.MyCommand)] Failed to configure proxy environment variables: $_"
                    }
                }
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed proxy configuration"
    }
}
