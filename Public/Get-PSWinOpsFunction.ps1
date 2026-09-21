#Requires -Version 5.1

function Get-PSWinOpsFunction {
    <#
    .SYNOPSIS
        Lists the module's public functions by domain with their synopsis

    .DESCRIPTION
        Enumerates every exported function of the PSWinOps module and returns one
        structured object per function with its name, the thematic domain it belongs
        to, its short alias, and its one-line synopsis taken from the comment-based
        help. The listing is sorted by domain then name, so it reads as a grouped
        index of the module's surface and doubles as a discovery aid when the exact
        command name is not known.

        The domain is resolved from the function's source file under Public\<domain>\.
        In the published (flattened) module build, the domain is recovered from the
        per-function markers that build.ps1 writes into the assembled PSM1.

        This meta-function itself lives at the root of Public\ and belongs to no
        domain, so it is listed with an empty Domain.

    .PARAMETER Domain
        One or more domain (thematic folder) names to restrict the listing to, e.g.
        'ntp' or 'network'. Accepts pipeline input by value and by property name.

    .EXAMPLE
        Get-PSWinOpsFunction

        Lists every public function grouped by domain, each with its alias and synopsis.

    .EXAMPLE
        Get-PSWinOpsFunction -Domain 'ntp'

        Lists only the NTP-domain functions.

    .EXAMPLE
        'ntp', 'network' | Get-PSWinOpsFunction

        Lists the NTP and network functions via pipeline input.

    .OUTPUTS
        PSWinOps.ModuleFunction
        One object per public function, with Name, Domain, Alias and Synopsis.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: 2026-09-21
        Requires: PowerShell 5.1+ / Windows only

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-command
    #>
    [CmdletBinding()]
    [OutputType('PSWinOps.ModuleFunction')]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('activedirectory', 'certificate', 'disk', 'eventlog', 'healthcheck', 'iis',
            'network', 'ntp', 'proxy', 'rdp', 'security', 'system', 'utils', 'vss', 'windowsupdate')]
        [string[]]$Domain
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand)] Enumerating module functions"

        # Reverse the module's short-alias map so each function name resolves to its alias.
        $aliasByFunction = @{}
        foreach ($entry in $script:AliasMap.GetEnumerator()) {
            $aliasByFunction[$entry.Value] = $entry.Key
        }

        $moduleName = $MyInvocation.MyCommand.Module.Name

        # Enumerate the module's exported functions once, sorted by name.
        $commands = @(Get-Command -Module $moduleName -CommandType Function -ErrorAction Stop | Sort-Object -Property Name)

        # Resolve each function to its domain (thematic folder). In the source layout the
        # defining file lives under Public\<domain>\, so the domain is the folder name. The
        # published module is a single flattened PSM1 with no Public\ tree, so fall back to
        # the '# --- Public: <domain>/<name>.ps1 ---' markers that build.ps1 writes.
        $domainByFunction = @{}
        $flatModuleFile = $null
        foreach ($cmd in $commands) {
            $file = $null
            if ($null -ne $cmd.ScriptBlock) {
                $file = $cmd.ScriptBlock.File
            }
            $domain = $null
            if ($file -and $file -match '[\\/]Public[\\/]([^\\/]+)[\\/]') {
                $domain = $Matches[1]
            } elseif ($file -and $file -like '*.psm1') {
                $flatModuleFile = $file
            }
            $domainByFunction[$cmd.Name] = $domain
        }

        if ($flatModuleFile) {
            $flatContent = Get-Content -Path $flatModuleFile -Raw -ErrorAction SilentlyContinue
            if ($flatContent) {
                foreach ($marker in [regex]::Matches($flatContent, '(?m)^# --- Public: ([A-Za-z0-9-]+)[/\\]([A-Za-z0-9-]+)\.ps1 ---[ \t]*$')) {
                    $domainByFunction[$marker.Groups[2].Value] = $marker.Groups[1].Value
                }
            }
        }

        $results = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($cmd in $commands) {
            $functionDomain = $domainByFunction[$cmd.Name]
            if ($PSBoundParameters.ContainsKey('Domain') -and ($functionDomain -notin $Domain)) {
                continue
            }

            $synopsis = ''
            $help = Get-Help -Name $cmd.Name -ErrorAction SilentlyContinue
            if ($null -ne $help) {
                $synopsis = (($help.Synopsis -join ' ') -replace '\s+', ' ').Trim()
            }

            $null = $results.Add([PSCustomObject]@{
                PSTypeName = 'PSWinOps.ModuleFunction'
                Name       = $cmd.Name
                Domain     = $functionDomain
                Alias      = if ($aliasByFunction.ContainsKey($cmd.Name)) { $aliasByFunction[$cmd.Name] } else { '' }
                Synopsis   = $synopsis
            })
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand)] Completed function listing"
        $results | Sort-Object -Property Domain, Name
    }
}
