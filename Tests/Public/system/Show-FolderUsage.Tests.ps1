#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force

    # A fixture tree of exactly-known byte sizes under a REAL TestDrive, so the
    # local contexts exercise the real aggregation scriptblock (recursion,
    # grouping, sorting, percentage, threshold, top) end to end.
    #
    #   Tree\a.log          2 MB  \
    #   Tree\Sub\b.log      1 MB  /  .log   = 3 MB, 2 files -> 60.00 %
    #   Tree\c.txt          1 MB     .txt   = 1 MB, 1 file  -> 20.00 %
    #   Tree\README         1 MB     (none) = 1 MB, 1 file  -> 20.00 %
    #   Tree\EmptySub\             (empty subfolder - walked, emits no row)
    #
    # Total is exactly 5 MB, so every percentage and MB value below is exact:
    # a double-count or a mis-grouping cannot hide in rounding noise.
    $script:treeRoot = Join-Path -Path $TestDrive -ChildPath 'Tree'
    $script:emptyRoot = Join-Path -Path $TestDrive -ChildPath 'EmptyTree'

    function script:NewSizedFile {
        param([string]$FilePath, [int]$Size)
        [System.IO.File]::WriteAllBytes($FilePath, [byte[]]::new($Size))
    }

    $script:subRoot = Join-Path -Path $script:treeRoot -ChildPath 'Sub'
    $null = New-Item -Path $script:subRoot -ItemType Directory -Force
    $null = New-Item -Path (Join-Path -Path $script:treeRoot -ChildPath 'EmptySub') -ItemType Directory -Force
    $null = New-Item -Path (Join-Path -Path $script:emptyRoot -ChildPath 'Nothing') -ItemType Directory -Force

    NewSizedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'a.log') -Size 2097152
    NewSizedFile -FilePath (Join-Path -Path $script:subRoot -ChildPath 'b.log') -Size 1048576
    NewSizedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'c.txt') -Size 1048576
    NewSizedFile -FilePath (Join-Path -Path $script:treeRoot -ChildPath 'README') -Size 1048576

    # Rows standing in for the target-side aggregation, so the remote contexts
    # (single machine, pipeline, credential, per-machine failure) stay
    # deterministic: only the dispatch, the parameter forwarding and the row
    # mapping are under test there. $TargetPath is echoed back so the forwarded
    # -ArgumentList[0] is proven by the returned Path property.
    $script:makeRows = {
        param([string]$TargetPath, [double]$MinPercent = 0, [int]$MaxRows = 0)

        $rows = @(
            [PSCustomObject]@{
                Path = $TargetPath; Extension = '.log'; FileCount = [long]2
                SizeBytes = [long]3145728; SizeMB = [double]3
                PercentOfTotal = [double]60; TotalSizeBytes = [long]4718592
                TotalFileCount = [long]7; InaccessibleCount = [long]2
            }
            [PSCustomObject]@{
                Path = $TargetPath; Extension = '.txt'; FileCount = [long]1
                SizeBytes = [long]1048576; SizeMB = [double]1
                PercentOfTotal = [double]20; TotalSizeBytes = [long]4718592
                TotalFileCount = [long]7; InaccessibleCount = [long]2
            }
            [PSCustomObject]@{
                Path = $TargetPath; Extension = '.png'; FileCount = [long]4
                SizeBytes = [long]524288; SizeMB = [double]0.5
                PercentOfTotal = [double]20; TotalSizeBytes = [long]4718592
                TotalFileCount = [long]7; InaccessibleCount = [long]2
            }
        )

        $rows = @($rows | Where-Object -FilterScript { $_.PercentOfTotal -ge $MinPercent })
        if ($MaxRows -gt 0) {
            $rows = @($rows | Select-Object -First $MaxRows)
        }

        $rows
    }
}

Describe 'Show-FolderUsage' {

    Context 'Local happy path (real fixture tree)' {

        BeforeAll {
            $script:result = @(Show-FolderUsage -Path $script:treeRoot)
            $script:byExtension = @{}
            foreach ($row in $script:result) {
                $script:byExtension[$row.Extension] = $row
            }
        }

        It -Name 'Should return PSWinOps.FolderUsage objects' -Test {
            $script:result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.FolderUsage'
        }

        It -Name 'Should default ComputerName to the local machine' -Test {
            ($script:result.ComputerName | Sort-Object -Unique) | Should -Be @($env:COMPUTERNAME)
        }

        It -Name 'Should emit one row per extension' -Test {
            $script:result | Should -HaveCount 3
            $script:result.Extension | Should -Contain '(none)'
            $script:result.Extension | Should -Contain '.log'
            $script:result.Extension | Should -Contain '.txt'
        }

        It -Name 'Should expose exactly the documented property set' -Test {
            $expected = @(
                'ComputerName', 'Path', 'Extension', 'FileCount', 'SizeBytes',
                'SizeMB', 'PercentOfTotal', 'TotalSizeBytes', 'TotalFileCount',
                'InaccessibleCount', 'Timestamp'
            )
            $actual = @($script:result[0].PSObject.Properties.Name)
            ($actual | Sort-Object) | Should -Be ($expected | Sort-Object)
        }

        It -Name 'Should report the resolved root path on every row' -Test {
            ($script:result.Path | Sort-Object -Unique) | Should -Be @($script:treeRoot)
        }

        It -Name 'Should accept Path as the first positional argument' -Test {
            @(Show-FolderUsage $script:treeRoot) | Should -HaveCount 3
        }

        It -Name 'Should recurse into subfolders' -Test {
            $script:byExtension['.log'].FileCount | Should -Be 2
        }

        It -Name 'Should group extensionless files under the (none) label' -Test {
            $script:byExtension.ContainsKey('(none)') | Should -BeTrue
            $script:byExtension['(none)'].FileCount | Should -Be 1
            $script:byExtension['(none)'].SizeBytes | Should -Be 1048576
        }

        It -Name 'Should sum exact byte totals per extension' -Test {
            $script:byExtension['.log'].SizeBytes | Should -Be 3145728
            $script:byExtension['.txt'].SizeBytes | Should -Be 1048576
            $script:byExtension['(none)'].SizeBytes | Should -Be 1048576
        }

        It -Name 'Should round SizeMB to two decimals' -Test {
            $script:byExtension['.log'].SizeMB | Should -Be 3
            $script:byExtension['.txt'].SizeMB | Should -Be 1
            $script:byExtension['(none)'].SizeMB | Should -Be 1
        }

        It -Name 'Should compute PercentOfTotal against the tree total' -Test {
            $script:byExtension['.log'].PercentOfTotal | Should -Be 60
            $script:byExtension['.txt'].PercentOfTotal | Should -Be 20
            $script:byExtension['(none)'].PercentOfTotal | Should -Be 20
        }

        It -Name 'Should sort rows descending by SizeBytes' -Test {
            $script:result[0].Extension | Should -Be '.log'
            for ($i = 0; $i -lt ($script:result.Count - 1); $i++) {
                $script:result[$i].SizeBytes | Should -BeGreaterOrEqual $script:result[$i + 1].SizeBytes
            }
        }

        It -Name 'Should repeat the exact tree totals on every row' -Test {
            foreach ($row in $script:result) {
                $row.TotalSizeBytes | Should -Be 5242880
                $row.TotalFileCount | Should -Be 4
            }
        }

        It -Name 'Should report InaccessibleCount 0 for a fully readable tree' -Test {
            ($script:result.InaccessibleCount | Sort-Object -Unique) | Should -Be @(0)
        }

        It -Name 'Should carry a per-row Timestamp' -Test {
            foreach ($row in $script:result) {
                $row.Timestamp | Should -Not -BeNullOrEmpty
            }
        }

        It -Name 'Should not embed ESC (char 27) in any property value' -Test {
            $esc = [regex]::Escape([string][char]27)
            foreach ($row in $script:result) {
                foreach ($prop in $row.PSObject.Properties) {
                    ($prop.Value | Out-String) | Should -Not -Match $esc
                }
            }
        }

        It -Name 'Should not expose a UsageBar property (the bar is view-only)' -Test {
            $script:result[0].PSObject.Properties.Name | Should -Not -Contain 'UsageBar'
            $script:result[0].PSObject.Properties.Name | Should -Not -Contain 'Usage'
        }
    }

    Context 'Empty tree (divide-by-zero guard)' {

        It -Name 'Should emit no rows for a tree without files and not throw' -Test {
            { Show-FolderUsage -Path $script:emptyRoot -ErrorAction Stop } | Should -Not -Throw
            @(Show-FolderUsage -Path $script:emptyRoot) | Should -HaveCount 0
        }

        It -Name 'Should Write-Verbose that the tree held no files' -Test {
            $verboseMessages = $null
            $null = Show-FolderUsage -Path $script:emptyRoot -Verbose -VerboseVariable verboseMessages
            ($verboseMessages | Out-String) | Should -Match 'contained no files'
        }
    }

    Context 'Threshold filtering (real fixture tree)' {

        It -Name 'Should keep only extensions at or above the threshold' -Test {
            $result = @(Show-FolderUsage -Path $script:treeRoot -Threshold 25)
            $result | Should -HaveCount 1
            $result[0].Extension | Should -Be '.log'
        }

        It -Name 'Should include rows exactly on the threshold' -Test {
            $result = @(Show-FolderUsage -Path $script:treeRoot -Threshold 20)
            $result | Should -HaveCount 3
        }

        It -Name 'Should accept the 100 upper boundary without rejecting it' -Test {
            @(Show-FolderUsage -Path $script:treeRoot -Threshold 100) | Should -HaveCount 0
        }
    }

    Context 'Top truncation (real fixture tree)' {

        It -Name 'Should keep only the largest extension when Top is 1' -Test {
            $result = @(Show-FolderUsage -Path $script:treeRoot -Top 1)
            $result | Should -HaveCount 1
            $result[0].Extension | Should -Be '.log'
            $result[0].SizeBytes | Should -Be 3145728
        }

        It -Name 'Should return every extension when Top exceeds the row count' -Test {
            @(Show-FolderUsage -Path $script:treeRoot -Top 1000) | Should -HaveCount 3
        }
    }

    Context 'Unreadable subfolder is counted, accessible rows still stream' {

        BeforeAll {
            # The enumeration raises a non-terminating error that the function
            # collects through -ErrorVariable: the readable remainder must still
            # be reported instead of discarding the whole tree.
            Mock -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -MockWith {
                Write-Error -Message 'Access to the path is denied.' -ErrorAction Continue
                [PSCustomObject]@{ Length = [long]2097152; Extension = '.log' }
            }
        }

        It -Name 'Should count the denial and keep the accessible rows' -Test {
            $result = @(Show-FolderUsage -Path $script:treeRoot)

            $result | Should -HaveCount 1
            $result[0].Extension | Should -Be '.log'
            $result[0].SizeBytes | Should -Be 2097152
            $result[0].PercentOfTotal | Should -Be 100
            $result[0].InaccessibleCount | Should -BeGreaterThan 0
            Should -Invoke -CommandName 'Get-ChildItem' -ModuleName 'PSWinOps' -Times 1 -Exactly
        }
    }

    Context 'Bad Path (per-machine error, no crash)' {

        It -Name 'Should write an error when the path does not exist' -Test {
            $missing = Join-Path -Path $script:treeRoot -ChildPath 'DoesNotExist'
            { Show-FolderUsage -Path $missing -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*does not exist*'
        }

        It -Name 'Should write an error when the path is a file' -Test {
            { Show-FolderUsage -Path (Join-Path -Path $script:treeRoot -ChildPath 'c.txt') -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*not a directory*'
        }
    }

    Context 'Remote single machine' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0]
            }
        }

        It -Name 'Should dispatch exactly once to the requested machine' -Test {
            $null = Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ComputerName -eq 'SRV01' }
        }

        It -Name 'Should forward Path to the target scriptblock' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data\App' -ComputerName 'SRV01')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[0] -eq 'C:\Data\App' }
            ($result.Path | Sort-Object -Unique) | Should -Be @('C:\Data\App')
        }

        It -Name 'Should not resolve the path locally for a remote query' -Test {
            # 'Z:\Does\Not\Exist' is meaningless on the test host; it must still be
            # handed to the target untouched and never validated locally.
            $result = @(Show-FolderUsage -Path 'Z:\Does\Not\Exist' -ComputerName 'SRV01')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[0] -eq 'Z:\Does\Not\Exist' }
            $result | Should -HaveCount 3
            ($result.Path | Sort-Object -Unique) | Should -Be @('Z:\Does\Not\Exist')
        }

        It -Name 'Should stamp the queried machine on every row' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01')
            ($result.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01')
            $result | Should -HaveCount 3
        }

        It -Name 'Should accept the CN alias for ComputerName' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -CN 'SRV01')
            ($result.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ComputerName -eq 'SRV01' }
        }

        It -Name 'Should map the target summary rows onto the output contract' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01')
            $result[0].PSObject.TypeNames | Should -Contain 'PSWinOps.FolderUsage'
            $result[0].Extension | Should -Be '.log'
            $result[0].FileCount | Should -Be 2
            $result[0].SizeBytes | Should -Be 3145728
            $result[0].SizeMB | Should -Be 3
            $result[0].PercentOfTotal | Should -Be 60
            $result[1].Extension | Should -Be '.txt'
            $result[1].PercentOfTotal | Should -Be 20
        }

        It -Name 'Should pass InaccessibleCount from the target through unchanged' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01')
            ($result.InaccessibleCount | Sort-Object -Unique) | Should -Be @(2)
        }

        It -Name 'Should map the tree totals onto every row' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01')
            foreach ($row in $result) {
                $row.TotalSizeBytes | Should -Be 4718592
                $row.TotalFileCount | Should -Be 7
            }
        }

        It -Name 'Should carry a per-row Timestamp' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01')
            foreach ($row in $result) {
                $row.Timestamp | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Credential propagation' {

        BeforeAll {
            $script:credential = [System.Management.Automation.PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString -String 'NotARealSecret' -AsPlainText -Force)
            )
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0]
            }
        }

        It -Name 'Should forward the credential to the remote dispatch' -Test {
            $null = Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01' -Credential $script:credential
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $null -ne $Credential -and $Credential.UserName -eq 'testuser' }
        }

        It -Name 'Should not attach a credential to a local query' -Test {
            $null = Show-FolderUsage -Path 'C:\Data'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $null -eq $Credential }
        }
    }

    Context 'Threshold and Top forwarding to the target' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0] -MinPercent $ArgumentList[1] -MaxRows $ArgumentList[2]
            }
        }

        It -Name 'Should default Threshold and Top to 0' -Test {
            $null = Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[1] -eq 0 -and $ArgumentList[2] -eq 0 }
        }

        It -Name 'Should forward Threshold as the second scriptblock argument' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01' -Threshold 25)
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[1] -eq 25 }
            $result | Should -HaveCount 1
            $result[0].Extension | Should -Be '.log'
        }

        It -Name 'Should forward Top as the third scriptblock argument' -Test {
            $result = @(Show-FolderUsage -Path 'C:\Data' -ComputerName 'SRV01' -Top 2)
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[2] -eq 2 }
            $result | Should -HaveCount 2
        }
    }

    Context 'Pipeline of multiple machines' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                & $script:makeRows -TargetPath $ArgumentList[0]
            }
        }

        It -Name 'Should query every piped machine once' -Test {
            $results = @(('SRV01', 'SRV02') | Show-FolderUsage -Path 'C:\Data')
            $results | Should -HaveCount 6
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should stamp a distinct ComputerName per machine' -Test {
            $results = @(('SRV01', 'SRV02') | Show-FolderUsage -Path 'C:\Data')
            ($results.ComputerName | Sort-Object -Unique) | Should -Be @('SRV01', 'SRV02')
        }

        It -Name 'Should accept Path from the pipeline by property name' -Test {
            $null = [PSCustomObject]@{ Path = 'C:\Piped\Tree' } | Show-FolderUsage -ComputerName 'SRV01'
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 1 -Exactly `
                -ParameterFilter { $ArgumentList[0] -eq 'C:\Piped\Tree' }
        }
    }

    Context 'Per-machine failure isolation' {

        BeforeAll {
            Mock -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -MockWith {
                if ($ComputerName -eq 'BADHOST') { throw 'boom' }
                & $script:makeRows -TargetPath $ArgumentList[0]
            }
        }

        It -Name 'Should surface a terminating error for the failed machine with ErrorAction Stop' -Test {
            { Show-FolderUsage -Path 'C:\Data' -ComputerName 'BADHOST' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*BADHOST*'
        }

        It -Name 'Should keep measuring the remaining machines' -Test {
            $results = @(('BADHOST', 'SRV02') | Show-FolderUsage -Path 'C:\Data' -ErrorAction SilentlyContinue)
            $results | Should -HaveCount 3
            ($results.ComputerName | Sort-Object -Unique) | Should -Be @('SRV02')
            Should -Invoke -CommandName 'Invoke-RemoteOrLocal' -ModuleName 'PSWinOps' -Times 2 -Exactly
        }

        It -Name 'Should write a non-terminating error naming the failed machine' -Test {
            $errors = @()
            $null = 'BADHOST', 'SRV02' | Show-FolderUsage -Path 'C:\Data' -ErrorAction SilentlyContinue -ErrorVariable +errors
            ($errors | Out-String) | Should -Match 'BADHOST'
        }
    }

    Context 'Parameter metadata' {

        BeforeAll {
            $script:commandInfo = Get-Command -Name 'Show-FolderUsage'
            $script:pathAttr = $script:commandInfo.Parameters['Path'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
            $script:computerAttr = $script:commandInfo.Parameters['ComputerName'].Attributes |
                Where-Object -FilterScript { $_ -is [System.Management.Automation.ParameterAttribute] }
        }

        It -Name 'Should declare Path as mandatory, position 0, by property name' -Test {
            $script:pathAttr.Mandatory | Should -BeTrue
            $script:pathAttr.Position | Should -Be 0
            $script:pathAttr.ValueFromPipelineByPropertyName | Should -BeTrue
            $script:pathAttr.ValueFromPipeline | Should -BeFalse
        }

        It -Name 'Should declare ComputerName for pipeline by value and by property name' -Test {
            $script:computerAttr.ValueFromPipeline | Should -BeTrue
            $script:computerAttr.ValueFromPipelineByPropertyName | Should -BeTrue
        }

        It -Name 'Should expose the spec aliases on ComputerName' -Test {
            foreach ($alias in @('CN', 'Name', 'DNSHostName')) {
                $script:commandInfo.Parameters['ComputerName'].Aliases | Should -Contain $alias
            }
        }
    }

    Context 'Parameter validation' {

        It -Name 'Should reject an empty Path' -Test {
            { Show-FolderUsage -Path '' } | Should -Throw
        }

        It -Name 'Should reject a null Path' -Test {
            { Show-FolderUsage -Path $null } | Should -Throw
        }

        It -Name 'Should reject a Threshold outside 0-100' -Test {
            { Show-FolderUsage -Path 'C:\Data' -Threshold -1 } | Should -Throw
            { Show-FolderUsage -Path 'C:\Data' -Threshold 101 } | Should -Throw
        }

        It -Name 'Should reject a Top outside 1-1000' -Test {
            { Show-FolderUsage -Path 'C:\Data' -Top 0 } | Should -Throw
            { Show-FolderUsage -Path 'C:\Data' -Top 1001 } | Should -Throw
        }

        It -Name 'Should reject an empty ComputerName' -Test {
            { Show-FolderUsage -Path 'C:\Data' -ComputerName '' } | Should -Throw
        }

        It -Name 'Should reject a null ComputerName' -Test {
            { Show-FolderUsage -Path 'C:\Data' -ComputerName $null } | Should -Throw
        }
    }

    Context 'Registration' {

        It -Name 'Should be exported from the module' -Test {
            Get-Command -Name 'Show-FolderUsage' -Module 'PSWinOps' | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should expose the sfu alias' -Test {
            (Get-Alias -Name 'sfu').ResolvedCommandName | Should -Be 'Show-FolderUsage'
        }
    }

    Context 'Format view' {

        BeforeAll {
            $script:formatPath = Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.Format.ps1xml'
            [xml]$script:formatXml = Get-Content -Path $script:formatPath -Raw

            $script:view = @($script:formatXml.Configuration.ViewDefinitions.View |
                    Where-Object -FilterScript { [string]$_.Name -eq 'PSWinOps.FolderUsage' })
        }

        It -Name 'Should parse PSWinOps.Format.ps1xml as XML' -Test {
            $script:formatXml | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should contain exactly one View named PSWinOps.FolderUsage' -Test {
            @($script:view) | Should -HaveCount 1
        }

        It -Name 'Should select the view by the spec PSTypeName' -Test {
            [string]$script:view[0].ViewSelectedBy.TypeName | Should -Be 'PSWinOps.FolderUsage'
        }

        It -Name 'Should render the view as a table' -Test {
            $script:view[0].TableControl | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should label the columns per the spec' -Test {
            $labels = @($script:view[0].TableControl.TableHeaders.TableColumnHeader |
                    ForEach-Object -Process { [string]$_.Label })
            $labels | Should -Be @('Extension', 'FileCount', 'Size(MB)', 'Percent', 'Usage')
        }

        It -Name 'Should render the usage bar from PercentOfTotal in the view ScriptBlock' -Test {
            $items = @($script:view[0].TableControl.TableRowEntries.TableRowEntry.TableColumnItems.TableColumnItem)
            $barItem = @($items | Where-Object -FilterScript { $null -ne $_.ScriptBlock })
            $barItem | Should -HaveCount 1
            $bar = [string]$barItem[0].ScriptBlock
            $bar | Should -Match 'PercentOfTotal'
            $bar | Should -Match '20'
        }
    }

    Context 'Comment-based help' {

        BeforeAll {
            $script:helpInfo = Get-Help -Name 'Show-FolderUsage' -Full
        }

        It -Name 'Should have a synopsis' -Test {
            $script:helpInfo.Synopsis.Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have a description' -Test {
            ($script:helpInfo.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        }

        It -Name 'Should have at least 3 examples' -Test {
            $script:helpInfo.Examples.Example.Count | Should -BeGreaterOrEqual 3
        }

        It -Name 'Should have an OUTPUTS section naming the object type' -Test {
            ($script:helpInfo.returnValues | Out-String) | Should -Match 'PSWinOps\.FolderUsage'
        }

        It -Name 'Should have Author in NOTES' -Test {
            ($script:helpInfo.alertSet | Out-String) | Should -Match 'Franck SALLET'
        }

        It -Name 'Should document every declared parameter' -Test {
            $expectedParams = @('Path', 'ComputerName', 'Threshold', 'Top', 'Credential')
            $documented = $script:helpInfo.parameters.parameter.name
            foreach ($param in $expectedParams) {
                $documented | Should -Contain $param
            }
        }
    }
}
