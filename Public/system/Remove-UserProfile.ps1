#Requires -Version 5.1

function Remove-UserProfile {
    <#
        .SYNOPSIS
            Removes stale user profiles that have not been used within a specified number of days

        .DESCRIPTION
            Enumerates Win32_UserProfile instances via CIM and removes those whose
            LastUseTime exceeds the configured threshold. System and service profiles
            are always excluded. Supports -WhatIf and -Confirm for safe operation.
            Profile folder size is calculated before deletion unless -SkipSizeCalculation
            is specified. Returns a result object for each profile processed.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER OlderThanDays
            Remove profiles not used within this many days. Valid range 1-3650.
            Defaults to 90.

        .PARAMETER ExcludeUser
            One or more usernames to exclude from removal. Supports wildcards.
            System profiles are always excluded regardless of this parameter.

        .PARAMETER SkipSizeCalculation
            Skips profile folder size calculation for faster execution.
            Sets ProfileSizeMB to -1 in the output.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.

        .PARAMETER Force
            Suppresses the confirmation prompt.

        .EXAMPLE
            Remove-UserProfile -WhatIf

            Shows which profiles older than 90 days would be removed on the local machine.

        .EXAMPLE
            Remove-UserProfile -ComputerName 'SRV01' -OlderThanDays 180 -Confirm:$false

            Removes profiles unused for 180+ days on SRV01 without confirmation prompts.

        .EXAMPLE
            'SRV01', 'SRV02' | Remove-UserProfile -ExcludeUser 'admin', 'svc_*' -WhatIf

            Shows which profiles would be removed on two servers, excluding admin
            and any account starting with svc_.

        .OUTPUTS
            PSWinOps.UserProfileRemoval
            Returns objects with ComputerName, UserName, LocalPath, SID, LastUseTime,
            ProfileSizeMB, DaysInactive, Status, ErrorMessage, and Timestamp.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-04-11
            Requires: PowerShell 5.1+ / Windows only
            Requires: Administrator privileges (profile deletion)

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-userprofile
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('PSWinOps.UserProfileRemoval')]
    param(
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 3650)]
        [int]$OlderThanDays = 90,

        [Parameter(Mandatory = $false)]
        [SupportsWildcards()]
        [string[]]$ExcludeUser,

        [Parameter(Mandatory = $false)]
        [switch]$SkipSizeCalculation,

        [Parameter(Mandatory = $false)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting — threshold: $OlderThanDays days"

        if ($Force.IsPresent -and -not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = 'None'
        }

        # System SIDs that must never be removed
        $systemSids = @(
            'S-1-5-18',   # SYSTEM
            'S-1-5-19',   # LOCAL SERVICE
            'S-1-5-20'    # NETWORK SERVICE
        )

        # Path segments that indicate system/default profiles
        $systemPathSegments = @(
            'Default', 'Public', 'systemprofile',
            'LocalService', 'NetworkService', 'Default User', 'All Users'
        )

        $enumerateBlock = {
            param(
                [int]$DaysOld,
                [bool]$CalcSize
            )

            $profiles = @(Get-CimInstance -ClassName 'Win32_UserProfile' -ErrorAction Stop)
            $results = [System.Collections.Generic.List[hashtable]]::new()

            foreach ($prof in $profiles) {
                # Skip system / special profiles
                if ($prof.Special -eq $true) {
                    continue 
                }

                $results.Add(@{
                        SID         = $prof.SID
                        LocalPath   = $prof.LocalPath
                        LastUseTime = $prof.LastUseTime
                        Loaded      = $prof.Loaded
                        SizeMB      = if ($CalcSize -and $prof.LocalPath -and (Test-Path -LiteralPath $prof.LocalPath)) {
                            $sizeBytes = (Get-ChildItem -LiteralPath $prof.LocalPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            [math]::Round(($sizeBytes / 1MB), 2)
                        } else {
                            [double]-1
                        }
                    })
            }

            @($results)
        }

        $removeBlock = {
            param(
                [string]$ProfileSid
            )

            $prof = Get-CimInstance -ClassName 'Win32_UserProfile' -Filter "SID='$ProfileSid'" -ErrorAction Stop
            if ($prof) {
                Remove-CimInstance -InputObject $prof -ErrorAction Stop
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$machine'"

            try {
                # ---- Enumerate eligible profiles ----
                $invokeParams = @{
                    ComputerName = $machine
                    ScriptBlock  = $enumerateBlock
                    ArgumentList = @($OlderThanDays, (-not $SkipSizeCalculation.IsPresent))
                }
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $invokeParams['Credential'] = $Credential
                }

                $rawProfiles = @(Invoke-RemoteOrLocal @invokeParams)
            } catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to enumerate profiles on '${machine}': $_"
                continue
            }

            $cutoff = (Get-Date).AddDays(-$OlderThanDays)

            foreach ($prof in $rawProfiles) {
                # Skip if raw result is null or not a hashtable
                if ($null -eq $prof -or $prof -isnot [hashtable]) {
                    continue 
                }

                $localPath = $prof.LocalPath
                $sid = $prof.SID
                $lastUse = $prof.LastUseTime
                $loaded = $prof.Loaded
                $sizeMB = $prof.SizeMB

                # Extract username from LocalPath (last segment)
                $userName = if ($localPath) {
                    Split-Path -Path $localPath -Leaf 
                } else {
                    $sid 
                }

                # ---- Exclusion: system SIDs ----
                if ($sid -in $systemSids) {
                    continue 
                }

                # ---- Exclusion: system path segments ----
                $isSystemPath = $false
                foreach ($segment in $systemPathSegments) {
                    if ($userName -eq $segment) {
                        $isSystemPath = $true
                        break
                    }
                }
                if ($isSystemPath) {
                    continue 
                }

                # ---- Exclusion: user-specified patterns ----
                if ($ExcludeUser) {
                    $isExcluded = $false
                    foreach ($pattern in $ExcludeUser) {
                        if ($userName -like $pattern) {
                            $isExcluded = $true
                            break
                        }
                    }
                    if ($isExcluded) {
                        continue 
                    }
                }

                # ---- Filter: age threshold ----
                $daysInactive = if ($null -ne $lastUse -and $lastUse -ne [datetime]::MinValue) {
                    [int](((Get-Date) - $lastUse).TotalDays)
                } else {
                    [int]::MaxValue  # Never used — eligible
                }

                if ($null -ne $lastUse -and $lastUse -ne [datetime]::MinValue -and $lastUse -ge $cutoff) {
                    continue  # Profile is recent — skip
                }

                # ---- Skip loaded profiles ----
                if ($loaded) {
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.UserProfileRemoval'
                        ComputerName  = $machine
                        UserName      = $userName
                        LocalPath     = $localPath
                        SID           = $sid
                        LastUseTime   = $lastUse
                        ProfileSizeMB = $sizeMB
                        DaysInactive  = $daysInactive
                        Status        = 'Skipped'
                        ErrorMessage  = 'Profile is currently loaded'
                        Timestamp     = Get-Date -Format 'o'
                    }
                    continue
                }

                # ---- ShouldProcess ----
                $lastUseDisplay = if ($null -ne $lastUse -and $lastUse -ne [datetime]::MinValue) {
                    $lastUse.ToString('yyyy-MM-dd')
                } else {
                    'Never'
                }
                $sizeDisplay = if ($sizeMB -ge 0) {
                    '{0:N1} MB' -f $sizeMB 
                } else {
                    'unknown' 
                }
                $target = "User '$userName' ($localPath, last used $lastUseDisplay, $sizeDisplay)"

                if (-not $PSCmdlet.ShouldProcess($target, 'Remove user profile')) {
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.UserProfileRemoval'
                        ComputerName  = $machine
                        UserName      = $userName
                        LocalPath     = $localPath
                        SID           = $sid
                        LastUseTime   = $lastUse
                        ProfileSizeMB = $sizeMB
                        DaysInactive  = $daysInactive
                        Status        = 'WhatIf'
                        ErrorMessage  = $null
                        Timestamp     = Get-Date -Format 'o'
                    }
                    continue
                }

                # ---- Delete profile ----
                try {
                    $removeParams = @{
                        ComputerName = $machine
                        ScriptBlock  = $removeBlock
                        ArgumentList = @($sid)
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $removeParams['Credential'] = $Credential
                    }

                    Invoke-RemoteOrLocal @removeParams

                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.UserProfileRemoval'
                        ComputerName  = $machine
                        UserName      = $userName
                        LocalPath     = $localPath
                        SID           = $sid
                        LastUseTime   = $lastUse
                        ProfileSizeMB = $sizeMB
                        DaysInactive  = $daysInactive
                        Status        = 'Removed'
                        ErrorMessage  = $null
                        Timestamp     = Get-Date -Format 'o'
                    }
                } catch {
                    [PSCustomObject]@{
                        PSTypeName    = 'PSWinOps.UserProfileRemoval'
                        ComputerName  = $machine
                        UserName      = $userName
                        LocalPath     = $localPath
                        SID           = $sid
                        LastUseTime   = $lastUse
                        ProfileSizeMB = $sizeMB
                        DaysInactive  = $daysInactive
                        Status        = 'Failed'
                        ErrorMessage  = $_.Exception.Message
                        Timestamp     = Get-Date -Format 'o'
                    }
                }
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
