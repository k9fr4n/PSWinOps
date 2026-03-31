#Requires -Version 5.1
function Get-EnvironmentVariable {
    <#
        .SYNOPSIS
            Retrieves environment variables from local or remote computers

        .DESCRIPTION
            Returns environment variables organized by scope (Machine, User, Process).
            Machine and User scopes read from the registry for persistent values.
            Process scope uses the current runtime environment. Supports wildcard
            filtering by variable name.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local computer.
            Accepts pipeline input by value and by property name.

        .PARAMETER VariableName
            Optional wildcard filter on the variable name. Uses -like matching.
            For example, 'PATH' returns only the PATH variable per scope.

        .PARAMETER Scope
            Scope to query. Valid values: Machine, User, Process, All.
            Defaults to All. Process scope is only available for local queries.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-EnvironmentVariable

            Returns all environment variables from all scopes on the local computer.

        .EXAMPLE
            Get-EnvironmentVariable -ComputerName 'SRV01' -VariableName 'PATH' -Scope Machine

            Returns the Machine-scoped PATH variable from SRV01.

        .EXAMPLE
            'SRV01', 'SRV02' | Get-EnvironmentVariable -VariableName 'TEMP*'

            Retrieves all TEMP-related variables from multiple servers via pipeline.

        .OUTPUTS
            PSWinOps.EnvironmentVariable
            Returns objects with ComputerName, Name, Value, Scope, and Timestamp.
            Results are sorted by Scope then by Name.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only
            Requires: Remote registry or WinRM for remote Machine/User scopes

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.EnvironmentVariable')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$VariableName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Machine', 'User', 'Process', 'All')]
        [string]$Scope = 'All',

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting with Scope=$Scope"

        $registryPaths = @{
            Machine = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
            User    = 'HKCU:\Environment'
        }

        $scriptBlock = {
            param(
                [hashtable]$Paths,
                [string]$RequestedScope
            )

            $results = [System.Collections.Generic.List[object]]::new()

            $scopesToQuery = if ($RequestedScope -eq 'All') {
                @('Machine', 'User')
            }
            else {
                @($RequestedScope)
            }

            foreach ($scopeName in $scopesToQuery) {
                if ($scopeName -eq 'Process') { continue }

                $path = $Paths[$scopeName]
                if (-not $path) { continue }

                try {
                    $regItem = Get-Item -Path $path -ErrorAction Stop
                    foreach ($valueName in $regItem.GetValueNames()) {
                        if ([string]::IsNullOrEmpty($valueName)) { continue }
                        $results.Add([PSCustomObject]@{
                            Name  = $valueName
                            Value = $regItem.GetValue($valueName, '', 'DoNotExpandEnvironmentNames')
                            Scope = $scopeName
                        })
                    }
                }
                catch {
                    Write-Warning "Failed to read $scopeName environment: $_"
                }
            }

            $results
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Processing '$machine'"

            try {
                $isLocal = @($env:COMPUTERNAME, 'localhost', '.') -contains $machine
                $displayName = $machine
                $resultList = [System.Collections.Generic.List[object]]::new()

                # Remote Process scope is not supported
                if (-not $isLocal -and $Scope -eq 'Process') {
                    Write-Warning -Message "[$($MyInvocation.MyCommand)] Process scope is not available for remote computers. Skipping '$machine'."
                    continue
                }

                # Query Machine/User scopes via Invoke-RemoteOrLocal
                $rawEntries = Invoke-RemoteOrLocal -ComputerName $machine -ScriptBlock $scriptBlock -ArgumentList @($registryPaths, $Scope) -Credential $Credential

                foreach ($entry in $rawEntries) {
                    $resultList.Add($entry)
                }

                # Add Process scope if local and requested
                if ($isLocal -and ($Scope -eq 'All' -or $Scope -eq 'Process')) {
                    $envVars = [Environment]::GetEnvironmentVariables('Process')
                    foreach ($key in $envVars.Keys) {
                        $resultList.Add([PSCustomObject]@{
                            Name  = $key
                            Value = $envVars[$key]
                            Scope = 'Process'
                        })
                    }
                }

                # Apply name filter and emit typed objects
                $resultList |
                    Sort-Object -Property Scope, Name |
                    ForEach-Object -Process {
                        if ($PSBoundParameters.ContainsKey('VariableName') -and ($_.Name -notlike $VariableName)) {
                            return
                        }

                        [PSCustomObject]@{
                            PSTypeName   = 'PSWinOps.EnvironmentVariable'
                            ComputerName = $displayName
                            Name         = $_.Name
                            Value        = $_.Value
                            Scope        = $_.Scope
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
