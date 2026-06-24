function Invoke-WindowsUpdateReset {
    <#
    .SYNOPSIS
        Performs the low-level Windows Update component reset operations on the local machine.
    .DESCRIPTION
        Script-block body extracted from Reset-WindowsUpdateComponent so it can be unit-tested
        independently of Invoke-RemoteOrLocal. Called locally as-is; passed as a serialised
        script block for remote execution via Invoke-RemoteOrLocal.
    .PARAMETER DoNetworkReset
        When $true, also resets the Winsock catalog and WinHTTP proxy (requires a reboot).
    #>
    [CmdletBinding()]
    param(
        [bool]$DoNetworkReset = $false
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $notes    = [System.Collections.Generic.List[string]]::new()

    # ----------------------------------------------------------------
    # Step 1 — Stop services: BITS, wuauserv, appidsvc, cryptsvc
    # ----------------------------------------------------------------
    $servicesToStop  = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
    $stoppedServices = [System.Collections.Generic.List[string]]::new()

    foreach ($svcName in $servicesToStop) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Stopped') {
                Stop-Service -Name $svcName -Force -ErrorAction Stop
                $stoppedServices.Add($svcName)
            }
        } catch {
            $failures.Add("Stop service '$svcName': $_")
        }
    }

    # Allow services to fully stop before filesystem operations
    Start-Sleep -Seconds 2

    # ----------------------------------------------------------------
    # Step 2 — Delete qmgr*.dat files
    # ----------------------------------------------------------------
    $qmgrFolder = Join-Path -Path $env:ALLUSERSPROFILE `
        -ChildPath 'Application Data\Microsoft\Network\Downloader'
    $qmgrCount = 0

    if (Test-Path -Path $qmgrFolder -PathType Container) {
        $qmgrFiles = Get-ChildItem -Path $qmgrFolder -Filter 'qmgr*.dat' `
            -Force -ErrorAction SilentlyContinue
        foreach ($f in $qmgrFiles) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $qmgrCount++
            } catch {
                $failures.Add("Delete '$($f.FullName)': $_")
            }
        }
    }

    # ----------------------------------------------------------------
    # Step 3 — Backup-rename SoftwareDistribution and Catroot2
    # ----------------------------------------------------------------
    $sdPath     = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution'
    $sdBak      = "${sdPath}.bak"
    $cr2Path    = Join-Path -Path $env:SystemRoot -ChildPath 'System32\Catroot2'
    $cr2Bak     = "${cr2Path}.bak"
    $sdBackupResult  = ''
    $cr2BackupResult = ''

    foreach ($pair in @(
        [pscustomobject]@{ Src = $sdPath;  Bak = $sdBak;  ResultVar = 'sd'  }
        [pscustomobject]@{ Src = $cr2Path; Bak = $cr2Bak; ResultVar = 'cr2' }
    )) {
        if (Test-Path -Path $pair.Src -PathType Container) {
            if (Test-Path -Path $pair.Bak) {
                try {
                    Remove-Item -LiteralPath $pair.Bak -Recurse -Force -ErrorAction Stop
                } catch {
                    $suffix   = Get-Date -Format 'yyyyMMddHHmmss'
                    $pair.Bak = "$($pair.Bak).$suffix"
                }
            }
            try {
                Rename-Item -LiteralPath $pair.Src -NewName ([System.IO.Path]::GetFileName($pair.Bak)) `
                    -ErrorAction Stop
                if ($pair.ResultVar -eq 'sd') {
                    $sdBackupResult = $pair.Bak
                } else {
                    $cr2BackupResult = $pair.Bak
                }
            } catch {
                $failures.Add("Backup '$($pair.Src)': $_")
                if ($pair.ResultVar -eq 'sd') {
                    $sdBackupResult = "Skipped: $_"
                } else {
                    $cr2BackupResult = "Skipped: $_"
                }
            }
        } else {
            if ($pair.ResultVar -eq 'sd') {
                $sdBackupResult = 'Skipped: folder not present'
            } else {
                $cr2BackupResult = 'Skipped: folder not present'
            }
        }
    }

    # ----------------------------------------------------------------
    # Step 4 — Remove WindowsUpdate.log
    # ----------------------------------------------------------------
    $wuLog = Join-Path -Path $env:SystemRoot -ChildPath 'WindowsUpdate.log'
    if (Test-Path -Path $wuLog -PathType Leaf) {
        try {
            Remove-Item -LiteralPath $wuLog -Force -ErrorAction Stop
        } catch {
            $failures.Add("Remove WindowsUpdate.log: $_")
        }
    }

    # ----------------------------------------------------------------
    # Step 5 — Reset service SDDL for BITS and wuauserv
    # ----------------------------------------------------------------
    $scPath       = Join-Path -Path $env:SystemRoot -ChildPath 'System32\sc.exe'
    $defaultSddl  = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'

    foreach ($svcTarget in @('bits', 'wuauserv')) {
        $scResult = Invoke-NativeCommand -FilePath $scPath `
            -ArgumentList @('sdset', $svcTarget, $defaultSddl)
        if ($scResult.ExitCode -ne 0) {
            $failures.Add("sc.exe sdset $svcTarget exited $($scResult.ExitCode): $($scResult.Output)")
        }
    }

    # ----------------------------------------------------------------
    # Step 6 — Reregister Windows Update DLLs
    # ----------------------------------------------------------------
    $regsvr32Path = Join-Path -Path $env:SystemRoot -ChildPath 'System32\regsvr32.exe'
    $dllNames     = @(
        'atl', 'urlmon', 'mshtml', 'shdocvw', 'browseui', 'jscript', 'vbscript',
        'scrrun', 'msxml', 'msxml3', 'msxml6', 'actxprxy', 'softpub', 'wintrust',
        'dssenh', 'rsaenh', 'gpkcsp', 'sccbase', 'slbcsp', 'cryptdlg', 'oleaut32',
        'ole32', 'shell32', 'initpki', 'wuapi', 'wuaueng', 'wuaueng1', 'wucltui',
        'wups', 'wups2', 'wuweb', 'qmgr', 'qmgrprxy', 'wucltux', 'muweb', 'wuwebv'
    )
    $dllsRegistered = 0
    $dllsFailed     = 0

    foreach ($dll in $dllNames) {
        $dllPath = Join-Path -Path $env:SystemRoot -ChildPath "System32\${dll}.dll"
        if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
            $dllsFailed++
            $failures.Add("DLL not found (non-fatal): $dllPath")
            continue
        }
        $regResult = Invoke-NativeCommand -FilePath $regsvr32Path `
            -ArgumentList @('/s', $dllPath)
        if ($regResult.ExitCode -eq 0) {
            $dllsRegistered++
        } else {
            $dllsFailed++
            $failures.Add("regsvr32 failed for '${dll}.dll' (exit $($regResult.ExitCode)): $($regResult.Output)")
        }
    }

    # ----------------------------------------------------------------
    # Steps 7 & 8 — Network reset (optional, gated by DoNetworkReset)
    # ----------------------------------------------------------------
    $networkResetPerformed = $false
    $rebootRequired        = $false
    $netshPath             = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'

    if ($DoNetworkReset) {
        $winsockResult = Invoke-NativeCommand -FilePath $netshPath `
            -ArgumentList @('winsock', 'reset')
        if ($winsockResult.ExitCode -eq 0) {
            $networkResetPerformed = $true
            $rebootRequired        = $true
        } else {
            $failures.Add("netsh winsock reset exited $($winsockResult.ExitCode): $($winsockResult.Output)")
        }

        $winhttpResult = Invoke-NativeCommand -FilePath $netshPath `
            -ArgumentList @('winhttp', 'reset', 'proxy')
        if ($winhttpResult.ExitCode -ne 0) {
            $failures.Add("netsh winhttp reset proxy exited $($winhttpResult.ExitCode): $($winhttpResult.Output)")
        }
    }

    # ----------------------------------------------------------------
    # Step 9 — Restart services: cryptsvc, appidsvc, wuauserv, BITS
    # ----------------------------------------------------------------
    $servicesToStart  = @('cryptsvc', 'appidsvc', 'wuauserv', 'BITS')
    $startedServices  = [System.Collections.Generic.List[string]]::new()

    foreach ($svcName in $servicesToStart) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                Start-Service -Name $svcName -ErrorAction Stop
                $startedServices.Add($svcName)
            }
        } catch {
            $failures.Add("Start service '$svcName': $_")
        }
    }

    # ----------------------------------------------------------------
    # Step 10 — Trigger detection: wuauclt, fall back to usoclient
    # ----------------------------------------------------------------
    $wuaucltPath   = Join-Path -Path $env:SystemRoot -ChildPath 'System32\wuauclt.exe'
    $usoclientPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\usoclient.exe'

    if (Test-Path -LiteralPath $wuaucltPath -PathType Leaf) {
        $wuaucltResult = Invoke-NativeCommand -FilePath $wuaucltPath `
            -ArgumentList @('/resetauthorization', '/detectnow')
        if ($wuaucltResult.ExitCode -ne 0) {
            $notes.Add("wuauclt exited $($wuaucltResult.ExitCode); attempting usoclient fallback.")
            if (Test-Path -LiteralPath $usoclientPath -PathType Leaf) {
                $usoResult = Invoke-NativeCommand -FilePath $usoclientPath `
                    -ArgumentList @('StartScan')
                if ($usoResult.ExitCode -ne 0) {
                    $failures.Add("usoclient StartScan exited $($usoResult.ExitCode): $($usoResult.Output)")
                } else {
                    $notes.Add('Detection triggered via usoclient StartScan.')
                }
            } else {
                $notes.Add('usoclient.exe not found; detection trigger skipped.')
            }
        }
    } else {
        $notes.Add('wuauclt.exe not found on this OS build; falling back to usoclient StartScan.')
        if (Test-Path -LiteralPath $usoclientPath -PathType Leaf) {
            $usoResult = Invoke-NativeCommand -FilePath $usoclientPath `
                -ArgumentList @('StartScan')
            if ($usoResult.ExitCode -ne 0) {
                $failures.Add("usoclient StartScan exited $($usoResult.ExitCode): $($usoResult.Output)")
            } else {
                $notes.Add('Detection triggered via usoclient StartScan.')
            }
        } else {
            $notes.Add('Neither wuauclt.exe nor usoclient.exe found; detection trigger skipped.')
        }
    }

    # ----------------------------------------------------------------
    # Determine overall status
    # ----------------------------------------------------------------
    $status = if ($failures.Count -eq 0) {
        'Succeeded'
    } else {
        'PartialSuccess'
    }

    return [PSCustomObject]@{
        Status                     = $status
        ServicesStopped            = @($stoppedServices)
        ServicesStarted            = @($startedServices)
        SoftwareDistributionBackup = $sdBackupResult
        Catroot2Backup             = $cr2BackupResult
        QmgrFilesDeleted           = $qmgrCount
        DllsReregistered           = $dllsRegistered
        DllsFailed                 = $dllsFailed
        NetworkResetPerformed      = $networkResetPerformed
        RebootRequired             = $rebootRequired
        Failures                   = @($failures)
        Notes                      = @($notes)
    }
}
