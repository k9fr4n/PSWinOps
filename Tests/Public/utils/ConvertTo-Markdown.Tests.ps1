#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
    $script:newLine = "`n"
}

Describe 'ConvertTo-Markdown' {
    Context 'Metadata and parameter binding' {
        It 'is exported by the module' {
            Get-Command -Name 'ConvertTo-Markdown' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It 'returns a string' {
            $result = [pscustomobject]@{ Name = 'SRV01' } | ConvertTo-Markdown
            $result | Should -BeOfType ([string])
        }

        It 'accepts InputObject from the pipeline' {
            $command = Get-Command -Name 'ConvertTo-Markdown'
            $command.Parameters['InputObject'].Attributes.ValueFromPipeline | Should -BeTrue
        }

        It 'accepts multiple Property values' {
            $command = Get-Command -Name 'ConvertTo-Markdown'
            $command.Parameters['Property'].ParameterType | Should -Be ([string[]])
        }

        It 'has optional decoration parameters' {
            $command = Get-Command -Name 'ConvertTo-Markdown'
            foreach ($name in 'Title', 'PreContent', 'PostContent') {
                $command.Parameters[$name].Attributes.Mandatory | Should -BeFalse
            }
        }
    }

    Context 'Column ordering' {
        It 'preserves explicit property order exactly' {
            $row = [pscustomobject][ordered]@{
                Name   = 'SRV01'
                Status = 'OK'
                Count  = 2
            }

            $result = $row | ConvertTo-Markdown -Property Count, Name, Status

            $result | Should -Be "| Count | Name | Status |$script:newLine| --- | --- | --- |$script:newLine| 2 | SRV01 | OK |"
        }

        It 'does not alphabetically sort explicit properties' {
            $row = [pscustomobject][ordered]@{ Zulu = 'z'; Alpha = 'a' }

            $result = $row | ConvertTo-Markdown -Property Zulu, Alpha

            ($result -split $script:newLine)[0] | Should -Be '| Zulu | Alpha |'
        }

        It 'follows the first object property order automatically' {
            $rows = @(
                [pscustomobject][ordered]@{ Name = 'SRV01'; Status = 'OK' }
                [pscustomobject][ordered]@{ Name = 'SRV02'; Status = 'Warning' }
            )

            $result = $rows | ConvertTo-Markdown

            ($result -split $script:newLine)[0] | Should -Be '| Name | Status |'
        }

        It 'appends properties introduced by later objects' {
            $rows = @(
                [pscustomobject][ordered]@{ Name = 'SRV01'; Status = 'OK' }
                [pscustomobject][ordered]@{ Name = 'SRV02'; Status = 'Warning'; Details = 'Disk space low' }
            )

            $result = $rows | ConvertTo-Markdown

            ($result -split $script:newLine)[0] | Should -Be '| Name | Status | Details |'
            ($result -split $script:newLine)[2] | Should -Be '| SRV01 | OK |  |'
        }

        It 'preserves existing columns and row order' {
            $rows = @(
                [pscustomobject][ordered]@{ Z = 1; A = 'first' }
                [pscustomobject][ordered]@{ Z = 2; A = 'second'; M = 'later' }
                [pscustomobject][ordered]@{ Z = 3; A = 'third' }
            )

            $result = $rows | ConvertTo-Markdown
            $lines = $result -split $script:newLine

            $lines[0] | Should -Be '| Z | A | M |'
            $lines[2] | Should -Be '| 1 | first |  |'
            $lines[3] | Should -Be '| 2 | second | later |'
            $lines[4] | Should -Be '| 3 | third |  |'
        }

        It 'preserves ordered object properties' {
            $row = [pscustomobject][ordered]@{ Third = 3; First = 1; Second = 2 }

            $result = $row | ConvertTo-Markdown

            ($result -split $script:newLine)[0] | Should -Be '| Third | First | Second |'
        }

        It 'matches explicit properties case-insensitively' {
            $row = [pscustomobject]@{ Name = 'SRV01'; Status = 'OK' }

            $result = $row | ConvertTo-Markdown -Property name, status

            ($result -split $script:newLine)[2] | Should -Be '| SRV01 | OK |'
        }
    }

    Context 'Heterogeneous and scalar input' {
        It 'renders heterogeneous objects as one stable table' {
            $rows = @(
                [pscustomobject][ordered]@{ Name = 'SRV01'; Status = 'OK' }
                [pscustomobject][ordered]@{ Name = 'SRV02'; Details = 'Review' }
            )

            $result = $rows | ConvertTo-Markdown

            $result | Should -Match '\| Name \| Status \| Details \|'
            $result | Should -Match '\| SRV02 \|  \| Review \|'
        }

        It 'uses a Value column for scalar input' {
            $result = 'Running', 'Stopped' | ConvertTo-Markdown

            $result | Should -Be "| Value |$script:newLine| --- |$script:newLine| Running |$script:newLine| Stopped |"
        }

        It 'renders missing properties as empty cells' {
            $rows = @(
                [pscustomobject][ordered]@{ Name = 'SRV01'; Status = 'OK' }
                [pscustomobject][ordered]@{ Name = 'SRV02' }
            )

            $lines = ($rows | ConvertTo-Markdown) -split $script:newLine

            $lines[3] | Should -Be '| SRV02 |  |'
        }
    }

    Context 'Markdown rendering' {
        It 'escapes pipe characters in headers and values' {
            $row = [pscustomobject][ordered]@{ 'Status|Code' = 'OK|Ready' }

            $result = $row | ConvertTo-Markdown

            $result | Should -Match '\| Status\\\|Code \|'
            $result | Should -Match '\| OK\\\|Ready \|'
        }

        It 'converts CRLF, CR, and LF to br tags' {
            $row = [pscustomobject]@{ Details = "first`r`nsecond`rthird`nfourth" }

            $result = $row | ConvertTo-Markdown

            $result | Should -Match 'first<br>second<br>third<br>fourth'
        }

        It 'joins array values with comma-space' {
            $row = [pscustomobject]@{ Tags = @('one', 'two', 'three') }

            $result = $row | ConvertTo-Markdown

            $result | Should -Match '\| one, two, three \|'
        }

        It 'renders null values as empty cells' {
            $row = [pscustomobject][ordered]@{ Name = 'SRV01'; Details = $null }

            $result = $row | ConvertTo-Markdown

            $result | Should -Match '\| SRV01 \|  \|'
        }
    }

    Context 'Decorations and empty input' {
        It 'places the title before the table' {
            $row = [pscustomobject]@{ Name = 'SRV01' }

            $lines = ($row | ConvertTo-Markdown -Title 'Inventory') -split $script:newLine

            $lines[0] | Should -Be '# Inventory'
            $lines[1] | Should -Be '| Name |'
        }

        It 'preserves one pre-content line per element' {
            $row = [pscustomobject]@{ Name = 'SRV01' }

            $result = $row | ConvertTo-Markdown -PreContent 'Generated report', 'Environment: Production'
            $lines = $result -split $script:newLine

            $lines[0] | Should -Be 'Generated report'
            $lines[1] | Should -Be 'Environment: Production'
            $lines[2] | Should -Be '| Name |'
        }

        It 'places post-content after the table' {
            $row = [pscustomobject]@{ Name = 'SRV01' }

            $lines = ($row | ConvertTo-Markdown -PostContent 'End of report') -split $script:newLine

            $lines[-1] | Should -Be 'End of report'
        }

        It 'returns an empty string for empty input without decorations' {
            ConvertTo-Markdown | Should -BeExactly ''
        }

        It 'retains decorations when input is empty' {
            $result = ConvertTo-Markdown -Title 'Empty report' -PreContent 'No rows' -PostContent 'End'

            $result | Should -Be "# Empty report$($script:newLine)No rows$($script:newLine)End"
        }
    }
}

AfterAll {
    Remove-Module -Name 'PSWinOps' -Force -ErrorAction SilentlyContinue
}
