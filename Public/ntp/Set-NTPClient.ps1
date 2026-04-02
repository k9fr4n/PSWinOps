#Requires -Version 5.1

function Set-NTPClient {
    <#
        .SYNOPSIS
            Configures Windows Time Service (W32Time) to synchronize with specified NTP servers

        .DESCRIPTION
            This function configures the Windows Time Service (W32Time) to use external NTP servers
            for time synchronization. It sets the NTP server list, phase offset tolerance, and polling
            intervals via registry and w32tm commands. The function ensures the service is running,
            applies the configuration, restarts the service, forces synchronization, and verifies
            the final state.

            Requires local administrator privileges to modify registry and manage the W32Time service.

        .PARAMETER NtpServers
            Array of NTP server FQDNs or IP addresses to use for time synchronization.
            At least one server must be specified.

        .PARAMETER MaxPhaseOffset
            Maximum allowed phase offset in seconds before the clock is corrected.
            Valid range: 1 to 3600 seconds. Default: 1 second.

        .PARAMETER SpecialPollInterval
            Interval in seconds for special polling operations.
            Valid range: 1 to 86400 seconds. Default: 300 seconds (5 minutes).

        .PARAMETER MinPollInterval
            Minimum poll interval as a power of 2 (2^n seconds).
            Valid range: 0 to 17. Default: 6 (2^6 = 64 seconds).

        .PARAMETER MaxPollInterval
            Maximum poll interval as a power of 2 (2^n seconds).
            Must be greater than MinPollInterval. Valid range: 0 to 17. Default: 10 (2^10 = 1024 seconds).

        .EXAMPLE
            Set-NTPClient -NtpServers 'time.windows.com', 'pool.ntp.org'
            Configures W32Time with two public NTP servers using default poll settings.

        .EXAMPLE
            Set-NTPClient -NtpServers 'time.windows.com', 'pool.ntp.org' -MaxPhaseOffset 5 -Verbose
            Configures W32Time with custom NTP servers and a 5-second phase offset tolerance,
            with verbose logging enabled.

        .EXAMPLE
            Set-NTPClient -NtpServers 'ntp.example.com' -SpecialPollInterval 600 -MinPollInterval 7 -MaxPollInterval 12 -WhatIf
            Shows what would happen if the configuration were applied with custom poll intervals.

        .OUTPUTS
            None
            This function does not produce pipeline output.

        .NOTES
            Author: Franck SALLET
            Version: 2.2.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+, Local Administrator rights
            Permissions: Administrator required to modify registry and manage W32Time service

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$NtpServers,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3600)]
        [int]$MaxPhaseOffset = 1,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$SpecialPollInterval = 300,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 17)]
        [int]$MinPollInterval = 6,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 17)]
        [int]$MaxPollInterval = 10
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        if (-not (Test-IsAdministrator)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.UnauthorizedAccessException]::new('This operation requires Administrator privileges.'),
                    'ElevationRequired',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
            )
        }

        if ($MaxPollInterval -le $MinPollInterval) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new(
                        "MaxPollInterval ($MaxPollInterval) must be greater than MinPollInterval ($MinPollInterval)"
                    ),
                    'InvalidPollIntervalRange',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $null
                )
            )
        }

        $registryPaths = @{
            Config     = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config'
            NtpClient  = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient'
            Parameters = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
        }

        $w32tmPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\w32tm.exe'
    }

    process {
        if (-not $PSCmdlet.ShouldProcess('Windows Time Service (W32Time)', 'Configure NTP synchronization')) {
            return
        }

        try {
            # Step 1: Ensure W32Time service exists and is running
            Write-Verbose "[$($MyInvocation.MyCommand)] Checking Windows Time Service status..."
            $service = Get-Service -Name 'w32time' -ErrorAction SilentlyContinue

            if (-not $service) {
                Write-Warning "[$($MyInvocation.MyCommand)] Windows Time Service not found - registering service..."
                $null = Invoke-NativeCommand -FilePath $w32tmPath -ArgumentList @('/register')
                Start-Sleep -Seconds 2
                $service = Get-Service -Name 'w32time' -ErrorAction Stop
            }

            if ($service.Status -ne 'Running') {
                Write-Warning "[$($MyInvocation.MyCommand)] Service is stopped - starting..."
                Start-Service -Name 'w32time' -ErrorAction Stop
                Write-Information -MessageData '[OK] Windows Time Service started successfully'
            } else {
                Write-Verbose "[$($MyInvocation.MyCommand)] Service is already running"
            }

            # Step 2: Verify registry paths exist
            Write-Verbose "[$($MyInvocation.MyCommand)] Verifying registry paths..."
            foreach ($pathInfo in $registryPaths.GetEnumerator()) {
                if (-not (Test-Path -Path $pathInfo.Value)) {
                    throw "Registry key not found: $($pathInfo.Value)"
                }
            }

            # Step 3: Build NTP server list with default flags
            Write-Verbose "[$($MyInvocation.MyCommand)] Building NTP server list..."
            $serverList = ($NtpServers | ForEach-Object {
                    if ($_ -match '^([^,]+)(,0x[0-9a-fA-F]+)?$') {
                        $serverName = $matches[1]
                        $existingFlag = $matches[2]
                        if ($existingFlag) {
                            $_
                        } else {
                            "$serverName,0x9"
                        }
                    } else {
                        Write-Warning "[$($MyInvocation.MyCommand)] Unusual server format: $_ - applying default flag"
                        "$_,0x9"
                    }
                }) -join ' '

            Write-Verbose "[$($MyInvocation.MyCommand)] NTP servers: $serverList"
            Write-Verbose "[$($MyInvocation.MyCommand)] MaxAllowedPhaseOffset: $MaxPhaseOffset second(s)"

            # Step 4: Apply NTP configuration directly via registry
            Write-Verbose "[$($MyInvocation.MyCommand)] Writing NTP configuration to registry..."

            Set-ItemProperty -Path $registryPaths['Parameters'] -Name 'NtpServer' -Value $serverList -Type String -ErrorAction Stop
            Set-ItemProperty -Path $registryPaths['Parameters'] -Name 'Type' -Value 'NTP' -Type String -ErrorAction Stop
            Set-ItemProperty -Path $registryPaths['Config'] -Name 'MaxAllowedPhaseOffset' -Value $MaxPhaseOffset -Type DWord -ErrorAction Stop

            $null = Invoke-NativeCommand -FilePath $w32tmPath -ArgumentList @('/config', '/update')

            Write-Information -MessageData "[OK] NTP servers configured: $serverList"

            # Step 5: Set poll intervals in registry
            Write-Verbose "[$($MyInvocation.MyCommand)] Setting poll intervals in registry..."
            Set-ItemProperty -Path $registryPaths['NtpClient'] -Name 'SpecialPollInterval' -Value $SpecialPollInterval -ErrorAction Stop
            Set-ItemProperty -Path $registryPaths['Config'] -Name 'MinPollInterval' -Value $MinPollInterval -ErrorAction Stop
            Set-ItemProperty -Path $registryPaths['Config'] -Name 'MaxPollInterval' -Value $MaxPollInterval -ErrorAction Stop

            $minSeconds = [math]::Pow(2, $MinPollInterval)
            $maxSeconds = [math]::Pow(2, $MaxPollInterval)
            Write-Information -MessageData "[OK] Poll intervals set: Special=$SpecialPollInterval s, Min=$minSeconds s, Max=$maxSeconds s"

            # Step 6: Restart W32Time service
            Write-Verbose "[$($MyInvocation.MyCommand)] Restarting Windows Time Service..."
            Restart-Service -Name 'w32time' -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Information -MessageData '[OK] Windows Time Service restarted successfully'

            # Step 7: Force synchronization
            Write-Verbose "[$($MyInvocation.MyCommand)] Forcing immediate NTP synchronization..."
            $syncResult = Invoke-NativeCommand -FilePath $w32tmPath -ArgumentList @('/resync', '/force')
            $syncExitCode = $syncResult.ExitCode

            # Exit code is the authoritative success indicator (locale-agnostic).
            # w32tm output text varies by OS language and is logged for diagnostics only.
            $isSyncSuccessful = ($syncExitCode -eq 0)

            if ($isSyncSuccessful) {
                Write-Information -MessageData '[OK] Time synchronization completed successfully'
                Write-Verbose "[$($MyInvocation.MyCommand)] w32tm /resync output: $($syncResult.Output)"
            } else {
                Write-Warning "[$($MyInvocation.MyCommand)] Time synchronization failed (exit code $syncExitCode):"
                ($syncResult.Output -split '\r?\n') | ForEach-Object { Write-Warning "[$($MyInvocation.MyCommand)] $_" }
            }

            # Step 8: Verify configuration (locale-agnostic)
            # Read registry directly and use w32tm /query /source to avoid locale-dependent label parsing.
            Start-Sleep -Seconds 3
            Write-Verbose "[$($MyInvocation.MyCommand)] Verifying final configuration..."

            try {
                $verifyServers = (Get-ItemProperty -Path $registryPaths['Parameters'] -Name 'NtpServer' -ErrorAction Stop).NtpServer
                Write-Information -MessageData "[OK] Configured servers (registry): $verifyServers"
            } catch {
                Write-Warning "[$($MyInvocation.MyCommand)] Could not read back NtpServer from registry: $_"
            }

            try {
                # w32tm /query /source returns only the source name without any locale-dependent label.
                $sourceResult = Invoke-NativeCommand -FilePath $w32tmPath -ArgumentList @('/query', '/source')
                $sourceText = $sourceResult.Output
                Write-Information -MessageData "[OK] Active NTP source: $sourceText"
            } catch {
                Write-Warning "[$($MyInvocation.MyCommand)] Could not query active NTP source: $_"
            }

            Write-Information -MessageData '[OK] Windows Time Service configuration completed successfully'
        } catch [System.UnauthorizedAccessException] {
            Write-Error "[$($MyInvocation.MyCommand)] Access denied - Administrator privileges required: $_"
            throw
        } catch [System.InvalidOperationException] {
            Write-Error "[$($MyInvocation.MyCommand)] Service operation failed: $_"
            throw
        } catch {
            Write-Error "[$($MyInvocation.MyCommand)] Unexpected error during NTP configuration: $_"
            throw
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}