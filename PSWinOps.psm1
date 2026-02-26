#Requires -Version 5.1

<#
.SYNOPSIS
    PSWinOps module loader

.DESCRIPTION
    Loads all public and private functions for the PSWinOps module.
    Public functions are automatically exported.
#>

# Get module root path
$script:ModuleRoot = $PSScriptRoot

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
