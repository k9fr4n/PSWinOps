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
# Argument completers for Active Directory Identity parameters
# ============================================================
# Each completer queries AD live, respects Server/Credential already
# typed on the command line, limits to 20 results, and silently
# returns nothing when the AD module is unavailable.

$script:ADUserCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $null = $commandName, $parameterName, $commandAst
    try {
        $splat = @{
            Filter      = "SamAccountName -like '$wordToComplete*'"
            Properties  = @('DisplayName')
            ErrorAction = 'Stop'
        }
        if ($fakeBoundParameters.ContainsKey('Server'))     { $splat['Server']     = $fakeBoundParameters['Server'] }
        if ($fakeBoundParameters.ContainsKey('Credential')) { $splat['Credential'] = $fakeBoundParameters['Credential'] }

        Get-ADUser @splat |
            Sort-Object -Property 'SamAccountName' |
            Select-Object -First 20 |
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
        $splat = @{
            Filter      = "Name -like '$wordToComplete*'"
            ErrorAction = 'Stop'
        }
        if ($fakeBoundParameters.ContainsKey('Server'))     { $splat['Server']     = $fakeBoundParameters['Server'] }
        if ($fakeBoundParameters.ContainsKey('Credential')) { $splat['Credential'] = $fakeBoundParameters['Credential'] }

        Get-ADComputer @splat |
            Sort-Object -Property 'Name' |
            Select-Object -First 20 |
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
        $splat = @{
            Filter      = "Name -like '$wordToComplete*'"
            ErrorAction = 'Stop'
        }
        if ($fakeBoundParameters.ContainsKey('Server'))     { $splat['Server']     = $fakeBoundParameters['Server'] }
        if ($fakeBoundParameters.ContainsKey('Credential')) { $splat['Credential'] = $fakeBoundParameters['Credential'] }

        Get-ADGroup @splat |
            Sort-Object -Property 'Name' |
            Select-Object -First 20 |
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
