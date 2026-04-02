#Requires -Version 5.1
function Get-InstalledSoftware {
    <#
        .SYNOPSIS
            Retrieves installed software from local or remote Windows computers

        .DESCRIPTION
            Queries the Windows registry Uninstall keys to enumerate installed software.
            Both 64-bit and 32-bit (WOW6432Node) registry hives are queried to provide
            a complete inventory. Supports wildcard filtering by display name.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER Name
            Optional wildcard filter for the software display name. Uses -like matching.
            For example, 'Microsoft*' returns all Microsoft products.

        .PARAMETER Credential
            Optional PSCredential object for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-InstalledSoftware

            Retrieves all installed software on the local computer.

        .EXAMPLE
            Get-InstalledSoftware -ComputerName 'SRV01' -Name 'Microsoft SQL*' -Credential (Get-Credential)

            Retrieves SQL Server related software from SRV01 using alternate credentials.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-InstalledSoftware -Name '7-Zip*'

            Retrieves 7-Zip installations from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.InstalledSoftware
            Returns objects with ComputerName, DisplayName, DisplayVersion, Publisher,
            InstallDate, InstallLocation, UninstallString, Architecture, EstimatedSizeMB,
            and Timestamp properties. Output is sorted by DisplayName.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only
            Requires: Remote registry or WinRM for remote computers

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/msi/uninstall-registry-key
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.InstalledSoftware')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting"

        $registryPaths = @{
            '64-bit' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            '32-bit' = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        }

        $scriptBlock = {
            param(
                [hashtable]$Paths
            )
            $softwareList = [System.Collections.Generic.List[object]]::new()
            foreach ($archKey in $Paths.GetEnumerator()) {
                try {
                    $entries = Get-ItemProperty -Path $archKey.Value -ErrorAction SilentlyContinue
                    foreach ($entry in $entries) {
                        if (-not [string]::IsNullOrWhiteSpace($entry.DisplayName)) {
                            $softwareList.Add([PSCustomObject]@{
                                DisplayName     = $entry.DisplayName
                                DisplayVersion  = $entry.DisplayVersion
                                Publisher        = $entry.Publisher
                                InstallDate     = $entry.InstallDate
                                InstallLocation = $entry.InstallLocation
                                UninstallString = $entry.UninstallString
                                EstimatedSize   = $entry.EstimatedSize
                                Architecture    = $archKey.Key
                            })
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to read registry path $($archKey.Value): $_"
                }
            }
            $softwareList
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "[$($MyInvocation.MyCommand)] Processing $computer"

            try {
                $rawEntries = Invoke-RemoteOrLocal -ComputerName $computer -ScriptBlock $scriptBlock -ArgumentList @(, $registryPaths) -Credential $Credential

                $resultList = [System.Collections.Generic.List[object]]::new()

                foreach ($entry in $rawEntries) {
                    if ($Name -and ($entry.DisplayName -notlike $Name)) {
                        continue
                    }

                    $installDate = $null
                    if (-not [string]::IsNullOrWhiteSpace($entry.InstallDate)) {
                        try {
                            $installDate = [datetime]::ParseExact(
                                $entry.InstallDate,
                                'yyyyMMdd',
                                [System.Globalization.CultureInfo]::InvariantCulture
                            )
                        }
                        catch {
                            Write-Verbose "[$($MyInvocation.MyCommand)] Could not parse InstallDate '$($entry.InstallDate)' for '$($entry.DisplayName)'"
                        }
                    }

                    $estimatedSizeMB = $null
                    if ($entry.EstimatedSize) {
                        $estimatedSizeMB = [math]::Round($entry.EstimatedSize / 1024, 2)
                    }

                    $resultList.Add([PSCustomObject]@{
                        PSTypeName      = 'PSWinOps.InstalledSoftware'
                        ComputerName    = $computer
                        DisplayName     = $entry.DisplayName
                        DisplayVersion  = $entry.DisplayVersion
                        Publisher        = $entry.Publisher
                        InstallDate     = $installDate
                        InstallLocation = $entry.InstallLocation
                        UninstallString = $entry.UninstallString
                        Architecture    = $entry.Architecture
                        EstimatedSizeMB = $estimatedSizeMB
                        Timestamp       = Get-Date -Format 'o'
                    })
                }

                $resultList | Sort-Object -Property DisplayName
            }
            catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query software on ${computer}: $_"
                continue
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed"
    }
}
