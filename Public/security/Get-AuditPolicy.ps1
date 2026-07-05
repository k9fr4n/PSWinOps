#Requires -Version 5.1

function Get-AuditPolicy {
    <#
    .SYNOPSIS
        Report advanced audit policy subcategory settings from auditpol.exe

    .DESCRIPTION
        Parses the advanced audit policy returned by 'auditpol.exe /get /category:* /r' (CSV)
        into one object per subcategory, reporting Success and Failure auditing state. It is a
        base building block for CIS/ANSSI compliance auditing and supports local and remote
        targets via Invoke-RemoteOrLocal, with optional filtering to a single category. Each
        Subcategory GUID is mapped to its parent Category using a static, well-known GUID map
        since 'auditpol /r' does not expose Category as a column.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .PARAMETER Credential
        Optional PSCredential for authenticating to remote machines. Ignored for local
        machine queries.

    .PARAMETER Category
        Filter results to a single audit category, e.g. 'Logon/Logoff'. Matched
        case-insensitively against the parsed Category column. When set and no subcategory
        matches on a given machine, that machine yields no rows (no error is raised).

    .EXAMPLE
        Get-AuditPolicy

        Returns advanced audit policy subcategory settings for the local machine.

    .EXAMPLE
        Get-AuditPolicy -Category 'Logon/Logoff'

        Returns only the subcategories belonging to the 'Logon/Logoff' category on the
        local machine.

    .EXAMPLE
        Get-AuditPolicy -ComputerName SRV01 -Credential (Get-Credential)

        Returns advanced audit policy subcategory settings from SRV01 via WinRM, using
        the supplied credential.

    .EXAMPLE
        'SRV01','SRV02' | Get-AuditPolicy

        Returns advanced audit policy subcategory settings for SRV01 and SRV02 via pipeline.

    .OUTPUTS
        PSWinOps.AuditPolicy
        One object per audit subcategory, with Category, Subcategory, SubcategoryGuid,
        AuditSuccess, AuditFailure and the derived Setting string.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-07-05
        Requires: PowerShell 5.1+ / Windows only
        Requires: Elevated (administrator) session for auditpol.exe to return data

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/auditpol
    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType('PSWinOps.AuditPolicy')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [string]$Category
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Starting audit policy query"

        $auditpolPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\auditpol.exe'

        # Static, well-known Subcategory GUID -> top-level Category map. auditpol /r does not
        # expose Category as a column, so it must be derived from the (stable) subcategory GUID.
        $categoryMap = @{
            # System
            '0CCE9210-69AE-11D9-BED3-505054503030' = 'System'
            '0CCE9211-69AE-11D9-BED3-505054503030' = 'System'
            '0CCE9212-69AE-11D9-BED3-505054503030' = 'System'
            '0CCE9213-69AE-11D9-BED3-505054503030' = 'System'
            '0CCE9214-69AE-11D9-BED3-505054503030' = 'System'
            # Logon/Logoff
            '0CCE9215-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE9216-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE9217-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE9218-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE9219-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE921A-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE921B-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE921C-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE9243-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE9247-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            '0CCE9249-69AE-11D9-BED3-505054503030' = 'Logon/Logoff'
            # Object Access
            '0CCE921D-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE921E-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE921F-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9220-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9221-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9222-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9223-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9224-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9225-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9226-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9227-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9244-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9245-69AE-11D9-BED3-505054503030' = 'Object Access'
            '0CCE9246-69AE-11D9-BED3-505054503030' = 'Object Access'
            # Privilege Use
            '0CCE9228-69AE-11D9-BED3-505054503030' = 'Privilege Use'
            '0CCE9229-69AE-11D9-BED3-505054503030' = 'Privilege Use'
            '0CCE922A-69AE-11D9-BED3-505054503030' = 'Privilege Use'
            # Detailed Tracking
            '0CCE922B-69AE-11D9-BED3-505054503030' = 'Detailed Tracking'
            '0CCE922C-69AE-11D9-BED3-505054503030' = 'Detailed Tracking'
            '0CCE922D-69AE-11D9-BED3-505054503030' = 'Detailed Tracking'
            '0CCE922E-69AE-11D9-BED3-505054503030' = 'Detailed Tracking'
            '0CCE9248-69AE-11D9-BED3-505054503030' = 'Detailed Tracking'
            '0CCE924A-69AE-11D9-BED3-505054503030' = 'Detailed Tracking'
            # Policy Change
            '0CCE922F-69AE-11D9-BED3-505054503030' = 'Policy Change'
            '0CCE9230-69AE-11D9-BED3-505054503030' = 'Policy Change'
            '0CCE9231-69AE-11D9-BED3-505054503030' = 'Policy Change'
            '0CCE9232-69AE-11D9-BED3-505054503030' = 'Policy Change'
            '0CCE9233-69AE-11D9-BED3-505054503030' = 'Policy Change'
            '0CCE9234-69AE-11D9-BED3-505054503030' = 'Policy Change'
            # Account Management
            '0CCE9235-69AE-11D9-BED3-505054503030' = 'Account Management'
            '0CCE9236-69AE-11D9-BED3-505054503030' = 'Account Management'
            '0CCE9237-69AE-11D9-BED3-505054503030' = 'Account Management'
            '0CCE9238-69AE-11D9-BED3-505054503030' = 'Account Management'
            '0CCE9239-69AE-11D9-BED3-505054503030' = 'Account Management'
            '0CCE923A-69AE-11D9-BED3-505054503030' = 'Account Management'
            # DS Access
            '0CCE923B-69AE-11D9-BED3-505054503030' = 'DS Access'
            '0CCE923C-69AE-11D9-BED3-505054503030' = 'DS Access'
            '0CCE923D-69AE-11D9-BED3-505054503030' = 'DS Access'
            '0CCE923E-69AE-11D9-BED3-505054503030' = 'DS Access'
            # Account Logon
            '0CCE923F-69AE-11D9-BED3-505054503030' = 'Account Logon'
            '0CCE9240-69AE-11D9-BED3-505054503030' = 'Account Logon'
            '0CCE9241-69AE-11D9-BED3-505054503030' = 'Account Logon'
            '0CCE9242-69AE-11D9-BED3-505054503030' = 'Account Logon'
        }

        # Scriptblock used for REMOTE execution only (Invoke-Command).
        # Resolves the full auditpol.exe path inside the remote session because remote
        # runspaces do not inherit local mock context, then checks $LASTEXITCODE and
        # throws on non-zero, returning the raw CSV text.
        $auditPolRemoteScriptBlock = {
            $remoteAuditpolPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\auditpol.exe'
            if (-not (Test-Path -Path $remoteAuditpolPath)) {
                throw "auditpol.exe not found at '$remoteAuditpolPath'"
            }
            $auditOutput = & $remoteAuditpolPath '/get' '/category:*' '/r' 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "auditpol /get /category:* /r failed (exit code $LASTEXITCODE): $($auditOutput -join ' ')"
            }
            $auditOutput
        }
    }

    process {
        foreach ($targetComputer in $ComputerName) {
            try {
                Write-Verbose "[$($MyInvocation.MyCommand)] Querying audit policy on '$targetComputer'"

                $isLocal = ($targetComputer -eq $env:COMPUTERNAME) -or
                ($targetComputer -eq 'localhost') -or
                ($targetComputer -eq '.')

                if ($isLocal) {
                    # Local execution: use Invoke-NativeCommand for testable auditpol calls
                    $auditResult = Invoke-NativeCommand -FilePath $auditpolPath -ArgumentList @('/get', '/category:*', '/r')
                    if ($auditResult.ExitCode -ne 0) {
                        $PSCmdlet.ThrowTerminatingError(
                            [System.Management.Automation.ErrorRecord]::new(
                                [System.InvalidOperationException]::new(
                                    "auditpol /get /category:* /r failed (exit code $($auditResult.ExitCode)): $($auditResult.Output)"
                                ),
                                'AuditPolGetFailed',
                                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                                $targetComputer
                            )
                        )
                    }
                    $rawOutput = $auditResult.Output -split '\r?\n'
                } else {
                    $invokeParams = @{
                        ComputerName = $targetComputer
                        ScriptBlock  = $auditPolRemoteScriptBlock
                        ErrorAction  = 'Stop'
                    }
                    if ($null -ne $Credential) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $rawOutput = Invoke-Command @invokeParams
                }

                # Normalise to a non-empty string array of lines (header + data rows)
                $csvLines = @($rawOutput | ForEach-Object { "$_" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

                if ($csvLines.Count -lt 2) {
                    Write-Error "[$($MyInvocation.MyCommand)] No audit policy data returned by auditpol.exe on '$targetComputer'"
                    continue
                }

                $rows = @($csvLines | ConvertFrom-Csv)

                if ($rows.Count -eq 0) {
                    Write-Error "[$($MyInvocation.MyCommand)] Failed to parse auditpol CSV output on '$targetComputer'"
                    continue
                }

                foreach ($row in $rows) {
                    $subcategoryGuid = ($row.'Subcategory GUID' -replace '[{}]', '').Trim().ToUpperInvariant()
                    $category = if ($categoryMap.ContainsKey($subcategoryGuid)) { $categoryMap[$subcategoryGuid] } else { 'Unknown' }

                    if ($Category -and ($category -ne $Category)) {
                        continue
                    }

                    $inclusionSetting = [string]$row.'Inclusion Setting'
                    $auditSuccess = $inclusionSetting -match 'Success'
                    $auditFailure = $inclusionSetting -match 'Failure'

                    $setting = if ($auditSuccess -and $auditFailure) {
                        'Success and Failure'
                    } elseif ($auditSuccess) {
                        'Success'
                    } elseif ($auditFailure) {
                        'Failure'
                    } else {
                        'No Auditing'
                    }

                    [PSCustomObject]@{
                        PSTypeName      = 'PSWinOps.AuditPolicy'
                        ComputerName    = $targetComputer
                        Category        = $category
                        Subcategory     = $row.Subcategory
                        SubcategoryGuid = $subcategoryGuid
                        AuditSuccess    = $auditSuccess
                        AuditFailure    = $auditFailure
                        Setting         = $setting
                        Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    }
                }
            } catch {
                Write-Error "[$($MyInvocation.MyCommand)] Failed to query '$targetComputer': $_"
                continue
            }
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed audit policy query"
    }
}
