#Requires -Version 5.1

function Get-ADLockoutSource {
    <#
    .SYNOPSIS
        Find the source machine for AD account lockout events

    .DESCRIPTION
        Reads Security event 4740 from the PDC Emulator or a specified domain
        controller and correlates events with Active Directory users by SID.
        Returns typed, pipeline-friendly records sorted with the newest lockout
        first.

    .PARAMETER Identity
        One or more Active Directory user identities (SamAccountName, DN, GUID,
        or SID) to look up lockout sources for. Accepts pipeline input by value
        and by property name (alias 'SamAccountName').

    .PARAMETER Server
        The domain controller whose Security event log is queried. Defaults to
        the discovered PDC Emulator when omitted.

    .PARAMETER MaxEvents
        The maximum number of 4740 events to retrieve from the Security log.
        Defaults to 1000.

    .PARAMETER After
        Only include lockout events with a TimeCreated after this timestamp.

    .PARAMETER Credential
        Specifies the credentials to use for the Get-ADUser and Get-WinEvent
        queries.

    .EXAMPLE
        Get-ADLockoutSource -Identity 'jsmith'

        Finds the lockout source for 'jsmith' using the discovered PDC Emulator.

    .EXAMPLE
        Get-ADLockoutSource -Identity 'jsmith' -Server 'DC01.contoso.com'

        Finds the lockout source for 'jsmith' by querying the Security log on a
        specific domain controller.

    .EXAMPLE
        Get-ADLockedAccount | Get-ADLockoutSource

        Pipes currently locked accounts into Get-ADLockoutSource to identify
        where each lockout originated.

    .OUTPUTS
        PSWinOps.ADLockoutSource
        One object per matching 4740 event, sorted by LockoutTime descending.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-04
        Requires: PowerShell 5.1+ / Windows only
        Requires: ActiveDirectory module (RSAT-AD-PowerShell)
        Requires: Read access to the PDC Security log (Administrator or Event Log Readers)
        Requires: Account Lockout auditing enabled on domain controllers

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4740
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ADLockoutSource')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('SamAccountName')]
        [string[]]$Identity,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 2147483647)]
        [int]$MaxEvents = 1000,

        [Parameter(Mandatory = $false)]
        [datetime]$After,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"

        try {
            Import-Module -Name 'ActiveDirectory' -ErrorAction Stop
        }
        catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new(
                        'ActiveDirectory module is not available. Install RSAT-AD-PowerShell.',
                        $_.Exception
                    ),
                    'ActiveDirectoryModuleMissing',
                    [System.Management.Automation.ErrorCategory]::NotInstalled,
                    'ActiveDirectory'
                )
            )
        }

        $adParams = @{}
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $adParams['Credential'] = $Credential
        }

        $targetServer = $Server
        if (-not $PSBoundParameters.ContainsKey('Server')) {
            try {
                $pdc = Get-ADDomainController -Discover -Service 'PrimaryDC' -ErrorAction Stop
                $targetServer = $pdc.HostName[0]
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Discovered PDC Emulator '$targetServer'"
            }
            catch {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new(
                            "Failed to discover the PDC Emulator: $_",
                            $_.Exception
                        ),
                        'PdcDiscoveryFailed',
                        [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                        $Server
                    )
                )
            }
        }

        if ($Server) {
            $adParams['Server'] = $Server
        }

        $eventParams = @{}
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $eventParams['Credential'] = $Credential
        }
    }

    process {
        foreach ($targetIdentity in $Identity) {
            try {
                $userDetail = Get-ADUser -Identity $targetIdentity -Properties 'SID' @adParams -ErrorAction Stop
            }
            catch {
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to resolve identity '$targetIdentity': $_"
                continue
            }

            $targetSid = $userDetail.SID.Value

            $filterHashtable = @{
                LogName = 'Security'
                Id      = 4740
            }
            if ($PSBoundParameters.ContainsKey('After')) {
                $filterHashtable['StartTime'] = $After
            }

            try {
                $events = Get-WinEvent -ComputerName $targetServer -FilterHashtable $filterHashtable -MaxEvents $MaxEvents @eventParams -ErrorAction Stop
            }
            catch {
                if ($_.CategoryInfo.Category -eq 'ObjectNotFound') {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No lockout (4740) events found on '$targetServer' for '$targetIdentity'"
                    continue
                }
                if ($_.Exception.Message -match 'No events were found' -or $_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') {
                    Write-Verbose -Message "[$($MyInvocation.MyCommand)] No lockout (4740) events found on '$targetServer' for '$targetIdentity'"
                    continue
                }
                Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to query Security log on '$targetServer' for '$targetIdentity': $_"
                continue
            }

            if (-not $events) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] No lockout (4740) events found on '$targetServer' for '$targetIdentity'"
                continue
            }

            $results = [System.Collections.Generic.List[object]]::new()

            foreach ($event in $events) {
                try {
                    if ($event.Properties.Count -lt 3) {
                        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Skipping event with unexpected property count on '$targetServer'"
                        continue
                    }

                    $eventSid = $event.Properties[2].Value
                    if (-not $eventSid -or $eventSid.ToString() -ne $targetSid) {
                        continue
                    }

                    $results.Add([PSCustomObject]@{
                        PSTypeName       = 'PSWinOps.ADLockoutSource'
                        ComputerName     = $targetServer
                        DomainController = $event.MachineName
                        UserName         = $event.Properties[0].Value
                        SamAccountName   = $userDetail.SamAccountName
                        LockoutSource    = $event.Properties[1].Value
                        LockoutTime      = [datetime]$event.TimeCreated
                        EventId          = [int]$event.Id
                        Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    })
                }
                catch {
                    Write-Error -Message "[$($MyInvocation.MyCommand)] Failed to parse event for '$targetIdentity' on '$targetServer': $_"
                    continue
                }
            }

            $results | Sort-Object -Property 'LockoutTime' -Descending
        }
    }

    end {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Completed"
    }
}
