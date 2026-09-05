#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:formatPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'PSWinOps.Format.ps1xml'
    [xml]$script:formatXml = Get-Content -Path $script:formatPath -Raw

    $script:windowsUpdateResultTypes = @(
        'PSWinOps.PendingReboot'
        'PSWinOps.WindowsUpdateResetResult'
        'PSWinOps.WindowsUpdateCacheResult'
        'PSWinOps.WindowsUpdateDownloadResult'
        'PSWinOps.WindowsUpdateHideResult'
        'PSWinOps.WindowsUpdateInstallResult'
        'PSWinOps.WindowsUpdateShowResult'
        'PSWinOps.WindowsUpdateUninstallResult'
    )
}

Describe -Name 'PSWinOps format definitions' -Fixture {
    It -Name 'should have a valid XML format definition' -Test {
        $script:formatXml.Configuration.ViewDefinitions | Should -Not -BeNullOrEmpty
    }

    It -Name 'should define a functional view for each Windows Update result type' -Test {
        foreach ($typeName in $script:windowsUpdateResultTypes) {
            $views = @(
                $script:formatXml.Configuration.ViewDefinitions.View |
                    Where-Object { @($_.ViewSelectedBy.TypeName) -contains $typeName }
            )

            $views.Count | Should -BeGreaterThan 0 -Because "$typeName must have a format view"

            foreach ($view in $views) {
                $view.Name | Should -Not -BeNullOrEmpty
                ([bool]$view.TableControl -or [bool]$view.ListControl) | Should -BeTrue -Because "$typeName must use TableControl or ListControl"
            }
        }
    }
}
