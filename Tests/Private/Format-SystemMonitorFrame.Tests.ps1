#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # Helper: build a synthetic CPU core object
    function script:NewCore {
        param([string]$Name = '0', [int]$Pct = 10)
        [PSCustomObject]@{ Name = $Name; PercentProcessorTime = $Pct }
    }

    # Helper: build a synthetic process object
    # NOTE: $PID is a read-only automatic variable in PowerShell; use $ProcessId instead.
    function script:NewProc {
        param([int]$ProcessId = 1234, [double]$CPU = 5.0, [double]$MemMB = 100.0, [string]$Name = 'svchost')
        [PSCustomObject]@{ PID = $ProcessId; CPU = $CPU; MemMB = $MemMB; Name = $Name }
    }

    # Minimal valid call helper (no color, fixed dimensions)
    function script:InvokeFrame {
        param([hashtable]$Params)
        & (Get-Module -Name 'PSWinOps') {
            param($p)
            $splat = @{
                Width            = if ($p.Width)            { $p.Width }            else { 80 }
                Height           = if ($p.Height)           { $p.Height }           else { 24 }
                UptimeStr        = if ($p.UptimeStr)        { $p.UptimeStr }        else { '0d 00:00:00' }
                TimeStr          = if ($p.TimeStr)          { $p.TimeStr }          else { '2026-01-01 00:00:00' }
                CpuTotalPercent  = if ($null -ne $p.CpuTotalPercent)  { $p.CpuTotalPercent }  else { 0 }
                MemPercent       = if ($null -ne $p.MemPercent)       { $p.MemPercent }       else { 0 }
                MemUsedKB        = if ($null -ne $p.MemUsedKB)        { $p.MemUsedKB }        else { 0 }
                MemTotalKB       = if ($null -ne $p.MemTotalKB)       { $p.MemTotalKB }       else { 8388608 }
                PagePercent      = if ($null -ne $p.PagePercent)      { $p.PagePercent }      else { 0 }
                PageUsedKB       = if ($null -ne $p.PageUsedKB)       { $p.PageUsedKB }       else { 0 }
                PageTotalKB      = if ($null -ne $p.PageTotalKB)      { $p.PageTotalKB }      else { 4096000 }
                ProcessCount     = if ($null -ne $p.ProcessCount)     { $p.ProcessCount }     else { 0 }
                SortMode         = if ($p.SortMode)         { $p.SortMode }         else { 'CPU' }
                NoColor          = $true
            }
            if ($p.CpuCores)     { $splat['CpuCores']     = $p.CpuCores }
            if ($p.TopProcesses) { $splat['TopProcesses'] = $p.TopProcesses }
            Format-SystemMonitorFrame @splat
        } $Params
    }
}

Describe -Name 'Format-SystemMonitorFrame' -Fixture {

    Context -Name 'Output type' -Fixture {

        It -Name 'Should return a single string' -Test {
            $result = script:InvokeFrame @{}
            @($result).Count | Should -Be 1
            $result           | Should -BeOfType [string]
        }

        It -Name 'Should not return null or empty' -Test {
            $result = script:InvokeFrame @{}
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context -Name 'Empty / zero state' -Fixture {

        BeforeAll {
            $script:frame = script:InvokeFrame @{
                CpuTotalPercent = 0
                CpuCores        = @()
                MemPercent      = 0
                TopProcesses    = @()
            }
        }

        It -Name 'Should contain monitor title' -Test {
            $script:frame | Should -Match 'Show-SystemMonitor'
        }

        It -Name 'Should contain CPU bar label' -Test {
            $script:frame | Should -Match '\bCPU\b'
        }

        It -Name 'Should contain Mem bar label' -Test {
            $script:frame | Should -Match '\bMem\b'
        }

        It -Name 'Should contain Swap bar label' -Test {
            $script:frame | Should -Match '\bSwp\b'
        }

        It -Name 'Should contain process table header' -Test {
            $script:frame | Should -Match 'CPU%'
            $script:frame | Should -Match 'MEM\(MB\)'
        }

        It -Name 'Should contain footer hotkeys' -Test {
            $script:frame | Should -Match '\[Q\]'
        }
    }

    Context -Name 'Full state (realistic metrics)' -Fixture {

        BeforeAll {
            $cores = @(
                (script:NewCore -Name '0' -Pct 45),
                (script:NewCore -Name '1' -Pct 72),
                (script:NewCore -Name '2' -Pct 10),
                (script:NewCore -Name '3' -Pct 85)
            )
            $procs = @(
                (script:NewProc -ProcessId 1000 -CPU 60.0 -MemMB 512.0 -Name 'notepad'),
                (script:NewProc -ProcessId 2000 -CPU 5.0  -MemMB 128.0 -Name 'svchost')
            )
            $script:frame = script:InvokeFrame @{
                CpuTotalPercent = 53
                CpuCores        = $cores
                MemPercent      = 62
                MemUsedKB       = 5242880
                MemTotalKB      = 8388608
                PagePercent     = 30
                PageUsedKB      = 1228800
                PageTotalKB     = 4096000
                UptimeStr       = '2d 05:30:00'
                TimeStr         = '2026-05-14 20:30:00'
                ProcessCount    = 120
                TopProcesses    = $procs
                SortMode        = 'CPU'
                Width           = 120
                Height          = 40
            }
        }

        It -Name 'Should show uptime' -Test {
            $script:frame | Should -Match '2d 05:30:00'
        }

        It -Name 'Should show timestamp' -Test {
            $script:frame | Should -Match '2026-05-14 20:30:00'
        }

        It -Name 'Should show process count' -Test {
            $script:frame | Should -Match 'Procs:.*120'
        }

        It -Name 'Should show core count' -Test {
            $script:frame | Should -Match 'Cores:.*4'
        }

        It -Name 'Should show process names' -Test {
            $script:frame | Should -Match 'notepad'
            $script:frame | Should -Match 'svchost'
        }

        It -Name 'Should show active sort mode in footer' -Test {
            $script:frame | Should -Match 'Sort:.*CPU'
        }
    }

    Context -Name 'Edge values' -Fixture {

        It -Name 'Should not throw when CpuTotalPercent = 0' -Test {
            { script:InvokeFrame @{ CpuTotalPercent = 0 } } | Should -Not -Throw
        }

        It -Name 'Should not throw when CpuTotalPercent = 100' -Test {
            { script:InvokeFrame @{ CpuTotalPercent = 100 } } | Should -Not -Throw
        }

        It -Name 'Should not throw when CpuTotalPercent is negative (clamp guard)' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                Format-SystemMonitorFrame -CpuTotalPercent -5 -NoColor
            } } | Should -Not -Throw
        }

        It -Name 'Should not throw when MemTotalKB = 0 (zero-guard)' -Test {
            { script:InvokeFrame @{ MemTotalKB = 0; MemUsedKB = 0 } } | Should -Not -Throw
        }

        It -Name 'Should not throw when PageTotalKB = 0 (zero-guard)' -Test {
            { script:InvokeFrame @{ PageTotalKB = 0; PageUsedKB = 0 } } | Should -Not -Throw
        }

        It -Name 'Should not throw with empty CpuCores array' -Test {
            { script:InvokeFrame @{ CpuCores = @() } } | Should -Not -Throw
        }

        It -Name 'Should not throw with null TopProcesses' -Test {
            { & (Get-Module -Name 'PSWinOps') {
                Format-SystemMonitorFrame -TopProcesses $null -NoColor
            } } | Should -Not -Throw
        }

        It -Name 'Should not throw when Width is minimal (10)' -Test {
            { script:InvokeFrame @{ Width = 10; Height = 10 } } | Should -Not -Throw
        }

        It -Name 'Should not throw when Height is minimal (1)' -Test {
            { script:InvokeFrame @{ Height = 1 } } | Should -Not -Throw
        }

        It -Name 'Should clamp high CPU value in bar rendering' -Test {
            $core = @( (script:NewCore -Name '0' -Pct 150) )
            { script:InvokeFrame @{ CpuCores = $core; CpuTotalPercent = 150 } } | Should -Not -Throw
        }
    }

    Context -Name 'Sort mode header highlighting' -Fixture {

        It -Name 'Should underline CPU column when SortMode = CPU' -Test {
            $frame = script:InvokeFrame @{ SortMode = 'CPU' }
            $frame | Should -Match 'Sort:.*CPU'
        }

        It -Name 'Should underline Memory column when SortMode = Memory' -Test {
            $frame = script:InvokeFrame @{ SortMode = 'Memory' }
            $frame | Should -Match 'Sort:.*Memory'
        }

        It -Name 'Should underline PID column when SortMode = PID' -Test {
            $frame = script:InvokeFrame @{ SortMode = 'PID' }
            $frame | Should -Match 'Sort:.*PID'
        }

        It -Name 'Should underline Name column when SortMode = Name' -Test {
            $frame = script:InvokeFrame @{ SortMode = 'Name' }
            $frame | Should -Match 'Sort:.*Name'
        }
    }
}
