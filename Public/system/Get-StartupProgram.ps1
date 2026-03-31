#Requires -Version 5.1
function Get-StartupProgram {
    <#
        .SYNOPSIS
            Retrieves programs configured to run at system startup or user logon

        .DESCRIPTION
            Enumerates startup entries from multiple sources: registry Run and RunOnce
            keys (both Machine and User scope, including WOW6432Node for 32-bit entries
            on 64-bit systems) and the common Startup folder. Provides a consolidated
            view of all auto-start programs across all launch points.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-StartupProgram

            Lists all startup programs on the local computer.

        .EXAMPLE
            Get-StartupProgram -ComputerName 'SRV01'

            Lists startup programs from a remote server.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-StartupProgram

            Lists startup programs from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.StartupProgram
            Returns objects with program name, command line, location source,
            scope (Machine or User), and timestamp.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only
            Requires: WinRM for remote computers

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.StartupProgram')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        $registrySources = @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';                          Scope = 'Machine'; Label = 'HKLM\...\Run' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';                      Scope = 'Machine'; Label = 'HKLM\...\RunOnce' }
            @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';              Scope = 'Machine'; Label = 'HKLM\...\WOW6432Node\Run' }
            @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce';          Scope = 'Machine'; Label = 'HKLM\...\WOW6432Node\RunOnce' }
            @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';                          Scope = 'User';    Label = 'HKCU\...\Run' }
            @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';                      Scope = 'User';    Label = 'HKCU\...\RunOnce' }
        )

        $scriptBlock = {
            param(
                [array]$Sources
            )

            $results = [System.Collections.Generic.List[object]]::new()

            foreach ($source in $Sources) {
                $regPath = $source.Path
                if (-not (Test-Path -Path $regPath)) { continue }

                try {
                    $regItem = Get-Item -Path $regPath -ErrorAction Stop
                    foreach ($valueName in $regItem.GetValueNames()) {
                        if ([string]::IsNullOrEmpty($valueName)) { continue }
                        $results.Add([PSCustomObject]@{
                            ProgramName = $valueName
                            Command     = $regItem.GetValue($valueName)
                            Location    = $source.Label
                            Scope       = $source.Scope
                            Source      = 'Registry'
                        })
                    }
                }
                catch {
                    Write-Warning "Failed to read '$regPath': $_"
                }
            }

            # Common Startup folder (All Users)
            $startupPath = [Environment]::GetFolderPath('CommonStartup')
            if ($startupPath -and (Test-Path -Path $startupPath)) {
                $shortcuts = Get-ChildItem -Path $startupPath -Filter '*.lnk' -ErrorAction SilentlyContinue
                foreach ($shortcut in $shortcuts) {
                    try {
                        $shell = New-Object -ComObject WScript.Shell
                        $lnk = $shell.CreateShortcut($shortcut.FullName)
                        $results.Add([PSCustomObject]@{
                            ProgramName = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.Name)
                            Command     = $lnk.TargetPath
                            Location    = 'Common Startup Folder'
                            Scope       = 'Machine'
                            Source      = 'StartupFolder'
                        })
                    }
                    catch {
                        $results.Add([PSCustomObject]@{
                            ProgramName = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.Name)
                            Command     = $shortcut.FullName
                            Location    = 'Common Startup Folder'
                            Scope       = 'Machine'
                            Source      = 'StartupFolder'
                        })
                    }
                }
            }

            # User Startup folder
            $userStartupPath = [Environment]::GetFolderPath('Startup')
            if ($userStartupPath -and (Test-Path -Path $userStartupPath)) {
                $shortcuts = Get-ChildItem -Path $userStartupPath -Filter '*.lnk' -ErrorAction SilentlyContinue
                foreach ($shortcut in $shortcuts) {
                    try {
                        $shell = New-Object -ComObject WScript.Shell
                        $lnk = $shell.CreateShortcut($shortcut.FullName)
                        $results.Add([PSCustomObject]@{
                            ProgramName = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.Name)
                            Command     = $lnk.TargetPath
                            Location    = 'User Startup Folder'
                            Scope       = 'User'
                            Source      = 'StartupFolder'
                        })
                    }
                    catch {
                        $results.Add([PSCustomObject]@{
                            ProgramName = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.Name)
                            Command     = $shortcut.FullName
                            Location    = 'User Startup Folder'
                            Scope       = 'User'
                            Source      = 'StartupFolder'
                        })
                    }
                }
            }

            $results
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$machine'"

            try {
                $displayName = $machine
                $rawEntries = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -ArgumentList @(, $registrySources) -Credential $Credential

                foreach ($entry in $rawEntries) {
                    [PSCustomObject]@{
                        PSTypeName   = 'PSWinOps.StartupProgram'
                        ComputerName = $displayName
                        ProgramName  = $entry.ProgramName
                        Command      = $entry.Command
                        Location     = $entry.Location
                        Scope        = $entry.Scope
                        Source       = $entry.Source
                        Timestamp    = Get-Date -Format 'o'
                    }
                }
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed on '${machine}': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
