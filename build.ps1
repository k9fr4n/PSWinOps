#Requires -Version 5.1

<#
.SYNOPSIS
    Build script for the PSWinOps module

.DESCRIPTION
    Automates the complete build pipeline for PSWinOps module development.
    Performs static code analysis with PSScriptAnalyzer, executes Pester unit tests,
    assembles the module from Private and Public function directories into a single
    PSM1 file, updates version metadata in the module manifest, and generates a
    distribution package ready for publication to PowerShell Gallery.

.PARAMETER Task
    The build task to execute. Valid options are:
    - Analyze: Run PSScriptAnalyzer static analysis only
    - Test: Execute Pester unit tests only
    - Build: Assemble module files and update manifest
    - Package: Create distribution ZIP file
    - All: Execute all tasks in sequence (default)

.PARAMETER BumpVersion
    The semantic version component to increment during the build.
    - Major: Increment major version (1.0.0 -> 2.0.0)
    - Minor: Increment minor version (1.0.0 -> 1.1.0)
    - Patch: Increment patch version (1.0.0 -> 1.0.1) (default)

.EXAMPLE
    .\build.ps1

    Executes all build tasks (Analyze, Test, Build, Package) with a patch version bump.

.EXAMPLE
    .\build.ps1 -Task Test

    Executes only the Pester test suite without building or packaging.

.EXAMPLE
    .\build.ps1 -Task Build -BumpVersion Minor

    Builds the module and increments the minor version number.

.EXAMPLE
    .\build.ps1 -Task All -BumpVersion Major -Verbose

    Executes the complete build pipeline with major version increment and verbose logging.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+, Pester 5.x, PSScriptAnalyzer
    Permissions:   Write access to module directory and output path

.LINK
    https://github.com/pester/Pester

.LINK
    https://github.com/PowerShell/PSScriptAnalyzer
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Analyze', 'Test', 'Build', 'Package', 'All')]
    [string]$Task = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$BumpVersion = 'Patch'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =========================================================================
# MODULE-LEVEL VARIABLES
# =========================================================================

$script:ModuleName = 'PSWinOps'
$script:RootPath = $PSScriptRoot
$script:SrcPath = $script:RootPath
$script:OutputPath = Join-Path -Path $script:RootPath -ChildPath 'output'
$script:ModuleOutput = Join-Path -Path $script:OutputPath -ChildPath $script:ModuleName
$script:ManifestPath = Join-Path -Path $script:SrcPath -ChildPath "$script:ModuleName.psd1"

# =========================================================================
# HELPER FUNCTIONS
# =========================================================================

function Write-BuildStep {
    <#
.SYNOPSIS
    Writes a major build step header to the information stream

.DESCRIPTION
    Outputs a formatted section header to the information stream to clearly
    delineate major phases of the build process. Uses ASCII box-drawing
    characters for visual separation and includes the step description.

.PARAMETER Message
    The build step description to display in the header.

.EXAMPLE
    Write-BuildStep -Message 'Running static code analysis'

    Displays a formatted header for the analysis phase.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+
    Permissions:   None required
#>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    process {
        Write-Information -MessageData '' -InformationAction Continue
        Write-Information -MessageData "--- $Message ---" -InformationAction Continue
    }
}

function Write-BuildSuccess {
    <#
.SYNOPSIS
    Writes a success message to the information stream

.DESCRIPTION
    Outputs a formatted success message with a visual indicator to the
    information stream. Used to report successful completion of individual
    build operations or validation checks.

.PARAMETER Message
    The success message to display.

.EXAMPLE
    Write-BuildSuccess -Message 'All tests passed'

    Displays a success indicator followed by the message.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+
    Permissions:   None required
#>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    process {
        Write-Information -MessageData "  [OK] $Message" -InformationAction Continue
    }
}

function Write-BuildFailure {
    <#
.SYNOPSIS
    Writes a failure message to the warning stream

.DESCRIPTION
    Outputs a formatted failure message with a visual indicator to the
    warning stream. Used to report failed operations or validation checks
    during the build process.

.PARAMETER Message
    The failure message to display.

.EXAMPLE
    Write-BuildFailure -Message 'Code analysis detected 5 issues'

    Displays a failure indicator followed by the message.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+
    Permissions:   None required
#>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    process {
        Write-Warning -Message "  [FAIL] $Message"
    }
}

# =========================================================================
# BUILD DEPENDENCY MANAGEMENT
# =========================================================================

function Install-BuildDependency {
    <#
.SYNOPSIS
    Verifies and installs required build tool modules

.DESCRIPTION
    Checks for the presence of required PowerShell modules (Pester and
    PSScriptAnalyzer) and installs any missing dependencies from the
    PowerShell Gallery to the current user scope. This ensures the build
    environment has all necessary tools before executing build tasks.

.EXAMPLE
    Install-BuildDependency

    Checks for and installs Pester and PSScriptAnalyzer if not present.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+, Internet access, PSGallery repository registered
    Permissions:   Ability to install modules in CurrentUser scope
#>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    process {
        Write-BuildStep -Message 'Verifying build dependencies'

        $dependencies = @('Pester', 'PSScriptAnalyzer')

        foreach ($moduleName in $dependencies) {
            if (-not (Get-Module -ListAvailable -Name $moduleName)) {
                Write-Information -MessageData "  --> Installing $moduleName..." -InformationAction Continue
                Install-Module -Name $moduleName -Force -Scope CurrentUser -Repository PSGallery
            } else {
                Write-BuildSuccess -Message "$moduleName is available"
            }
        }
    }
}

# =========================================================================
# TASK: STATIC CODE ANALYSIS
# =========================================================================

function Invoke-CodeAnalysis {
    <#
.SYNOPSIS
    Executes PSScriptAnalyzer static code analysis

.DESCRIPTION
    Runs PSScriptAnalyzer against the module source code (Public and Private
    directories only) to detect code quality issues, style violations, and
    potential bugs. Test files are explicitly excluded from analysis. Supports
    both custom settings files and default rule configurations. Throws an
    exception if any errors or warnings are detected, halting the build.

.EXAMPLE
    Invoke-CodeAnalysis

    Analyzes all PowerShell files in Public/ and Private/ directories only.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.2
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+, PSScriptAnalyzer module
    Permissions:   Read access to source code directory
#>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    process {
        Write-BuildStep -Message 'Running PSScriptAnalyzer'

        # Build list of directories to analyze (exclude Tests/)
        $pathsToAnalyze = [System.Collections.Generic.List[string]]::new()

        $publicPath = Join-Path -Path $script:SrcPath -ChildPath 'Public'
        $privatePath = Join-Path -Path $script:SrcPath -ChildPath 'Private'

        if (Test-Path -Path $publicPath) {
            $pathsToAnalyze.Add($publicPath)
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Including Public directory: $publicPath"
        }

        if (Test-Path -Path $privatePath) {
            $pathsToAnalyze.Add($privatePath)
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Including Private directory: $privatePath"
        }

        if ($pathsToAnalyze.Count -eq 0) {
            Write-Warning -Message "[$($MyInvocation.MyCommand)] No Public or Private directories found. Skipping analysis."
            return
        }

        $settingsFile = Join-Path -Path $script:RootPath -ChildPath 'PSScriptAnalyzerSettings.psd1'

        # Base parameters for analysis
        $analyzeParams = @{
            Recurse  = $true
            Severity = @('Error', 'Warning')
        }

        if (Test-Path -Path $settingsFile) {
            $analyzeParams['Settings'] = $settingsFile
            $analyzeParams.Remove('Severity')
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Using settings file: $settingsFile"
        }

        Write-Information -MessageData '  --> Analyzing Public/ and Private/ directories (Tests/ excluded)' -InformationAction Continue

        # Analyze each directory separately and aggregate results
        $allResults = [System.Collections.Generic.List[object]]::new()

        foreach ($path in $pathsToAnalyze) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Analyzing: $path"
            $results = Invoke-ScriptAnalyzer -Path $path @analyzeParams

            if ($results) {
                foreach ($result in $results) {
                    $allResults.Add($result)
                }
            }
        }

        if ($allResults.Count -gt 0) {
            $allResults | Format-Table -AutoSize | Out-String | Write-Information -InformationAction Continue
            Write-BuildFailure -Message "$($allResults.Count) issue(s) detected"
            throw 'PSScriptAnalyzer found errors. Build halted.'
        } else {
            Write-BuildSuccess -Message 'No issues detected'
        }
    }
}

# =========================================================================
# TASK: UNIT TESTS
# =========================================================================

function Invoke-UnitTest {
    <#
.SYNOPSIS
    Executes Pester unit tests with code coverage analysis

.DESCRIPTION
    Runs the Pester v5 test suite against the module code with code coverage
    enabled. Supports custom Pester configuration files and enforces a
    minimum code coverage threshold. Throws an exception if any tests fail,
    halting the build process.

.EXAMPLE
    Invoke-UnitTest

    Executes all tests in the Tests directory with coverage reporting.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+, Pester 5.x
    Permissions:   Read access to source and test directories
#>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    process {
        Write-BuildStep -Message 'Running Pester unit tests'

        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = Join-Path -Path $script:RootPath -ChildPath 'Tests'
        $pesterConfig.Run.Exit = $false
        $pesterConfig.Output.Verbosity = 'Detailed'
        $pesterConfig.CodeCoverage.Enabled = $true
        $pesterConfig.CodeCoverage.Path = @(
            Join-Path -Path $script:RootPath -ChildPath 'Public'
            Join-Path -Path $script:RootPath -ChildPath 'Private'
        )
        $pesterConfig.CodeCoverage.CoveragePercentTarget = 70

        # Load custom configuration if present
        $configFile = Join-Path -Path $script:RootPath -ChildPath 'Tests' -AdditionalChildPath 'pester.config.ps1'
        if (Test-Path -Path $configFile) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Loading custom Pester config: $configFile"
            $pesterConfig = & $configFile
        }

        $result = Invoke-Pester -Configuration $pesterConfig

        if ($result.FailedCount -gt 0) {
            Write-BuildFailure -Message "$($result.FailedCount) test(s) failed out of $($result.TotalCount)"
            throw 'Pester tests failed. Build halted.'
        } else {
            Write-BuildSuccess -Message "$($result.PassedCount)/$($result.TotalCount) tests passed"
        }
    }
}

# =========================================================================
# TASK: MODULE BUILD
# =========================================================================

function Invoke-ModuleBuild {
    <#
.SYNOPSIS
    Assembles the module and updates version metadata

.DESCRIPTION
    Combines all Private and Public function files into a single PSM1 module
    file, updates the module manifest with incremented version number and
    exported function list, and prepares the output directory structure.
    The version number is incremented according to the BumpVersion parameter
    and updated in both the output manifest and the source manifest.

.EXAMPLE
    Invoke-ModuleBuild

    Builds the module with default patch version increment.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+
    Permissions:   Write access to source and output directories
#>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    process {
        Write-BuildStep -Message 'Building module assembly'

        # Clean and recreate output directory
        if (Test-Path -Path $script:ModuleOutput) {
            Write-Verbose -Message "[$($MyInvocation.MyCommand)] Removing existing output: $script:ModuleOutput"
            Remove-Item -Path $script:ModuleOutput -Recurse -Force
        }
        $null = New-Item -Path $script:ModuleOutput -ItemType Directory

        # === Assemble PSM1 file ===

        $psm1Output = Join-Path -Path $script:ModuleOutput -ChildPath "$script:ModuleName.psm1"
        $psm1Content = [System.Text.StringBuilder]::new()

        # Header comment
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $null = $psm1Content.AppendLine("# Auto-generated by build.ps1 at $timestamp")
        $null = $psm1Content.AppendLine('')

        # Include Private functions
        $privatePath = Join-Path -Path $script:SrcPath -ChildPath 'Private'
        if (Test-Path -Path $privatePath) {
            $privateFiles = Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse
            foreach ($file in $privateFiles) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Including Private: $($file.Name)"
                $null = $psm1Content.AppendLine("# --- Private: $($file.Name) ---")
                $null = $psm1Content.AppendLine((Get-Content -Path $file.FullName -Raw))
                $null = $psm1Content.AppendLine('')
            }
        }

        # Include Public functions and track exported names
        $publicPath = Join-Path -Path $script:SrcPath -ChildPath 'Public'
        $exportedFunctions = [System.Collections.Generic.List[string]]::new()

        if (Test-Path -Path $publicPath) {
            $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse
            foreach ($file in $publicFiles) {
                Write-Verbose -Message "[$($MyInvocation.MyCommand)] Including Public: $($file.Name)"
                $null = $psm1Content.AppendLine("# --- Public: $($file.Name) ---")
                $null = $psm1Content.AppendLine((Get-Content -Path $file.FullName -Raw))
                $null = $psm1Content.AppendLine('')
                $functionName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $exportedFunctions.Add($functionName)
            }
        }

        # Export-ModuleMember statement
        if ($exportedFunctions.Count -gt 0) {
            $null = $psm1Content.AppendLine('Export-ModuleMember -Function @(')
            foreach ($fn in $exportedFunctions) {
                $null = $psm1Content.AppendLine("    '$fn',")
            }
            $null = $psm1Content.AppendLine(')')
        }

        Set-Content -Path $psm1Output -Value $psm1Content.ToString() -Encoding UTF8
        Write-BuildSuccess -Message "PSM1 assembled with $($exportedFunctions.Count) exported function(s)"

        # === Update module manifest ===

        $psd1Output = Join-Path -Path $script:ModuleOutput -ChildPath "$script:ModuleName.psd1"
        Copy-Item -Path $script:ManifestPath -Destination $psd1Output

        # Calculate new version
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        $currentVersion = [version]$manifest.ModuleVersion

        $newVersion = switch ($BumpVersion) {
            'Major' {
                [version]::new($currentVersion.Major + 1, 0, 0)
            }
            'Minor' {
                [version]::new($currentVersion.Major, $currentVersion.Minor + 1, 0)
            }
            'Patch' {
                [version]::new($currentVersion.Major, $currentVersion.Minor, $currentVersion.Build + 1)
            }
        }

        Write-Verbose -Message "[$($MyInvocation.MyCommand)] Updating version: $currentVersion -> $newVersion"

        # Update output manifest
        Update-ModuleManifest -Path $psd1Output -ModuleVersion $newVersion -FunctionsToExport $exportedFunctions.ToArray()
        Write-BuildSuccess -Message "Output manifest updated: $currentVersion -> $newVersion"

        # Update source manifest
        Update-ModuleManifest -Path $script:ManifestPath -ModuleVersion $newVersion -FunctionsToExport $exportedFunctions.ToArray()
        Write-BuildSuccess -Message 'Source manifest synchronized'
    }
}

# =========================================================================
# TASK: PACKAGE CREATION
# =========================================================================

function Invoke-PackageCreation {
    <#
.SYNOPSIS
    Creates a distribution package for PSGallery publication

.DESCRIPTION
    Validates the assembled module manifest and creates a compressed ZIP
    archive of the module ready for distribution or publication to the
    PowerShell Gallery. The package filename includes the module version
    number for easy identification.

.EXAMPLE
    Invoke-PackageCreation

    Creates a versioned ZIP package in the output directory.

.NOTES
    Author:        Franck SALLET
    Version:       1.0.0
    Last Modified: 2026-02-26
    Requires:      PowerShell 5.1+
    Permissions:   Write access to output directory
#>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    process {
        Write-BuildStep -Message 'Creating distribution package'

        if (-not (Test-Path -Path $script:ModuleOutput)) {
            throw "Output directory does not exist: $script:ModuleOutput. Run the Build task first."
        }

        # Validate manifest
        $manifestPath = Join-Path -Path $script:ModuleOutput -ChildPath "$script:ModuleName.psd1"
        $null = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        Write-BuildSuccess -Message 'Module manifest is valid'

        # Create versioned package
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $version = $manifest.ModuleVersion
        $zipPath = Join-Path -Path $script:OutputPath -ChildPath "$script:ModuleName-$version.zip"

        Compress-Archive -Path "$script:ModuleOutput\*" -DestinationPath $zipPath -Force
        Write-BuildSuccess -Message "Package created: $zipPath"

        Write-Information -MessageData '' -InformationAction Continue
        Write-Information -MessageData '  [INFO] To publish to PowerShell Gallery:' -InformationAction Continue
        Write-Information -MessageData "         Publish-Module -Path '$script:ModuleOutput' -NuGetApiKey `$env:PSGALLERY_API_KEY" -InformationAction Continue
    }
}

# =========================================================================
# MAIN EXECUTION LOGIC
# =========================================================================

try {
    $InformationPreference = 'Continue'  # Ensure Write-Information is visible

    Write-Information -MessageData '' -InformationAction Continue
    Write-Information -MessageData '=== PSWinOps Build Script ===' -InformationAction Continue
    Write-Information -MessageData "Task: $Task | Version Bump: $BumpVersion" -InformationAction Continue

    Install-BuildDependency

    switch ($Task) {
        'Analyze' {
            Invoke-CodeAnalysis
        }
        'Test' {
            Invoke-UnitTest
        }
        'Build' {
            Invoke-ModuleBuild
        }
        'Package' {
            Invoke-PackageCreation
        }
        'All' {
            Invoke-CodeAnalysis
            Invoke-UnitTest
            Invoke-ModuleBuild
            Invoke-PackageCreation
        }
    }

    Write-Information -MessageData '' -InformationAction Continue
    Write-Information -MessageData '[SUCCESS] Build completed successfully' -InformationAction Continue
    Write-Information -MessageData '' -InformationAction Continue
} catch {
    Write-Error -Message "[$($MyInvocation.MyCommand)] Build failed: $_"
    Write-Information -MessageData '' -InformationAction Continue
    Write-Information -MessageData '[FAIL] Build terminated with errors' -InformationAction Continue
    Write-Information -MessageData '' -InformationAction Continue
    exit 1
}
