#Requires -Version 5.1

<#
.SYNOPSIS
    PSWinOps module loader

.DESCRIPTION
    Loads all public and private functions for the PSWinOps module.
    Public functions are automatically exported.
#>

# Guard: this module is Windows-only (Win32/CIM/registry/netsh/w32tm/mstsc/logoff)
if ($PSEdition -eq 'Core' -and -not $IsWindows) {
    throw 'PSWinOps requires Windows. Linux and macOS are not supported.'
}

# Get module root path
$script:ModuleRoot = $PSScriptRoot

# Module-scoped list of names that identify the local machine
$script:LocalComputerNames = @($env:COMPUTERNAME, 'localhost', '.')

Write-Verbose "[$($MyInvocation.MyCommand)] Loading PSWinOps module from: $script:ModuleRoot"

# Legacy alias gate — opt-in for one minor release cycle, then remove entirely.
# Set $env:PSWINOPS_LEGACY_ALIASES = '1' BEFORE Import-Module to re-create the
# pre-rename aliases. Each gated alias emits a deprecation warning.
if ($env:PSWINOPS_LEGACY_ALIASES -eq '1') {
    Set-Alias -Name 'Download-WindowsUpdate' -Value 'Save-WindowsUpdate' -Scope Global
    Write-Warning "PSWinOps: 'Download-WindowsUpdate' alias is deprecated. Use 'Save-WindowsUpdate' (Download is not an approved verb). This alias will be removed in a future minor release."
}

# Import Private functions
$privatePath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private'
if (Test-Path -Path $privatePath) {
    Write-Verbose "[$($MyInvocation.MyCommand)] Loading Private functions from: $privatePath"
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse | ForEach-Object {
        Write-Verbose "[$($MyInvocation.MyCommand)] Importing private function: $($_.Name)"
        . $_.FullName
    }
}

# Import Public functions
$publicPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public'
if (Test-Path -Path $publicPath) {
    Write-Verbose "[$($MyInvocation.MyCommand)] Loading Public functions from: $publicPath"
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse | ForEach-Object {
        Write-Verbose "[$($MyInvocation.MyCommand)] Importing public function: $($_.Name)"
        . $_.FullName
    }
}

# ============================================================
# Short aliases for every public function
# ============================================================
$script:AliasMap = @{
    'cfms' = 'ConvertFrom-MisencodedString'
    'cla' = 'Clear-Arp'
    'cldc' = 'Clear-DiskCleanup'
    'clwuc' = 'Clear-WindowsUpdateCache'
    'conrs' = 'Connect-RdpSession'
    'ctm' = 'ConvertTo-Markdown'
    'dconrs' = 'Disconnect-RdpSession'
    'disaua' = 'Disable-ADUserAccount'
    'ehf' = 'Edit-HostsFile'
    'enaua' = 'Enable-ADUserAccount'
    'expnc' = 'Export-NetworkConfig'
    'gacd' = 'Get-ADComputerDetail'
    'gaci' = 'Get-ADComputerInventory'
    'gadch' = 'Get-AdDomainControllerHealth'
    'gadi' = 'Get-ADDomainInfo'
    'gagi' = 'Get-ADGroupInventory'
    'gagm' = 'Get-ADGroupMembership'
    'gah' = 'Get-ADFSHealth'
    'gala' = 'Get-ADLockedAccount'
    'gals' = 'Get-ADLockoutSource'
    'gangm' = 'Get-ADNestedGroupMembership'
    'gap' = 'Get-AuditPolicy'
    'gapa' = 'Get-ADPrivilegedAccount'
    'gaps' = 'Get-ADPasswordStatus'
    'gars' = 'Get-ADReplicationStatus'
    'gasa' = 'Get-ADStaleAccount'
    'gasc' = 'Get-ADStaleComputer'
    'gast' = 'Get-ADSiteTopology'
    'gat' = 'Get-ARPTable'
    'gaud' = 'Get-ADUserDetail'
    'gaugi' = 'Get-ADUserGroupInventory'
    'gaui' = 'Get-ADUserInventory'
    'gcah' = 'Get-CertificateAuthorityHealth'
    'gcd' = 'Get-CrashDump'
    'gch' = 'Get-ClusterHealth'
    'gcu' = 'Get-ComputerUptime'
    'gdci' = 'Get-DiskCleanupInfo'
    'gdee' = 'Get-DiskErrorEvent'
    'gdi' = 'Get-DriverInventory'
    'gdnh' = 'Get-DfsNamespaceHealth'
    'gdrh' = 'Get-DfsReplicationHealth'
    'gds' = 'Get-DiskSpace'
    'gdsh' = 'Get-DhcpServerHealth'
    'gdshe' = 'Get-DnsServerHealth'
    'gec' = 'Get-ExpiringCertificate'
    'gesh' = 'Get-ExchangeServerHealth'
    'gev' = 'Get-EnvironmentVariable'
    'gfsh' = 'Get-FileServerHealth'
    'ghvhh' = 'Get-HyperVHostHealth'
    'giaph' = 'Get-IISAppPoolHistory'
    'gicb' = 'Get-IISCertificateBinding'
    'gicr' = 'Get-IISCurrentRequest'
    'gifrt' = 'Get-IISFailedRequestTrace'
    'gih' = 'Get-IISHealth'
    'gipl' = 'Get-IISParsedLog'
    'gis' = 'Get-InstalledSoftware'
    'giwp' = 'Get-IISWorkerProcess'
    'glf' = 'Get-LogonFailure'
    'glp' = 'Get-ListeningPort'
    'gna' = 'Get-NetworkAdapter'
    'gnc' = 'Get-NTPConfiguration'
    'gnci' = 'Get-NetworkCIDR'
    'gnco' = 'Get-NetworkConnection'
    'gnp' = 'Get-NTPPeer'
    'gnr' = 'Get-NetworkRoute'
    'gns' = 'Get-NetworkStatistic'
    'gnss' = 'Get-NTPSyncStatus'
    'gpbp' = 'Get-ProcessByPort'
    'gpc' = 'Get-ProxyConfiguration'
    'gpce' = 'Get-ProcessCrashEvent'
    'gpfc' = 'Get-PageFileConfiguration'
    'gpia' = 'Get-PublicIPAddress'
    'gpr' = 'Get-PendingReboot'
    'gpsh' = 'Get-PrintServerHealth'
    'grh' = 'Get-RDSHealth'
    'grhi' = 'Get-RebootHistory'
    'grs' = 'Get-RdpSession'
    'grsh' = 'Get-RdpSessionHistory'
    'grsl' = 'Get-RdpSessionLock'
    'gsa' = 'Get-ServiceAccount'
    'gsc' = 'Get-SSLCertificate'
    'gsce' = 'Get-ServiceCrashEvent'
    'gsco' = 'Get-ShadowCopy'
    'gscs' = 'Get-ShadowCopyStorage'
    'gse' = 'Get-SchannelError'
    'gsh' = 'Get-ServiceHealth'
    'gsi' = 'Get-SubnetInfo'
    'gsp' = 'Get-StartupProgram'
    'gss' = 'Get-SystemSummary'
    'gstd' = 'Get-ScheduledTaskDetail'
    'gstf' = 'Get-ScheduledTaskFailure'
    'gus' = 'Get-UnexpectedShutdown'
    'gwh' = 'Get-WSUSHealth'
    'gwu' = 'Get-WindowsUpdate'
    'gwuc' = 'Get-WindowsUpdateConfiguration'
    'gwuf' = 'Get-WindowsUpdateFailure'
    'gwuh' = 'Get-WindowsUpdateHistory'
    'hwu' = 'Hide-WindowsUpdate'
    'iasa' = 'Invoke-ADSecurityAudit'
    'inswu' = 'Install-WindowsUpdate'
    'mnl' = 'Measure-NetworkLatency'
    'nnr' = 'New-NetworkRoute'
    'nrp' = 'New-RandomPassword'
    'nsc' = 'New-ShadowCopy'
    'restscf' = 'Restore-ShadowCopyFile'
    'rnr' = 'Remove-NetworkRoute'
    'rpc' = 'Remove-ProxyConfiguration'
    'rrs' = 'Remove-RdpSession'
    'rsc' = 'Remove-ShadowCopy'
    'rsd' = 'Remove-StringDiacritic'
    'rslvmv' = 'Resolve-MACVendor'
    'rstaup' = 'Reset-ADUserPassword'
    'rstns' = 'Reset-NetworkStack'
    'rstwuc' = 'Reset-WindowsUpdateComponent'
    'rup' = 'Remove-UserProfile'
    'seao' = 'Search-ADObject'
    'sev' = 'Set-EnvironmentVariable'
    'shnsm' = 'Show-NetworkStatisticMonitor'
    'shpm' = 'Show-PingMonitor'
    'shsm' = 'Show-SystemMonitor'
    'shwu' = 'Show-WindowsUpdate'
    'sibc' = 'Set-IISBindingCertificate'
    'snc' = 'Set-NTPClient'
    'snr' = 'Set-NetworkRoute'
    'spc' = 'Set-ProxyConfiguration'
    'spf' = 'Set-PageFile'
    'sscs' = 'Set-ShadowCopyStorage'
    'stppt' = 'Stop-ProcessTree'
    'svwu' = 'Save-WindowsUpdate'
    'synt' = 'Sync-NTPTime'
    'tdr' = 'Test-DNSResolution'
    'tibc' = 'Test-IISBindingCertificate'
    'tpc' = 'Test-PortConnectivity'
    'tpco' = 'Test-ProxyConnection'
    'trnr' = 'Trace-NetworkRoute'
    'twr' = 'Test-WinRM'
    'ulaua' = 'Unlock-ADUserAccount'
    'unswu' = 'Uninstall-WindowsUpdate'
    'wil' = 'Watch-IISLog'
}
foreach ($aliasName in $script:AliasMap.Keys) {
    Set-Alias -Name $aliasName -Value $script:AliasMap[$aliasName] -Scope Global
}

# ============================================================
# Argument completers for Active Directory Identity parameters
# ============================================================
# Each completer queries AD live, respects Server/Credential already
# typed on the command line, limits to 20 results, and silently
# returns nothing when the AD module is unavailable.

$script:ADUserCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $null = $commandName, $parameterName, $commandAst
    try {
        # Sanitize user-typed text to prevent LDAP filter injection / wildcard explosion.
        $safe = ($wordToComplete -as [string]) -replace '[\\\(\)\*\x00'']', ''
        if ([string]::IsNullOrWhiteSpace($safe)) { return }
        $splat = @{
            Filter        = "SamAccountName -like '$safe*'"
            Properties    = @('DisplayName')
            ResultSetSize = 20
            ErrorAction   = 'Stop'
        }
        if ($fakeBoundParameters.ContainsKey('Server'))     { $splat['Server']     = $fakeBoundParameters['Server'] }
        if ($fakeBoundParameters.ContainsKey('Credential')) { $splat['Credential'] = $fakeBoundParameters['Credential'] }

        Get-ADUser @splat |
            Sort-Object -Property 'SamAccountName' |
            ForEach-Object {
                $toolTip = if ($_.DisplayName) { "$($_.SamAccountName) ($($_.DisplayName))" } else { $_.SamAccountName }
                [System.Management.Automation.CompletionResult]::new(
                    $_.SamAccountName,
                    $_.SamAccountName,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    $toolTip
                )
            }
    }
    catch {
        Write-Verbose -Message "AD user completer unavailable: $_"
    }
}

$script:ADComputerCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $null = $commandName, $parameterName, $commandAst
    try {
        # Sanitize user-typed text to prevent LDAP filter injection / wildcard explosion.
        $safe = ($wordToComplete -as [string]) -replace '[\\\(\)\*\x00'']', ''
        if ([string]::IsNullOrWhiteSpace($safe)) { return }
        $splat = @{
            Filter        = "Name -like '$safe*'"
            ResultSetSize = 20
            ErrorAction   = 'Stop'
        }
        if ($fakeBoundParameters.ContainsKey('Server'))     { $splat['Server']     = $fakeBoundParameters['Server'] }
        if ($fakeBoundParameters.ContainsKey('Credential')) { $splat['Credential'] = $fakeBoundParameters['Credential'] }

        Get-ADComputer @splat |
            Sort-Object -Property 'Name' |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name,
                    $_.Name,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    "$($_.Name) ($($_.DistinguishedName))"
                )
            }
    }
    catch {
        Write-Verbose -Message "AD computer completer unavailable: $_"
    }
}

$script:ADGroupCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $null = $commandName, $parameterName, $commandAst
    try {
        # Sanitize user-typed text to prevent LDAP filter injection / wildcard explosion.
        $safe = ($wordToComplete -as [string]) -replace '[\\\(\)\*\x00'']', ''
        if ([string]::IsNullOrWhiteSpace($safe)) { return }
        $splat = @{
            Filter        = "Name -like '$safe*'"
            ResultSetSize = 20
            ErrorAction   = 'Stop'
        }
        if ($fakeBoundParameters.ContainsKey('Server'))     { $splat['Server']     = $fakeBoundParameters['Server'] }
        if ($fakeBoundParameters.ContainsKey('Credential')) { $splat['Credential'] = $fakeBoundParameters['Credential'] }

        Get-ADGroup @splat |
            Sort-Object -Property 'Name' |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name,
                    $_.Name,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    "$($_.Name) ($($_.GroupScope)/$($_.GroupCategory))"
                )
            }
    }
    catch {
        Write-Verbose -Message "AD group completer unavailable: $_"
    }
}

# Register user completers
$userFunctions = @(
    'Disable-ADUserAccount'
    'Enable-ADUserAccount'
    'Get-ADNestedGroupMembership'
    'Get-ADUserDetail'
    'Get-ADUserGroupInventory'
    'Reset-ADUserPassword'
    'Unlock-ADUserAccount'
)
foreach ($fn in $userFunctions) {
    Register-ArgumentCompleter -CommandName $fn -ParameterName 'Identity' -ScriptBlock $script:ADUserCompleter
}

# Register computer completer
Register-ArgumentCompleter -CommandName 'Get-ADComputerDetail' -ParameterName 'Identity' -ScriptBlock $script:ADComputerCompleter

# Register group completer
Register-ArgumentCompleter -CommandName 'Get-ADGroupMembership' -ParameterName 'Identity' -ScriptBlock $script:ADGroupCompleter

Write-Verbose "[$($MyInvocation.MyCommand)] PSWinOps module loaded successfully"
