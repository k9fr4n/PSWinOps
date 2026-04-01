#Requires -Version 5.1
function Get-ProxyConfiguration {
    <#
        .SYNOPSIS
            Retrieves proxy configuration from all three Windows proxy layers

        .DESCRIPTION
            Queries proxy settings from three distinct sources:
            - WinINET (Internet Settings registry): used by browsers and .NET apps
            - WinHTTP (netsh winhttp): used by system services and PowerShell
            - Environment variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY)

            Returns a single object consolidating all three layers for quick diagnosis
            of proxy misconfigurations.

        .EXAMPLE
            Get-ProxyConfiguration

            Returns the current proxy configuration from all three layers on the local machine.

        .EXAMPLE
            Get-ProxyConfiguration -Verbose

            Returns proxy configuration with verbose output showing each layer being queried.

        .EXAMPLE
            Get-ProxyConfiguration | Select-Object -Property WinInet*, WinHttp*

            Returns only WinINET and WinHTTP proxy settings, excluding environment variables.

        .OUTPUTS
            PSWinOps.ProxyConfiguration
            Current proxy settings from system and user scopes.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-20
            Requires: PowerShell 5.1+ / Windows only

            WinINET settings are read from HKCU and reflect the current user's proxy.
            WinHTTP settings are read via netsh winhttp show proxy.
            Environment variables check both uppercase and lowercase variants.
            This function is local-only by design (HKCU is user-specific, env vars are session-specific).

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-winhttp
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ProxyConfiguration')]
    param()

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting proxy configuration retrieval"
    }

    process {
        # -- WinINET (Internet Settings registry) --
        Write-Verbose "[$($MyInvocation.MyCommand)] Querying WinINET proxy settings from registry"
        $winInetPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

        try {
            $inetSettings = Get-ItemProperty -Path $winInetPath -ErrorAction Stop

            $winInetEnabled    = [bool]($inetSettings.ProxyEnable)
            $winInetServer     = if ($inetSettings.ProxyServer)   { [string]$inetSettings.ProxyServer }   else { $null }
            $winInetBypass     = if ($inetSettings.ProxyOverride)  { [string]$inetSettings.ProxyOverride }  else { $null }
            $winInetAutoConfig = if ($inetSettings.AutoConfigURL)  { [string]$inetSettings.AutoConfigURL }  else { $null }
        } catch {
            Write-Warning "[$($MyInvocation.MyCommand)] Failed to read WinINET settings: $_"
            $winInetEnabled    = $false
            $winInetServer     = $null
            $winInetBypass     = $null
            $winInetAutoConfig = $null
        }

        # -- WinHTTP (netsh winhttp) --
        Write-Verbose "[$($MyInvocation.MyCommand)] Querying WinHTTP proxy settings via netsh"
        $winHttpEnabled = $false
        $winHttpServer  = $null
        $winHttpBypass  = $null

        try {
            $netshPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
            if (-not (Test-Path -Path $netshPath -PathType Leaf)) {
                Write-Warning "[$($MyInvocation.MyCommand)] netsh.exe not found at '$netshPath'"
            } else {
                $netshResult = Invoke-NativeCommand -FilePath $netshPath -ArgumentList @('winhttp', 'show', 'proxy')
                $netshExitCode = $netshResult.ExitCode

                if ($netshExitCode -ne 0) {
                    Write-Warning "[$($MyInvocation.MyCommand)] netsh winhttp show proxy returned exit code $netshExitCode"
                } else {
                    $outputText = $netshResult.Output
                    Write-Verbose "[$($MyInvocation.MyCommand)] netsh output: $outputText"

                    if ($outputText -notmatch 'Direct access') {
                        $winHttpEnabled = $true

                        if ($outputText -match 'Proxy Server\(s\)\s*:\s*(.+)') {
                            $winHttpServer = $Matches[1].Trim()
                        }
                        if ($outputText -match 'Bypass List\s*:\s*(.+)') {
                            $winHttpBypass = $Matches[1].Trim()
                        }
                    }
                }
            }
        } catch {
            Write-Warning "[$($MyInvocation.MyCommand)] Failed to query WinHTTP settings: $_"
        }

        # -- Environment variables --
        Write-Verbose "[$($MyInvocation.MyCommand)] Querying proxy environment variables"
        $envHttpProxy  = if ($env:HTTP_PROXY)  { $env:HTTP_PROXY }  elseif ($env:http_proxy)  { $env:http_proxy }  else { $null }
        $envHttpsProxy = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } elseif ($env:https_proxy) { $env:https_proxy } else { $null }
        $envNoProxy    = if ($env:NO_PROXY)    { $env:NO_PROXY }    elseif ($env:no_proxy)    { $env:no_proxy }    else { $null }

        # -- Build output object --
        [PSCustomObject]@{
            PSTypeName        = 'PSWinOps.ProxyConfiguration'
            ComputerName      = $env:COMPUTERNAME
            WinInetEnabled    = $winInetEnabled
            WinInetServer     = $winInetServer
            WinInetBypass     = $winInetBypass
            WinInetAutoConfig = $winInetAutoConfig
            WinHttpEnabled    = $winHttpEnabled
            WinHttpServer     = $winHttpServer
            WinHttpBypass     = $winHttpBypass
            EnvHttpProxy      = $envHttpProxy
            EnvHttpsProxy     = $envHttpsProxy
            EnvNoProxy        = $envNoProxy
            Timestamp         = (Get-Date -Format 'o')
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed proxy configuration retrieval"
    }
}
