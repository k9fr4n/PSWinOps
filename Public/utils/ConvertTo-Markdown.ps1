#Requires -Version 5.1

function ConvertTo-Markdown {
    <#
        .SYNOPSIS
            Converts PowerShell objects into a GitHub-Flavored Markdown table

        .DESCRIPTION
            Converts pipeline input or explicitly supplied objects into one complete
            GitHub-Flavored Markdown table. Column and row order are deterministic:
            explicit properties retain the requested order, while automatic columns
            follow first-seen property order and append properties found later.

            Pipe characters are escaped, line breaks become <br>, arrays are joined
            with comma-space separators, and optional Markdown decorations can be
            emitted before or after the table.

        .PARAMETER InputObject
            One or more PowerShell objects to convert. Accepts input from the pipeline
            and preserves the order in which objects arrive.

        .PARAMETER Property
            Optional property names to render. The supplied order is authoritative;
            property names are matched case-insensitively and missing values are empty.

        .PARAMETER Title
            Optional level-one Markdown heading emitted before the table.

        .PARAMETER PreContent
            Optional Markdown lines emitted before the table, one element per line.

        .PARAMETER PostContent
            Optional Markdown lines emitted after the table, one element per line.

        .EXAMPLE
            Get-ScheduledTaskFailure | ConvertTo-Markdown
            Converts scheduled task failure objects into a Markdown table.

        .EXAMPLE
            Get-Service | ConvertTo-Markdown -Property Status, Name, DisplayName
            Renders the selected properties in the exact order supplied.

        .EXAMPLE
            'SRV01', 'SRV02' | ConvertTo-Markdown -Title 'Targets'
            Converts pipeline string values into a Markdown table with a Value column.

        .OUTPUTS
            System.String
            One complete Markdown document containing the requested decorations and table.

        .NOTES
            Author:        Franck SALLET
            Version:       1.0.0
            Last Modified: 2026-09-05
            Requires:      PowerShell 5.1+ / Windows only
            Permissions:   None required
            Module:        PSWinOps

        .LINK
            https://github.com/k9fr4n/PSWinOps

        .LINK
            https://github.github.com/gfm/#tables-extension-
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $false)]
        [string[]]$Property,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$PreContent,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$PostContent
    )

    begin {
        $rows = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in @($InputObject)) {
            [void]$rows.Add($item)
        }
    }

    end {
        $lines = [System.Collections.Generic.List[string]]::new()

        if ($null -ne $Title) {
            [void]$lines.Add("# $Title")
        }

        if ($null -ne $PreContent) {
            foreach ($line in $PreContent) {
                [void]$lines.Add($line)
            }
        }

        if ($rows.Count -gt 0) {
            $allRowsAreScalar = $true
            foreach ($row in $rows) {
                if ($null -ne $row -and $row -isnot [string] -and $row -isnot [System.ValueType]) {
                    $allRowsAreScalar = $false
                    break
                }
            }

            $columns = [System.Collections.Generic.List[string]]::new()

            if ($null -ne $Property -and $Property.Count -gt 0) {
                foreach ($propertyName in $Property) {
                    [void]$columns.Add($propertyName)
                }
            } elseif ($allRowsAreScalar) {
                [void]$columns.Add('Value')
            } else {
                $knownColumns = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                foreach ($row in $rows) {
                    if ($null -eq $row -or $row -is [string] -or $row -is [System.ValueType]) {
                        if ($knownColumns.Add('Value')) {
                            [void]$columns.Add('Value')
                        }
                        continue
                    }

                    foreach ($propertyInfo in $row.PSObject.Properties) {
                        if ($knownColumns.Add($propertyInfo.Name)) {
                            [void]$columns.Add($propertyInfo.Name)
                        }
                    }
                }
            }

            $escapeCell = {
                param([object]$Value)

                if ($null -eq $Value) {
                    return ''
                }

                if ($Value -is [System.Array]) {
                    $Value = $Value -join ', '
                }

                $text = [string]$Value
                $text = $text -replace '\|', '\|'
                $text = $text -replace "`r`n|`r|`n", '<br>'
                return $text
            }

            $headerCells = foreach ($column in $columns) {
                & $escapeCell $column
            }
            [void]$lines.Add("| $($headerCells -join ' | ') |")

            $separatorCells = foreach ($column in $columns) {
                '---'
            }
            [void]$lines.Add("| $($separatorCells -join ' | ') |")

            foreach ($row in $rows) {
                $cells = foreach ($column in $columns) {
                    $value = $null
                    $found = $false

                    if ($column -ieq 'Value' -and
                        ($null -eq $row -or $row -is [string] -or $row -is [System.ValueType])) {
                        $value = $row
                        $found = $true
                    } elseif ($null -ne $row -and
                        $row -isnot [string] -and
                        $row -isnot [System.ValueType]) {
                        foreach ($propertyInfo in $row.PSObject.Properties) {
                            if ($propertyInfo.Name -ieq $column) {
                                $value = $propertyInfo.Value
                                $found = $true
                                break
                            }
                        }
                    }

                    if ($found) {
                        & $escapeCell $value
                    } else {
                        ''
                    }
                }

                [void]$lines.Add("| $($cells -join ' | ') |")
            }
        }

        if ($null -ne $PostContent) {
            foreach ($line in $PostContent) {
                [void]$lines.Add($line)
            }
        }

        $lines -join "`n"
    }
}
