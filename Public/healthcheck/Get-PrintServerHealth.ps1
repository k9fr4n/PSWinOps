#Requires -Version 5.1
function Get-PrintServerHealth {
    <#
        .SYNOPSIS
            Retrieves print server health information from local or remote computers

        .DESCRIPTION
            Collects Spooler service status, printer counts by state, pending and errored
            print jobs, and port counts from one or more print servers. Each server produces
            a single typed object with an OverallHealth summary computed from the collected metrics.

        .PARAMETER ComputerName
            One or more computer names to query. Defaults to the local machine.
            Accepts pipeline input by value and by property name.

        .PARAMETER Credential
            Optional PSCredential for authenticating to remote computers.
            Not used for local queries.

        .EXAMPLE
            Get-PrintServerHealth

            Retrieves print server health for the local computer.

        .EXAMPLE
            Get-PrintServerHealth -ComputerName 'PRINT01'

            Retrieves print server health from a single remote server.

        .EXAMPLE
            'PRINT01', 'PRINT02' | Get-PrintServerHealth -Credential (Get-Credential)

            Retrieves print server health from multiple remote servers via pipeline.

        .OUTPUTS
            PSWinOps.PrintServerHealth
            Returns one object per server with service status, printer counts,
            job counts, port count, and an OverallHealth assessment.

        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: 2026-03-26
            Requires: PowerShell 5.1+ / Windows only
            Requires: PrintManagement module on target servers

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://learn.microsoft.com/en-us/powershell/module/printmanagement/
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.PrintServerHealth')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CN', 'Name', 'DNSHostName')]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Starting"
        $localNames = @($env:COMPUTERNAME, 'localhost', '.')

        $scriptBlock = {
            $serviceStatus = 'NotFound'
            $moduleAvailable = $false
            $totalPrinters = 0
            $printersOnline = 0
            $printersInError = 0
            $printersOffline = 0
            $totalPrintJobs = 0
            $erroredPrintJobs = 0
            $totalPorts = 0

            try {
                $svc = Get-Service -Name 'Spooler' -ErrorAction Stop
                $serviceStatus = $svc.Status.ToString()
            }
            catch {
                $serviceStatus = 'NotFound'
            }

            $modCheck = Get-Module -Name 'PrintManagement' -ListAvailable -ErrorAction SilentlyContinue
            if ($modCheck) { $moduleAvailable = $true }

            if ($moduleAvailable -and $serviceStatus -eq 'Running') {
                $printerList = @(Get-Printer -ErrorAction SilentlyContinue)
                $totalPrinters = $printerList.Count
                foreach ($p in $printerList) {
                    switch ($p.PrinterStatus) {
                        'Normal'   { $printersOnline++ }
                        'Error'    { $printersInError++ }
                        'Degraded' { $printersInError++ }
                        'Warning'  { $printersInError++ }
                        'Offline'  { $printersOffline++ }
                    }
                }

                $jobList = @(Get-PrintJob -PrinterName '*' -ErrorAction SilentlyContinue)
                $totalPrintJobs = $jobList.Count
                foreach ($j in $jobList) {
                    if ($j.JobStatus -match 'Error') { $erroredPrintJobs++ }
                }

                $totalPorts = @(Get-PrinterPort -ErrorAction SilentlyContinue).Count
            }

            @{
                ServiceStatus    = $serviceStatus
                ModuleAvailable  = $moduleAvailable
                TotalPrinters    = $totalPrinters
                PrintersOnline   = $printersOnline
                PrintersInError  = $printersInError
                PrintersOffline  = $printersOffline
                TotalPrintJobs   = $totalPrintJobs
                ErroredPrintJobs = $erroredPrintJobs
                TotalPorts       = $totalPorts
            }
        }
    }

    process {
        foreach ($machine in $ComputerName) {
            $displayName = $machine.ToUpper()
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Querying '${machine}'"

            try {
                $isLocal = $localNames -contains $machine
                if ($isLocal) {
                    $data = & $scriptBlock
                }
                else {
                    $invokeParams = @{
                        ComputerName = $machine
                        ScriptBlock  = $scriptBlock
                        ErrorAction  = 'Stop'
                    }
                    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
                        $invokeParams['Credential'] = $Credential
                    }
                    $data = Invoke-Command @invokeParams
                }

                if (-not $data.ModuleAvailable) {
                    $healthStatus = 'RoleUnavailable'
                }
                elseif ($data.ServiceStatus -ne 'Running' -or $data.PrintersInError -gt 0) {
                    $healthStatus = 'Critical'
                }
                elseif ($data.PrintersOffline -gt 0 -or $data.ErroredPrintJobs -gt 0) {
                    $healthStatus = 'Degraded'
                }
                else {
                    $healthStatus = 'Healthy'
                }

                [PSCustomObject]@{
                    PSTypeName       = 'PSWinOps.PrintServerHealth'
                    ComputerName     = $displayName
                    ServiceName      = 'Spooler'
                    ServiceStatus    = $data.ServiceStatus
                    TotalPrinters    = [int]$data.TotalPrinters
                    PrintersOnline   = [int]$data.PrintersOnline
                    PrintersInError  = [int]$data.PrintersInError
                    PrintersOffline  = [int]$data.PrintersOffline
                    TotalPrintJobs   = [int]$data.TotalPrintJobs
                    ErroredPrintJobs = [int]$data.ErroredPrintJobs
                    TotalPorts       = [int]$data.TotalPorts
                    OverallHealth    = $healthStatus
                    Timestamp        = Get-Date -Format 'o'
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