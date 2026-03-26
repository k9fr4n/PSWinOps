#Requires -Version 5.1
function ConvertTo-ScheduledTaskResultMessage {
    <#
        .SYNOPSIS
            Converts an HRESULT code to a human-readable scheduled task result message

        .DESCRIPTION
            Maps common Windows Task Scheduler HRESULT codes to descriptive messages.
            Unknown codes are formatted as hexadecimal strings for diagnostic purposes.
            This is a private helper function used by Get-ScheduledTaskDetail.

        .PARAMETER ResultCode
            The HRESULT integer code returned by the Task Scheduler.
            Can be null if task run info was unavailable.

        .OUTPUTS
            System.String
            Returns a human-readable message describing the task result code.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-25
            Requires: PowerShell 5.1+ / Windows only
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$ResultCode
    )

    if ($null -eq $ResultCode) {
        return 'No run information available'
    }

    [int]$code = $ResultCode

    switch ($code) {
        0           { 'Success (0x0)' }
        1           { 'Incorrect function (0x1)' }
        2           { 'File not found (0x2)' }
        10          { 'Environment incorrect (0xA)' }
        267009      { 'Task is currently running (0x41301)' }
        267011      { 'Task has not yet run (0x41303)' }
        267014      { 'Task terminated by user (0x41306)' }
        -2147020576 { 'Operator or user refused (0x800710E0)' }
        -2147216609 { 'Instance already running (0x8004131F)' }
        default     { 'Unknown (0x{0:X})' -f $code }
    }
}
