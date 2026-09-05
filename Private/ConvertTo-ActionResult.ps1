#Requires -Version 5.1

function ConvertTo-ActionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Succeeded', 'Failed', 'WhatIf')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName = $env:COMPUTERNAME
    )

    [PSCustomObject]@{
        PSTypeName   = 'PSWinOps.ActionResult'
        ComputerName = $ComputerName
        Action       = $Action
        Target       = $Target
        Status       = $Status
        Error        = $ErrorMessage
        Timestamp    = Get-Date -Format 'o'
    }
}
