#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Post-Create Command for DevContainer
# ═══════════════════════════════════════════════════════════════════════════

set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Running Post-Create Commands"
echo "═══════════════════════════════════════════════════════════════════════════"

# ═══════════════════════════════════════════════════════════════════════════
# Create PowerShell Profile
# ═══════════════════════════════════════════════════════════════════════════

echo "Creating PowerShell profile..."

mkdir -p ~/.config/powershell

cat > ~/.config/powershell/Microsoft.PowerShell_profile.ps1 << 'PSEOF'
# ═══════════════════════════════════════════════════════════════════════════
# PowerShell Development Profile
# ═══════════════════════════════════════════════════════════════════════════

# PSReadLine Configuration
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# Aliases
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name la -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String

# Custom Functions
function prompt {
    "PWS [$(Get-Location)] > "
}

function Test-PSScriptAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = '.',

        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )

    Invoke-ScriptAnalyzer -Path $Path -Recurse:$Recurse -Severity Error,Warning
}

function Format-PowerShellCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = Get-Content -Path $Path -Raw
    Invoke-Formatter -ScriptDefinition $content | Set-Content -Path $Path -Encoding UTF8
}

function Clean-TrailingWhitespace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = Get-Content -Path $Path -Raw -Encoding UTF8
    $lines = $content -split "`r?`n"
    $cleaned = $lines | ForEach-Object { $_.TrimEnd() }
    $result = $cleaned -join "`r`n"

    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($Path, $result, $utf8Bom)

    Write-Host "✅ Cleaned: $Path" -ForegroundColor Green
}

# Welcome Message
Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "═══════════════════════════════════════════════════════" -InformationAction Continue
Write-Information -MessageData "  PowerShell Development Environment" -InformationAction Continue
Write-Information -MessageData "═══════════════════════════════════════════════════════" -InformationAction Continue
Write-Information -MessageData "PowerShell Version: $($PSVersionTable.PSVersion)" -InformationAction Continue
Write-Information -MessageData "PSScriptAnalyzer: $(Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -ExpandProperty Version -First 1)" -InformationAction Continue
Write-Information -MessageData "Pester: $(Get-Module -ListAvailable Pester | Select-Object -ExpandProperty Version -First 1)" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue
Write-Information -MessageData "Quick Commands:" -InformationAction Continue
Write-Information -MessageData "  Test-PSScriptAnalyzer [-Path <path>] [-Recurse]" -InformationAction Continue
Write-Information -MessageData "  Format-PowerShellCode -Path <file.ps1>" -InformationAction Continue
Write-Information -MessageData "  Clean-TrailingWhitespace -Path <file.ps1>" -InformationAction Continue
Write-Information -MessageData "  Invoke-Pester -Path <test-path>" -InformationAction Continue
Write-Information -MessageData "═══════════════════════════════════════════════════════" -InformationAction Continue
Write-Information -MessageData "" -InformationAction Continue
PSEOF

echo "✅ PowerShell profile created"

# ═══════════════════════════════════════════════════════════════════════════
# Create .vscode directory if it doesn't exist
# ═══════════════════════════════════════════════════════════════════════════

mkdir -p .vscode

# ═══════════════════════════════════════════════════════════════════════════
# Create PSScriptAnalyzer Settings File
# ═══════════════════════════════════════════════════════════════════════════

cat > .vscode/PSScriptAnalyzerSettings.psd1 << 'EOF'
@{
    Severity = @('Error', 'Warning')

    IncludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidGlobalFunctions',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseProcessBlockForPipelineCommand',
        'PSUseBOMForUnicodeEncodedFile',
        'PSAvoidTrailingWhitespace',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidUsingPositionalParameters',
        'PSUseSingularNouns',
        'PSReviewUnusedParameter',
        'PSUseOutputTypeCorrectly',
        'PSAvoidUsingCmdletAliases',
        'PSUseApprovedVerbs',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSUsePSCredentialType',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUserNameAndPasswordParams',
        'PSUseCmdletCorrectly',
        'PSAvoidUsingWMICmdlet'
    )

    Rules = @{
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator = $true
            CheckParameter = $true
        }

        PSAlignAssignmentStatement = @{
            Enable = $true
            CheckHashtable = $true
        }

        PSUseCorrectCasing = @{
            Enable = $true
        }
    }
}
EOF

echo "✅ Created PSScriptAnalyzer settings file"

# ═══════════════════════════════════════════════════════════════════════════
# Create .editorconfig
# ═══════════════════════════════════════════════════════════════════════════

cat > .editorconfig << 'EOF'
# EditorConfig for PowerShell Development
# https://editorconfig.org

root = true

[*]
charset = utf-8-bom
end_of_line = crlf
insert_final_newline = true
trim_trailing_whitespace = true

[*.{ps1,psm1,psd1}]
indent_style = space
indent_size = 4

[*.{yml,yaml}]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false
EOF

echo "✅ Created .editorconfig"

# ═══════════════════════════════════════════════════════════════════════════
# Create .gitignore for PowerShell projects
# ═══════════════════════════════════════════════════════════════════════════

if [ ! -f .gitignore ]; then
    cat > .gitignore << 'EOF'
# PowerShell
*.ps1.bak
*.psm1.bak
*.psd1.bak

# Test Results
TestResults/
*.trx
*.coverage.xml

# Build Output
bin/
obj/
out/
publish/

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Secrets
*.pfx
*.p12
secrets.json
EOF
    echo "✅ Created .gitignore"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Verify PowerShell Modules
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "Verifying PowerShell modules..."
pwsh -NoProfile -Command "Get-InstalledModule | Format-Table -AutoSize"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✅ DevContainer Setup Complete!"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "Available commands:"
echo "  - Test-PSScriptAnalyzer      : Run PSScriptAnalyzer on your code"
echo "  - Invoke-Pester              : Run Pester tests"
echo "  - Format-PowerShellCode      : Format PowerShell files"
echo "  - Clean-TrailingWhitespace   : Remove trailing whitespace from files"
echo ""
