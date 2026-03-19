#Requires -Version 5.1

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}

Describe 'ConvertFrom-QUserIdleTime' {

    Context 'Active / no idle (dot and none)' {

        It 'Returns TimeSpan.Zero for a dot' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '.' }
            $result | Should -Be ([TimeSpan]::Zero)
        }

        It 'Returns TimeSpan.Zero for none' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString 'none' }
            $result | Should -Be ([TimeSpan]::Zero)
        }

        It 'Returns TimeSpan.Zero for an empty string' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '' }
            $result | Should -Be ([TimeSpan]::Zero)
        }

        It 'Returns TimeSpan.Zero for a whitespace-only string' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '   ' }
            $result | Should -Be ([TimeSpan]::Zero)
        }
    }

    Context 'Minutes-only format (integer string)' {

        It 'Converts 5 minutes correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '5' }
            $result | Should -Be ([TimeSpan]::FromMinutes(5))
        }

        It 'Converts 90 minutes correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '90' }
            $result | Should -Be ([TimeSpan]::FromMinutes(90))
        }

        It 'Converts 0 minutes to TimeSpan.Zero' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '0' }
            $result | Should -Be ([TimeSpan]::Zero)
        }
    }

    Context 'H:MM format' {

        It 'Converts 8:05 correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '8:05' }
            $result | Should -Be ([TimeSpan]::new(8, 5, 0))
        }

        It 'Converts 0:30 correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '0:30' }
            $result | Should -Be ([TimeSpan]::new(0, 30, 0))
        }

        It 'Converts 23:59 correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '23:59' }
            $result | Should -Be ([TimeSpan]::new(23, 59, 0))
        }
    }

    Context 'D+H:MM format' {

        It 'Converts 1+08:15 correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '1+08:15' }
            $result | Should -Be ([TimeSpan]::new(1, 8, 15, 0))
        }

        It 'Converts 0+00:01 correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '0+00:01' }
            $result | Should -Be ([TimeSpan]::new(0, 0, 1, 0))
        }

        It 'Converts 7+23:59 correctly' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '7+23:59' }
            $result | Should -Be ([TimeSpan]::new(7, 23, 59, 0))
        }
    }

    Context 'Unrecognised input (fallback to Zero)' {

        It 'Returns TimeSpan.Zero for an unrecognised string' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString 'bogus' }
            $result | Should -Be ([TimeSpan]::Zero)
        }

        It 'Returns TimeSpan.Zero for a partial H:MM-like string' {
            $result = & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime -IdleTimeString '8:' }
            $result | Should -Be ([TimeSpan]::Zero)
        }
    }

    Context 'Output type' {

        It 'Always returns a TimeSpan object' {
            $inputs = @('.', 'none', '', '5', '8:05', '1+08:15', 'bogus')
            foreach ($val in $inputs) {
                $result = & (Get-Module -Name 'PSWinOps') { param($v) ConvertFrom-QUserIdleTime -IdleTimeString $v } $val
                $result | Should -BeOfType [TimeSpan]
            }
        }
    }

    Context 'Parameter validation' {

        It 'Throws when IdleTimeString is not provided' {
            { & (Get-Module -Name 'PSWinOps') { ConvertFrom-QUserIdleTime } } | Should -Throw
        }
    }
}
