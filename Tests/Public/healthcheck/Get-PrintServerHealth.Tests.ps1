#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    & (Get-Module -Name 'PSWinOps') {
        foreach ($cmdName in @('Get-Printer', 'Get-PrintJob', 'Get-PrinterPort')) {
            if (-not (Get-Command -Name $cmdName -ErrorAction SilentlyContinue)) {
                Set-Item -Path "function:script:$cmdName" -Value ([scriptblock]::Create(''))
            }
        }
    }
}

Describe 'Get-PrintServerHealth' {

    BeforeAll {
        $script:mockRemoteData = @{
            ServiceStatus = 'Running'; ModuleAvailable = $true; TotalPrinters = 10
            PrintersOnline = 8; PrintersInError = 0; PrintersOffline = 0
            TotalPrintJobs = 25; ErroredPrintJobs = 0; TotalPorts = 12
        }

        function Set-PrintLocalMocks {
            param(
                [string]$ServiceStatus   = 'Running',
                [bool]$ServiceThrows     = $false,
                [bool]$ModuleAvailable   = $true,
                [array]$Printers         = @(),
                [array]$PrintJobs        = @(),
                [int]$PortCount          = 5
            )

            if ($ServiceThrows) {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith { throw 'Service not found' }
            }
            else {
                Mock -CommandName 'Get-Service' -ModuleName 'PSWinOps' -MockWith {
                    [PSCustomObject]@{ Status = $ServiceStatus; Name = 'Spooler' }
                }.GetNewClosure()
            }

            if ($ModuleAvailable) {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'PrintManagement' } -MockWith {
                    [PSCustomObject]@{ Name = 'PrintManagement'; Version = '1.1' }
                }
            }
            else {
                Mock -CommandName 'Get-Module' -ModuleName 'PSWinOps' -ParameterFilter { $Name -eq 'PrintManagement' } -MockWith { return $null }
            }

            Mock -CommandName 'Get-Printer' -ModuleName 'PSWinOps' -MockWith { return $Printers }.GetNewClosure()
            Mock -CommandName 'Get-PrintJob' -ModuleName 'PSWinOps' -MockWith { return $PrintJobs }.GetNewClosure()

            $portData = @(1..$([Math]::Max($PortCount,1)) | ForEach-Object { [PSCustomObject]@{ Name = "Port$_" } })
            if ($PortCount -eq 0) { $portData = @() }
            Mock -CommandName 'Get-PrinterPort' -ModuleName 'PSWinOps' -MockWith { return $portData }.GetNewClosure()

            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps'
        }
    }

    # =================================================================
    #  REMOTE PATH
    # =================================================================
    Context 'Remote - Healthy' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return correct printer count' { $script:result.TotalPrinters | Should -Be 10 }
        It 'Should return correct online count' { $script:result.PrintersOnline | Should -Be 8 }
        It 'Should return zero errors' { $script:result.PrintersInError | Should -Be 0 }
        It 'Should return correct port count' { $script:result.TotalPorts | Should -Be 12 }
    }

    Context 'Remote - RoleUnavailable' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ModuleAvailable = $false
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
    }

    Context 'Remote - Critical (service stopped)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ServiceStatus = 'Stopped'
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
    }

    Context 'Remote - Critical (printers in error)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.PrintersInError = 3
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should return error count' { $script:result.PrintersInError | Should -Be 3 }
    }

    Context 'Remote - Degraded (printers offline)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.PrintersOffline = 2
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Remote - Degraded (errored print jobs)' {
        BeforeAll {
            $d = $script:mockRemoteData.Clone(); $d.ErroredPrintJobs = 4
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $d }
            $script:result = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
    }

    Context 'Remote - Pipeline input' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:results = 'PRINT01', 'PRINT02' | Get-PrintServerHealth
        }
        It 'Should return two results' { $script:results | Should -HaveCount 2 }
    }

    Context 'Remote - Failure handling' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should not throw' { { Get-PrintServerHealth -ComputerName 'PRINT01' -ErrorAction SilentlyContinue } | Should -Not -Throw }
    }

    # =================================================================
    #  LOCAL PATH
    # =================================================================
    Context 'Local - Healthy (all printers Normal)' {
        BeforeAll {
            $prn = @(
                [PSCustomObject]@{ Name = 'P1'; PrinterStatus = 'Normal' },
                [PSCustomObject]@{ Name = 'P2'; PrinterStatus = 'Normal' }
            )
            Set-PrintLocalMocks -Printers $prn
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should call Get-Service' { Should -Invoke -CommandName 'Get-Service' -ModuleName 'PSWinOps' -Times 1 }
        It 'Should call Get-Printer' { Should -Invoke -CommandName 'Get-Printer' -ModuleName 'PSWinOps' -Times 1 }
        It 'Should call Get-PrintJob' { Should -Invoke -CommandName 'Get-PrintJob' -ModuleName 'PSWinOps' -Times 1 }
        It 'Should call Get-PrinterPort' { Should -Invoke -CommandName 'Get-PrinterPort' -ModuleName 'PSWinOps' -Times 1 }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return Running service' { $script:result.ServiceStatus | Should -Be 'Running' }
        It 'Should return TotalPrinters = 2' { $script:result.TotalPrinters | Should -Be 2 }
        It 'Should return PrintersOnline = 2' { $script:result.PrintersOnline | Should -Be 2 }
        It 'Should return PrintersInError = 0' { $script:result.PrintersInError | Should -Be 0 }
        It 'Should return PrintersOffline = 0' { $script:result.PrintersOffline | Should -Be 0 }
        It 'Should return ErroredPrintJobs = 0' { $script:result.ErroredPrintJobs | Should -Be 0 }
    }

    Context 'Local - Service not found (Get-Service throws)' {
        BeforeAll {
            Set-PrintLocalMocks -ServiceThrows $true
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return NotFound ServiceStatus' { $script:result.ServiceStatus | Should -Be 'NotFound' }
        It 'Should NOT call Get-Printer' { Should -Invoke -CommandName 'Get-Printer' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should NOT call Get-PrintJob' { Should -Invoke -CommandName 'Get-PrintJob' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Local - Module not available' {
        BeforeAll {
            Set-PrintLocalMocks -ModuleAvailable $false
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return RoleUnavailable' { $script:result.OverallHealth | Should -Be 'RoleUnavailable' }
        It 'Should NOT call Get-Printer' { Should -Invoke -CommandName 'Get-Printer' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Local - Service stopped (module available)' {
        BeforeAll {
            Set-PrintLocalMocks -ServiceStatus 'Stopped'
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should NOT call Get-Printer' { Should -Invoke -CommandName 'Get-Printer' -ModuleName 'PSWinOps' -Times 0 -Exactly }
    }

    Context 'Local - Printers in Error status (Critical)' {
        BeforeAll {
            $prn = @(
                [PSCustomObject]@{ Name = 'P1'; PrinterStatus = 'Normal' },
                [PSCustomObject]@{ Name = 'P2'; PrinterStatus = 'Error' }
            )
            Set-PrintLocalMocks -Printers $prn
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should count 1 printer in error' { $script:result.PrintersInError | Should -Be 1 }
    }

    Context 'Local - Printers with Warning and Degraded status count as error' {
        BeforeAll {
            $prn = @(
                [PSCustomObject]@{ Name = 'P1'; PrinterStatus = 'Warning' },
                [PSCustomObject]@{ Name = 'P2'; PrinterStatus = 'Degraded' },
                [PSCustomObject]@{ Name = 'P3'; PrinterStatus = 'Normal' }
            )
            Set-PrintLocalMocks -Printers $prn
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Critical' { $script:result.OverallHealth | Should -Be 'Critical' }
        It 'Should count 2 printers in error' { $script:result.PrintersInError | Should -Be 2 }
    }

    Context 'Local - Printers offline (Degraded)' {
        BeforeAll {
            $prn = @(
                [PSCustomObject]@{ Name = 'P1'; PrinterStatus = 'Normal' },
                [PSCustomObject]@{ Name = 'P2'; PrinterStatus = 'Offline' }
            )
            Set-PrintLocalMocks -Printers $prn
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should count 1 printer offline' { $script:result.PrintersOffline | Should -Be 1 }
        It 'Should count 0 printers in error' { $script:result.PrintersInError | Should -Be 0 }
    }

    Context 'Local - Errored print jobs (Degraded)' {
        BeforeAll {
            $prn = @([PSCustomObject]@{ Name = 'P1'; PrinterStatus = 'Normal' })
            $jobs = @(
                [PSCustomObject]@{ JobStatus = 'Error' },
                [PSCustomObject]@{ JobStatus = 'Printing' }
            )
            Set-PrintLocalMocks -Printers $prn -PrintJobs $jobs
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Degraded' { $script:result.OverallHealth | Should -Be 'Degraded' }
        It 'Should count 1 errored job' { $script:result.ErroredPrintJobs | Should -Be 1 }
    }

    Context 'Local - Empty printer list (Healthy)' {
        BeforeAll {
            Set-PrintLocalMocks -Printers @() -PortCount 0
            $script:result = Get-PrintServerHealth -ComputerName $env:COMPUTERNAME
        }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
        It 'Should return TotalPrinters = 0' { $script:result.TotalPrinters | Should -Be 0 }
    }

    Context 'Local - localhost alias' {
        BeforeAll {
            Set-PrintLocalMocks -Printers @([PSCustomObject]@{ Name = 'P1'; PrinterStatus = 'Normal' })
            $script:result = Get-PrintServerHealth -ComputerName 'localhost'
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return LOCALHOST as ComputerName' { $script:result.ComputerName | Should -Be 'LOCALHOST' }
        It 'Should return Healthy' { $script:result.OverallHealth | Should -Be 'Healthy' }
    }

    Context 'Local - dot alias' {
        BeforeAll {
            Set-PrintLocalMocks -Printers @([PSCustomObject]@{ Name = 'P1'; PrinterStatus = 'Normal' })
            $script:result = Get-PrintServerHealth -ComputerName '.'
        }
        It 'Should NOT call Invoke-Command' { Should -Invoke -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -Times 0 -Exactly }
        It 'Should return a result' { $script:result | Should -Not -BeNullOrEmpty }
    }

    # =================================================================
    #  COMMON VALIDATIONS
    # =================================================================
    Context 'PSTypeName validation' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should have PSTypeName PSWinOps.PrintServerHealth' { $script:typeResult.PSObject.TypeNames[0] | Should -Be 'PSWinOps.PrintServerHealth' }
    }

    Context 'Timestamp ISO 8601 format' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:typeResult = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should have Timestamp matching ISO 8601' { $script:typeResult.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T' }
    }

    Context 'Output property completeness' {
        BeforeAll {
            Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { return $script:mockRemoteData.Clone() }
            $script:hpResult = Get-PrintServerHealth -ComputerName 'PRINT01'
        }
        It 'Should have ComputerName set to PRINT01' { $script:hpResult.ComputerName | Should -Be 'PRINT01' }
        It 'Should have ServiceName = Spooler' { $script:hpResult.ServiceName | Should -Be 'Spooler' }
        It 'Should have TotalPrinters' { $script:hpResult.TotalPrinters | Should -Be 10 }
        It 'Should have PrintersOnline' { $script:hpResult.PrintersOnline | Should -Be 8 }
        It 'Should have PrintersInError' { $script:hpResult.PrintersInError | Should -Be 0 }
        It 'Should have PrintersOffline' { $script:hpResult.PrintersOffline | Should -Be 0 }
        It 'Should have TotalPrintJobs' { $script:hpResult.TotalPrintJobs | Should -Be 25 }
        It 'Should have ErroredPrintJobs' { $script:hpResult.ErroredPrintJobs | Should -Be 0 }
        It 'Should have TotalPorts' { $script:hpResult.TotalPorts | Should -Be 12 }
        It 'Should have OverallHealth' { $script:hpResult.OverallHealth | Should -Not -BeNullOrEmpty }
    }

    Context 'Parameter validation' {
        It 'Should reject empty ComputerName' { { Get-PrintServerHealth -ComputerName '' } | Should -Throw }
        It 'Should reject null ComputerName' { { Get-PrintServerHealth -ComputerName $null } | Should -Throw }
    }

    Context 'Error message content on failure' {
        BeforeAll { Mock -CommandName 'Invoke-Command' -ModuleName 'PSWinOps' -MockWith { throw 'Connection refused' } }
        It 'Should include computer name in error message' {
            Get-PrintServerHealth -ComputerName 'BADHOST' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'BADHOST'
        }
        It 'Should include function name in error message' {
            Get-PrintServerHealth -ComputerName 'BADHOST2' -ErrorVariable err -ErrorAction SilentlyContinue
            ($err | ForEach-Object { $_.Exception.Message }) -join ' ' | Should -Match 'Get-PrintServerHealth'
        }
    }
}
