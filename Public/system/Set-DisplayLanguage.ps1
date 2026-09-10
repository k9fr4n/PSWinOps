#Requires -Version 5.1
function Set-DisplayLanguage {
    <#
        .SYNOPSIS
            Sets the Windows UI display language on local or remote computers

        .DESCRIPTION
            Changes the Windows UI display language for the current user via
            Set-WinUILanguageOverride, installing the language pack automatically
            through the LanguagePackManagement module when it is not already present.
            Optionally propagates the settings to the system account (Welcome Screen)
            and/or new user profiles via Copy-UserInternationalSettingsToSystem.
            The LanguagePackManagement module ships built-in on Windows 11 22H2+ and
            Windows Server 2022+; on earlier OS versions (e.g. Windows Server 2019) the
            module is not available and the function fails with clear guidance instead
            of the underlying "Get-InstalledLanguage is not recognized" error. A session
            restart is required for changes to take effect.

        .PARAMETER Language
            The BCP-47 language tag to apply (e.g. 'en-US', 'fr-FR').
            Must follow the format: two lowercase letters, a hyphen, two uppercase letters.

        .PARAMETER NoInstall
            Disables automatic installation of the language pack if it is not already
            present. By default, the function installs the pack automatically when missing.

        .PARAMETER ApplyToSystem
            Copies the language settings to the system account (Welcome Screen / login
            screen). Requires elevated privileges.

        .PARAMETER ApplyToNewUsers
            Copies the language settings to all new user profiles created after this
            change. Requires elevated privileges.

        .PARAMETER ComputerName
            One or more computer names to target. Defaults to the local computer.
            Accepts pipeline input by value and by property name. On a remote computer,
            the user-scoped override applies to the executing account's profile (the
            WinRM logon identity), not the interactive console user.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local operations.

        .EXAMPLE
            Set-DisplayLanguage -Language en-US

            Changes the display language to English (United States) for the current
            user on the local computer, installing the language pack automatically.

        .EXAMPLE
            Set-DisplayLanguage -Language fr-FR -ComputerName 'SRV01' -ApplyToSystem -ApplyToNewUsers

            Changes the display language to French on SRV01 for the current user, the
            system account, and all future new user profiles. Requires an elevated session.

        .EXAMPLE
            'SRV01', 'SRV02' | Set-DisplayLanguage -Language en-US -NoInstall

            Changes the display language on both servers via pipeline, without
            installing the language pack if it is missing.

        .OUTPUTS
            PSWinOps.DisplayLanguageResult
            Returns one object per computer describing the pack action taken and
            whether the user/system/new-user settings were applied.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-09-10
            Requires: PowerShell 5.1+ / Windows only
            Requires: LanguagePackManagement module (built-in on Windows 11 22H2+ / Windows Server 2022+)
            Requires: Administrator privileges for -ApplyToSystem / -ApplyToNewUsers

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/languagepackmanagement/
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('PSWinOps.DisplayLanguageResult')]
    param(
        [Parameter(Mandatory = $true, HelpMessage = 'BCP-47 language tag to apply, e.g. en-US or fr-FR')]
        [ValidatePattern('^[a-z]{2}-[A-Z]{2}$')]
        [string]$Language,

        [Parameter(Mandatory = $false, HelpMessage = 'Skip automatic installation of a missing language pack')]
        [switch]$NoInstall,

        [Parameter(Mandatory = $false, HelpMessage = 'Copy settings to the system account (Welcome Screen)')]
        [switch]$ApplyToSystem,

        [Parameter(Mandatory = $false, HelpMessage = 'Copy settings to new user profiles')]
        [switch]$ApplyToNewUsers,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting with Language='$Language', NoInstall=$($NoInstall.IsPresent), ApplyToSystem=$($ApplyToSystem.IsPresent), ApplyToNewUsers=$($ApplyToNewUsers.IsPresent)"

        if ($ApplyToSystem -or $ApplyToNewUsers) {
            if (-not (Test-IsAdministrator)) {
                $adminException = [System.Security.SecurityException]::new(
                    'Applying settings to the system account or new user profiles requires administrator privileges.'
                )
                $adminRecord = [System.Management.Automation.ErrorRecord]::new(
                    $adminException,
                    'InsufficientPrivilege',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null
                )
                $PSCmdlet.ThrowTerminatingError($adminRecord)
            }
        }

        $scriptBlock = {
            param(
                [string]$TargetLanguage,
                [bool]$SkipInstall,
                [bool]$ToSystem,
                [bool]$ToNewUsers
            )

            $languagePackModule = Get-Module -ListAvailable -Name 'LanguagePackManagement'
            if (-not $languagePackModule) {
                throw "The 'LanguagePackManagement' module is not available on this computer. It ships built-in on Windows 11 22H2+ and Windows Server 2022+; on earlier OS versions (e.g. Windows Server 2019) install the language pack via 'lpksetup.exe' or Server Manager and use 'Set-WinUILanguageOverride' instead."
            }

            $installed = Get-InstalledLanguage -ErrorAction Stop | Where-Object -FilterScript { $_.LanguageId -eq $TargetLanguage }

            if (-not $installed) {
                if ($SkipInstall) {
                    return [PSCustomObject]@{
                        PackAction        = 'Skipped'
                        UserLanguageSet   = $false
                        AppliedToSystem   = $false
                        AppliedToNewUsers = $false
                        Status            = 'Skipped'
                    }
                }

                Install-Language -Language $TargetLanguage -ErrorAction Stop
                $packAction = 'Installed'
            } else {
                $packAction = 'AlreadyPresent'
            }

            Set-WinUILanguageOverride -Language $TargetLanguage -ErrorAction Stop

            $appliedToSystem = $false
            $appliedToNewUsers = $false
            if ($ToSystem -or $ToNewUsers) {
                Copy-UserInternationalSettingsToSystem -WelcomeScreen:$ToSystem -NewUser:$ToNewUsers -ErrorAction Stop
                $appliedToSystem = $ToSystem
                $appliedToNewUsers = $ToNewUsers
            }

            [PSCustomObject]@{
                PackAction        = $packAction
                UserLanguageSet   = $true
                AppliedToSystem   = $appliedToSystem
                AppliedToNewUsers = $appliedToNewUsers
                Status            = 'Success'
            }
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$targetComputer'"

            $actionDescription = if ($ApplyToSystem -or $ApplyToNewUsers) {
                "Set display language to '$Language' and propagate to System/NewUsers"
            } else {
                "Set display language to '$Language'"
            }

            try {
                if ($PSCmdlet.ShouldProcess($targetComputer, $actionDescription)) {
                    $innerResult = Invoke-RemoteOrLocal -ComputerName $targetComputer -ScriptBlock $scriptBlock -ArgumentList @($Language, $NoInstall.IsPresent, $ApplyToSystem.IsPresent, $ApplyToNewUsers.IsPresent) -Credential $Credential

                    [PSCustomObject]@{
                        PSTypeName        = 'PSWinOps.DisplayLanguageResult'
                        ComputerName      = $targetComputer
                        Language          = $Language
                        PackAction        = $innerResult.PackAction
                        UserLanguageSet   = $innerResult.UserLanguageSet
                        AppliedToSystem   = $innerResult.AppliedToSystem
                        AppliedToNewUsers = $innerResult.AppliedToNewUsers
                        RestartRequired   = ($innerResult.Status -eq 'Success')
                        Status            = $innerResult.Status
                        ErrorMessage      = $null
                        Timestamp         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }

                    if ($innerResult.Status -eq 'Success') {
                        Write-Warning -Message "[$($MyInvocation.MyCommand)] A session restart on '$targetComputer' is required for changes to take effect."
                    }
                }
            } catch {
                [PSCustomObject]@{
                    PSTypeName        = 'PSWinOps.DisplayLanguageResult'
                    ComputerName      = $targetComputer
                    Language          = $Language
                    PackAction        = 'None'
                    UserLanguageSet   = $false
                    AppliedToSystem   = $false
                    AppliedToNewUsers = $false
                    RestartRequired   = $false
                    Status            = 'Failed'
                    ErrorMessage      = $_.Exception.Message
                    Timestamp         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                }
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to set display language on '${targetComputer}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
