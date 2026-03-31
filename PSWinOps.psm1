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

Write-Verbose "[$($MyInvocation.MyCommand)] PSWinOps module loaded successfully"
