#Requires -Version 5.1

function Sync-NTPTime {
    <#
    .SYNOPSIS
        Forces NTP time resynchronization on Windows machines

    .DESCRIPTION
        Forces a resynchronization of the Windows Time Service (w32tm) on one or more
        local or remote machines. Optionally restarts the Windows Time service before
        resyncing to ensure a clean state. Parses the output of w32tm /resync to report
        success or failure per machine, supporting both English and French OS locales.

        Uses Invoke-Command for uniform local and remote execution, enabling consistent
        behavior and straightforward mocking in tests. Each machine is processed
        independently with per-machine error isolation -- a failure on one target does
        not prevent processing of subsequent targets.

        Supports -WhatIf and -Confirm via SupportsShouldProcess. Since ConfirmImpact is
        Medium and the default ConfirmPreference is High, the function does not prompt by
        default. Pass -Confirm to force a prompt, or -Confirm:$false to suppress it
        explicitly in automation contexts.

    .PARAMETER ComputerName
        One or more computer names to resynchronize. Accepts pipeline input.
        Defaults to the local machine ($env:COMPUTERNAME). Each value must be
        a non-empty string.

    .PARAMETER RestartService
        When specified, restarts the Windows Time service (w32time) on each target
        machine before running w32tm /resync. This can help recover from a stale
        service state. The restart action also goes through ShouldProcess confirmation.

    .EXAMPLE
        Sync-NTPTime

        Forces an NTP resync on the local machine using default parameters.

    .EXAMPLE
        Sync-NTPTime -ComputerName 'SRV-DC01'

        Forces an NTP resync on a single remote machine.

    .EXAMPLE
        Sync-NTPTime -ComputerName 'SRV-DC01', 'SRV-DC02' -RestartService -Verbose

        Restarts the w32time service then forces an NTP resync on two remote machines,
        with verbose logging enabled.

    .EXAMPLE
        Get-Content -Path 'C:\\Admin\\servers.txt' | Sync-NTPTime -RestartService

        Reads a list of server names from a file and pipelines them into Sync-NTPTime,
        restarting the w32time service on each before resyncing.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-03-12
        Requires: PowerShell 5.1+ / Windows only
        Permissions: Requires admin rights (local and remote) to restart services
                     and run w32tm /resync. Remote targets require PSRemoting enabled.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [switch]$RestartService
    )

    begin {
        Set-StrictMode -Version Latest
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting - PowerShell $($PSVersionTable.PSVersion)"

        # Scriptblock: force NTP resynchronization via w32tm
        $resyncScriptBlock = {
            $w32tmPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\\w32tm.exe'
            if (-not (Test-Path -Path $w32tmPath)) {
                throw "[ERROR] w32tm.exe not found at '$w32tmPath'"
            }
            $rawOutput = & w32tm.exe /resync 2>&1

            [PSCustomObject]@{
                Output   = ($rawOutput | Out-String).Trim()
                ExitCode = $LASTEXITCODE
            }
        }

        # Scriptblock: restart the Windows Time service
        $restartScriptBlock = {
            Restart-Service -Name 'w32time' -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        }

        # Locale-agnostic success pattern (EN + FR)
        $successPattern = '(The command completed successfully|Sending resync command to local computer|La commande s.est correctement|Envoi de la commande de resynchronisation)'
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Processing: $targetComputer"
                $isLocal = ($targetComputer -eq $env:COMPUTERNAME)
                $serviceRestarted = $false

                # Optionally restart w32time service before resync
                if ($RestartService) {
                    if ($PSCmdlet.ShouldProcess($targetComputer, 'Restart Windows Time service (w32time)')) {
                        Write-Verbose "[$($MyInvocation.MyCommand)] Restarting w32time on '$targetComputer'..."
                        if ($isLocal) {
                            $null = Invoke-Command -ScriptBlock $restartScriptBlock
                        } else {
                            $null = Invoke-Command -ComputerName $targetComputer -ScriptBlock $restartScriptBlock
                        }
                        $serviceRestarted = $true
                        Write-Verbose "[$($MyInvocation.MyCommand)] w32time restarted on '$targetComputer'"
                    }
                }

                # Force NTP resynchronization
                if ($PSCmdlet.ShouldProcess($targetComputer, 'Force NTP resynchronization')) {
                    Write-Verbose "[$($MyInvocation.MyCommand)] Running w32tm /resync on '$targetComputer'..."
                    if ($isLocal) {
                        $resyncResult = Invoke-Command -ScriptBlock $resyncScriptBlock
                    } else {
                        $resyncResult = Invoke-Command -ComputerName $targetComputer -ScriptBlock $resyncScriptBlock
                    }

                    $outputText = [string]$resyncResult.Output
                    $exitCode = [int]$resyncResult.ExitCode
                    $isSuccess = ($exitCode -eq 0) -and ($outputText -match $successPattern)

                    if ($isSuccess) {
                        Write-Verbose "[$($MyInvocation.MyCommand)] [OK] Resync succeeded on '$targetComputer'"
                    } else {
                        Write-Warning "[$($MyInvocation.MyCommand)] Resync may have failed on '$targetComputer': $outputText"
                    }

                    [PSCustomObject]@{
                        PSTypeName       = 'PSWinOps.NtpResyncResult'
                        ComputerName     = $targetComputer
                        Success          = $isSuccess
                        ServiceRestarted = $serviceRestarted
                        Message          = $outputText
                        Timestamp        = Get-Date -Format 'o'
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to sync NTP on '$targetComputer': $_"
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
