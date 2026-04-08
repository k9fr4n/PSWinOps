#Requires -Version 5.1
function Uninstall-WindowsUpdate {
    <#
        .SYNOPSIS
            Uninstalls previously installed Windows Updates by KB article ID

        .DESCRIPTION
            Removes one or more Windows Updates from local or remote computers using
            wusa.exe in quiet mode. Each KB is validated as installed via Get-HotFix
            before attempting uninstallation. Provides detailed exit code mapping for
            troubleshooting.
            Use this function to rollback problematic updates that cause issues in
            your environment.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not required for local operations.

        .PARAMETER KBArticleID
            One or more KB article IDs to uninstall. Accepts values with or without
            the KB prefix (e.g., 'KB5034441' or '5034441').

        .PARAMETER AutoReboot
            When specified, uses /forcerestart instead of /norestart with wusa.exe.
            The computer will restart automatically after successful uninstallation.

        .EXAMPLE
            Uninstall-WindowsUpdate -KBArticleID 'KB5034441'

            Uninstalls KB5034441 from the local computer without automatic reboot.

        .EXAMPLE
            Uninstall-WindowsUpdate -ComputerName 'SRV01' -KBArticleID 'KB5034441' -AutoReboot

            Uninstalls KB5034441 from SRV01 with automatic reboot.

        .EXAMPLE
            'SRV01', 'SRV02' | Uninstall-WindowsUpdate -KBArticleID 'KB5034441', 'KB5035432'

            Uninstalls two KBs from two servers via pipeline.

        .OUTPUTS
            PSWinOps.WindowsUpdateUninstallResult
            Returns objects with ComputerName, KBArticle, Result, ExitCode,
            RebootRequired, and Timestamp properties.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-08
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges

            wusa.exe exit codes:
                0       Success
                3010    Success, reboot required
                1641    Success, reboot initiated
                2359303 Not applicable / not uninstallable
                87      Invalid parameter

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/wua_sdk/portal-client
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.WindowsUpdateUninstallResult')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KBArticleID,

        [Parameter(Mandatory = $false)]
        [switch]$AutoReboot
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $normalizedKBIds = $KBArticleID | ForEach-Object -Process { $_ -replace '^KB', '' }
        $kbCsv = $normalizedKBIds -join ','
        $kbDisplay = ($normalizedKBIds | ForEach-Object -Process { "KB$_" }) -join ', '

        $uninstallScriptBlock = {
            param(
                [string]$KBCsv,
                [bool]$UseForceRestart
            )

            $kbList = $KBCsv -split ','

            foreach ($kb in $kbList) {
                $kbId = "KB$kb"

                # Check if KB is installed
                $installed = $null
                try {
                    $installed = Get-HotFix -Id $kbId -ErrorAction SilentlyContinue
                } catch {
                    $installed = $null
                }

                if (-not $installed) {
                    [PSCustomObject]@{
                        KBArticle      = $kbId
                        Result         = 'NotInstalled'
                        ExitCode       = -1
                        RebootRequired = $false
                    }
                    continue
                }

                # Build wusa.exe arguments
                $restartFlag = if ($UseForceRestart) {
                    '/forcerestart'
                } else {
                    '/norestart'
                }

                try {
                    $process = Start-Process -FilePath 'wusa.exe' `
                        -ArgumentList @('/uninstall', "/kb:$kb", '/quiet', $restartFlag) `
                        -Wait -PassThru -NoNewWindow -ErrorAction Stop

                    $exitCode = $process.ExitCode
                } catch {
                    [PSCustomObject]@{
                        KBArticle      = $kbId
                        Result         = 'Failed'
                        ExitCode       = -2
                        RebootRequired = $false
                    }
                    continue
                }

                $result = switch ($exitCode) {
                    0 {
                        'Succeeded'
                    }
                    3010 {
                        'SucceededRebootRequired'
                    }
                    1641 {
                        'SucceededRebootRequired'
                    }
                    2359303 {
                        'NotUninstallable'
                    }
                    default {
                        'Failed'
                    }
                }

                $rebootNeeded = ($exitCode -eq 3010) -or ($exitCode -eq 1641)

                [PSCustomObject]@{
                    KBArticle      = $kbId
                    Result         = $result
                    ExitCode       = $exitCode
                    RebootRequired = $rebootNeeded
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$computer'"

            if (-not $PSCmdlet.ShouldProcess("$computer — $kbDisplay", 'Uninstall Windows Update')) {
                continue
            }

            try {
                $invokeParams = @{
                    ComputerName = $computer
                    ScriptBlock  = $uninstallScriptBlock
                    ArgumentList = @($kbCsv, [bool]$AutoReboot)
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $results = Invoke-RemoteOrLocal @invokeParams

                $rebootNeeded = $false
                foreach ($entry in $results) {
                    if ($entry.RebootRequired) {
                        $rebootNeeded = $true
                    }

                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] '$computer' — $($entry.KBArticle): $($entry.Result) (exit: $($entry.ExitCode))"

                    [PSCustomObject]@{
                        PSTypeName     = 'PSWinOps.WindowsUpdateUninstallResult'
                        ComputerName   = $computer
                        KBArticle      = $entry.KBArticle
                        Result         = $entry.Result
                        ExitCode       = $entry.ExitCode
                        RebootRequired = $entry.RebootRequired
                        Timestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }

                if ($rebootNeeded) {
                    Write-Warning -Message "[$($MyInvocation.MyCommand)] '$computer' requires a reboot to complete uninstallation"
                }
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${computer}': $_"
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
