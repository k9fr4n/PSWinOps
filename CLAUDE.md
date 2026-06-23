# CLAUDE.md

Guidance for working in this repository. This file is **self-contained** — it is the single
source of truth for PSWinOps coding conventions.

## Project

**PSWinOps** — a PowerShell module of utilities for Windows system administrators,
published to the PowerShell Gallery.

- Module: `PSWinOps` (current version in `PSWinOps.psd1` → `ModuleVersion`)
- Runtime: **PowerShell 5.1+ / Windows only** (`CompatiblePSEditions = Desktop, Core`)
- Author: **Franck SALLET** (k9fr4n)
- Repo: https://github.com/k9fr4n/PSWinOps

The loader (`PSWinOps.psm1`) hard-fails on non-Windows (`PSEdition Core` without `$IsWindows`),
dot-sources every `.ps1` under `Private/` then `Public/`, and registers live AD argument
completers for `Identity` parameters.

> This dev environment is Linux/ARM — PowerShell/Pester may not be installed and the module is
> Windows-only, so it cannot execute here. Author code to spec and rely on CI for verification.

## Repository layout

```
PSWinOps.psd1            Manifest (FunctionsToExport: explicit alphabetical list, no wildcards)
PSWinOps.psm1            Module loader + AD argument completers
PSWinOps.Format.ps1xml   Format views for typed [PSCustomObject] output
build.ps1               Build/test/package pipeline
Public/<domain>/        Exported functions, one file per function
Private/                Internal helpers (Invoke-RemoteOrLocal, Invoke-NativeCommand,
                        Test-IsAdministrator, ConvertFrom-QUserIdleTime, ...)
Tests/                  Pester v5, mirrors Public/ & Private/ paths exactly
en-US/about_PSWinOps.help.txt   Conceptual help topic — keep in sync (Rule 14)
output/PSWinOps/        Build artifact (assembled module), git-ignored
```

Public domains: `activedirectory`, `healthcheck`, `iis`, `network`, `ntp`, `proxy`,
`rdp`, `system`, `utils`, `vss`, `windowsupdate`. New domain → new folder under both
`Public/` and `Tests/Public/`.

## Coding rules (1–14)

**Rule 1 — Sub-folder structure.** One function per file in its domain folder. Test file
mirrors the source path: `Public\<domain>\Foo.ps1` → `Tests\Public\<domain>\Foo.Tests.ps1`;
`Private\Bar.ps1` → `Tests\Private\Bar.Tests.ps1`.

**Rule 2 — Windows-only.** Windows-specific APIs (registry, CIM, WTS, event logs) are allowed.
Always note in `.NOTES`: `Requires: PowerShell 5.1+ / Windows only`. Do NOT add
`#Requires -PSEdition Desktop` unless truly incompatible with PS 7+ on Windows.

**Rule 3 — Noun prefix.** No module prefix; plain singular nouns. `Get-NTPConfiguration` ✓,
`Get-PSWinOpsNTPConfiguration` ✗.

**Rule 4 — Manifest & help updates.** When adding/removing/renaming a public function: update
`FunctionsToExport` in `PSWinOps.psd1` (explicit alphabetical list, no wildcards); update
`FormatsToProcess`/`TypesToProcess` if adding format/type files; update
`en-US\about_PSWinOps.help.txt` (Rule 14); run `.\build.ps1 -Task SyncManifest`.

**Rule 5 — CIM over WMI.** Always `Get-CimInstance` / `Invoke-CimMethod`. Never
`Get-WmiObject` / `Invoke-WmiMethod`.

**Rule 6 — Standard output shape.** All public functions return `[PSCustomObject]` with at
minimum: `ComputerName` `[string]` (`$env:COMPUTERNAME` for local), `Timestamp` `[string]`
(ISO 8601: `Get-Date -Format 'o'`), plus domain-specific fields.
*Exceptions:* pure utilities (`New-RandomPassword`, `ConvertFrom-MisencodedString`) are exempt
from `ComputerName`/`Timestamp` but still return `[PSCustomObject]`; interactive monitors
(`Show-PingMonitor`, `Show-NetworkStatisticMonitor`, `Show-SystemMonitor`) render to the console
and return nothing structured.

**Rule 7 — PSTypeName.** Every `[PSCustomObject]` output includes a `PSTypeName` of the form
`PSWinOps.<ObjectType>` (see the Type Registry below). This drives the format file.

```powershell
[PSCustomObject]@{
    PSTypeName   = 'PSWinOps.ActiveRdpSession'
    ComputerName = $computer
    # ...
}
```

**Rule 8 — Format file.** `PSWinOps.Format.ps1xml` defines default views for typed output. For
each new typed function, add a matching `<View>`: `<TableControl>` for tabular/row data,
`<ListControl>` for wide objects with many properties. `FormatsToProcess` in the manifest must
reference `'PSWinOps.Format.ps1xml'`; `build.ps1` copies `*.Format.ps1xml` to the output dir.

**Rule 9 — Session functions output shape.** Enumerate sessions with `quser.exe` (not
`Win32_LogonSession` — stale LSA records / duplicate auth-package entries). Always parse into
`[PSCustomObject]`, never return raw text. Always include `SessionId` for pipeline chaining:

```powershell
[PSCustomObject]@{
    PSTypeName   = 'PSWinOps.ActiveRdpSession'
    ComputerName = $ComputerName
    SessionId    = $sessionId    # required for pipeline chaining
    UserName     = $userName
    SessionName  = $sessionName
    State        = $state        # 'Active', 'Disconnected', etc.
    LogonTime    = $logonTime    # [datetime]
    Timestamp    = Get-Date -Format 'o'
}
```

**Rule 10 — NTP functions.** Read via `w32tm.exe /query` (don't parse the registry when w32tm
provides the data). Registry writes and `Restart-Service w32tm` require `SupportsShouldProcess`.
Call `w32tm.exe` once in `begin {}`, not inside a loop.

**Rule 11 — ErrorActionPreference scope.** Never set `$ErrorActionPreference` at function scope
(`begin`/`process`/`end`). Use `-ErrorAction Stop` on individual cmdlet calls.

```powershell
# WRONG
begin { $ErrorActionPreference = 'Stop' }
# CORRECT
$service = Get-Service -Name 'w32time' -ErrorAction Stop
```

**Rule 12 — Remote computer support pattern.**

```powershell
[Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string[]]$ComputerName = $env:COMPUTERNAME
```

Iterate in `process {}`; a per-machine failure must NOT stop the remaining machines:

```powershell
process {
    foreach ($targetComputer in $ComputerName) {
        try {
            # logic
        }
        catch {
            Write-Error "[$($MyInvocation.MyCommand)] Failed on '$targetComputer': $_"
        }
    }
}
```

**Rule 13 — Author field.** Always `'Franck SALLET'` in `.NOTES`. Never team or company names.

**Rule 14 — `about_PSWinOps.help.txt` maintenance.** Keep `en-US\about_PSWinOps.help.txt` in
sync at all times. Update when adding/removing/renaming a public function (domain list +
function count), adding a domain (new section in `FUNCTION DOMAINS`), or adding/removing a
PSTypeName (the `PSWINOPS TYPE REGISTRY` section, alphabetical). Formatting: section headers
left-aligned UPPERCASE; content indented 4 spaces; domain sub-headers indented 2 spaces;
function lists indented 6 spaces, one per line, alphabetical; type-registry entries indented
6 spaces, alphabetical.

## Comment-based help (mandatory)

Every public function MUST include all **7 fields** below, one `.PARAMETER` block **per declared
parameter**. Minimum **3 `.EXAMPLE`** blocks: local, remote single-machine, pipeline.

Formatting: `<#` opener indented 4 spaces on its own line; every `.FIELD` tag and every content
line indented **8 spaces**; `.OUTPUTS` content on the *next* line (not on the tag line); one
`.LINK` block per URL (never two URLs under one `.LINK`); `#>` closer indented 4 spaces; blank
line between sections.

```powershell
    <#
    .SYNOPSIS
        One-line summary (no period, max 80 chars).

    .DESCRIPTION
        Full description, at least two sentences.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .EXAMPLE
        Verb-Noun
        Local usage example.

    .EXAMPLE
        Verb-Noun -ComputerName 'SRV01'
        Remote single-machine example.

    .EXAMPLE
        'SRV01', 'SRV02' | Verb-Noun
        Pipeline usage example.

    .OUTPUTS
        PSWinOps.<ObjectType>
        What is returned and when.

    .NOTES
        Author: Franck SALLET
        Version: 1.0.0
        Last Modified: YYYY-MM-DD
        Requires: PowerShell 5.1+ / Windows only
        Requires: <privilege or dependency if applicable>

    .LINK
        https://github.com/k9fr4n/PSWinOps

    .LINK
        https://learn.microsoft.com/en-us/...
    #>
```

## Before coding — clarification checklist

- **Domain** — which sub-folder (create one if new)?
- **Remote support** — local only, or `$ComputerName` pattern (Rule 12)?
- **Credential** — current user or `-Credential`?
- **Error isolation** — continue on per-machine failure (default) or stop?
- **Elevation** — admin required? Document in `.NOTES`; gate with `Test-IsAdministrator` if needed.
- **External binaries** — `w32tm.exe`, `quser.exe`, etc.? Verify exit code; handle missing binary gracefully.
- **PSTypeName** — pick `PSWinOps.<Type>` (see registry) and add a Format `<View>`.
- **Format view** — Table (rows) or List (wide objects)?

## Workflow: add / remove / rename a public function

1. Create `Public/<domain>/Verb-Noun.ps1` — complete, PSScriptAnalyzer-clean, full help.
2. Decide its `PSTypeName` (`PSWinOps.<Type>`) and add a `<View>` to `PSWinOps.Format.ps1xml`
   (Table for rows, List for wide objects).
3. Add the mirrored test `Tests/Public/<domain>/Verb-Noun.Tests.ps1` (full Pester v5).
4. Update `FunctionsToExport` in `PSWinOps.psd1` (explicit, alphabetical) — or run
   `.\build.ps1 -Task SyncManifest`.
5. Update `en-US/about_PSWinOps.help.txt` (domain list, counts, type registry — Rule 14).
6. Provide usage examples (local, remote single, pipeline) and note permissions / Windows
   features / edge cases.

## Build & test (`build.ps1`)

Runs on Windows with PowerShell 5.1+, Pester 5.x, PSScriptAnalyzer.

```powershell
.\build.ps1 -Task Analyze       # PSScriptAnalyzer static analysis
.\build.ps1 -Task Test          # Pester unit tests (Integration tag excluded)
.\build.ps1 -Task SyncManifest  # sync FunctionsToExport with Public/ files
.\build.ps1 -Task Build         # assemble module + update manifest
.\build.ps1 -Task Package       # build distribution ZIP
.\build.ps1                     # All (Analyze, Test, Build, Package), default patch bump
.\build.ps1 -Task Build -BumpVersion Minor   # Major | Minor | Patch
```

Run a single test file directly:

```powershell
Invoke-Pester -Path .\Tests\Public\<domain>\Verb-Noun.Tests.ps1
```

## Testing conventions (Pester v5)

Import the module in `BeforeAll` via the relative path to `PSWinOps.psd1`:

```powershell
# Tests\Public\<domain>\ (3 levels up to root)
BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}
# Tests\Private\ (2 levels up to root)
BeforeAll {
    $script:modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    Import-Module -Name (Join-Path -Path $script:modulePath -ChildPath 'PSWinOps.psd1') -Force
}
```

Call/mock private functions through the module scope:

```powershell
$result = & (Get-Module -Name 'PSWinOps') { Invoke-NativeCommand -Command 'hostname' }
Mock -CommandName 'Invoke-NativeCommand' -MockWith { } -ModuleName 'PSWinOps'
```

**Mandatory mocks by category:** Sessions → `quser.exe`/`query.exe`, `Invoke-Command`,
`logoff.exe`, `mstsc.exe`. NTP → `w32tm.exe`, `Set-ItemProperty`, `Restart-Service`.
AD → `Get-ADUser`, `Get-ADComputer`, `Get-ADGroup`, `Get-ADDomain`, etc. General →
`Get-CimInstance`, `Invoke-CimMethod`, `Test-Connection`.

**Mandatory scenarios per function:** local happy path (`$env:COMPUTERNAME`); explicit remote
machine; pipeline of multiple machine names; per-machine failure (mock throws → function
continues and writes error); parameter validation (empty/null/invalid → error).

**Integration tests:** tag `-Tag 'Integration'`; skip when binaries are absent
(`-Skip:(-not (Test-Path "$env:SystemRoot\System32\qwinsta.exe"))`); CI excludes them.

## Anti-patterns

| Anti-pattern | Correct approach |
|---|---|
| `Get-WmiObject` | `Get-CimInstance` |
| Raw `quser`/`query` text returned | Parse into `[PSCustomObject]` |
| Session output missing `SessionId` | Always include for pipeline chaining |
| Output missing `ComputerName`/`Timestamp` | Always include (except pure utilities & monitors) |
| Output missing `PSTypeName` | Always define `PSWinOps.<Type>` |
| Format view missing for typed output | Add `<View>` in `PSWinOps.Format.ps1xml` |
| Multi-machine loop stops on error | Catch per-machine, write error, continue |
| Function in wrong sub-folder | Match domain; create new folder if needed |
| Wildcard in `FunctionsToExport` | Explicit alphabetical list |
| Test path not mirroring source path | `Tests\Public\<domain>\` / `Tests\Private\` |
| `$ErrorActionPreference` in `begin {}` | `-ErrorAction Stop` per call |
| Author != `'Franck SALLET'` | Fix `.NOTES` Author field |
| `w32tm.exe` called inside a loop | Call once in `begin {}`, parse result |
| External binary without exit-code check | Verify exit code, handle missing binary |
| `.OUTPUTS` content on the tag line | Content on next line, 8-space indent |
| Single `.LINK` with two URLs | Two separate `.LINK` blocks |
| Fewer than 3 `.EXAMPLE` blocks | Minimum 3: local, remote, pipeline |
| Missing a `.PARAMETER` for a declared param | One `.PARAMETER` block per param |
| `about_PSWinOps.help.txt` not updated | Update domain list, counts, type registry |

## Type registry (canonical `PSTypeName` per function — Rule 7)

The authoritative `PSTypeName` for a function is the value in its source `[PSCustomObject]` and
its `<View>` in `PSWinOps.Format.ps1xml`. This table is the reference list; keep it and
`about_PSWinOps.help.txt` aligned with the code.

| Function | PSTypeName | View |
|---|---|---|
| Get-RdpSession | PSWinOps.ActiveRdpSession | Table |
| Get-RdpSessionHistory | PSWinOps.RdpSessionHistory | Table |
| Get-RdpSessionLock | PSWinOps.RdpSessionLock | Table |
| Get-NTPConfiguration | PSWinOps.NtpConfiguration | List |
| Get-NTPPeer | PSWinOps.NtpPeer | Table |
| Get-NTPSyncStatus | PSWinOps.NtpSyncResult | List |
| Sync-NTPTime | PSWinOps.NtpResyncResult | List |
| Get-SystemSummary | PSWinOps.SystemSummary | List |
| Get-ComputerUptime | PSWinOps.ComputerUptime | Table |
| Get-DiskSpace | PSWinOps.DiskSpace | Table |
| Get-EnvironmentVariable | PSWinOps.EnvironmentVariable | Table |
| Get-InstalledSoftware | PSWinOps.InstalledSoftware | Table |
| Get-PageFileConfiguration | PSWinOps.PageFileConfiguration | Table |
| Get-PendingReboot | PSWinOps.PendingReboot | List |
| Get-ScheduledTaskDetail | PSWinOps.ScheduledTaskDetail | Table |
| Get-StartupProgram | PSWinOps.StartupProgram | Table |
| Set-PageFile | PSWinOps.PageFileConfiguration | List |
| Clear-Arp | PSWinOps.ArpEntry | Table |
| Get-ARPTable | PSWinOps.ArpEntry | Table |
| Get-ListeningPort | PSWinOps.ListeningPort | Table |
| Get-NetworkAdapter | PSWinOps.NetworkAdapterInfo | Table |
| Get-NetworkCIDR | PSWinOps.NetworkCIDR | Table |
| Get-NetworkConnection | PSWinOps.NetworkConnection | Table |
| Get-NetworkRoute | PSWinOps.NetworkRoute | Table |
| Get-NetworkStatistic | PSWinOps.NetworkStatistic | Table |
| Get-PublicIPAddress | PSWinOps.PublicIPAddress | List |
| Get-SSLCertificate | PSWinOps.SSLCertificate | List |
| Get-SubnetInfo | PSWinOps.SubnetInfo | List |
| Export-NetworkConfig | PSWinOps.NetworkConfig | List |
| Measure-NetworkLatency | PSWinOps.NetworkLatency | Table |
| Resolve-MACVendor | PSWinOps.MACVendor | Table |
| Test-DNSResolution | PSWinOps.DnsResolution | Table |
| Test-PortConnectivity | PSWinOps.PortConnectivity | Table |
| Test-WinRM | PSWinOps.WinRMTestResult | Table |
| Trace-NetworkRoute | PSWinOps.TraceRouteHop | Table |
| Get-ProxyConfiguration | PSWinOps.ProxyConfiguration | List |
| Test-ProxyConnection | PSWinOps.ProxyTestResult | Table |
| Get-ADComputerDetail | PSWinOps.ADComputerDetail | List |
| Get-ADComputerInventory | PSWinOps.ADComputerInventory | Table |
| Get-ADDomainInfo | PSWinOps.ADDomainInfo | List |
| Get-ADGroupInventory | PSWinOps.ADGroupInventory | Table |
| Get-ADGroupMembership | PSWinOps.ADGroupMember | Table |
| Get-ADLockedAccount | PSWinOps.ADLockedAccount | Table |
| Get-ADNestedGroupMembership | PSWinOps.ADNestedGroupMembership | Table |
| Get-ADPasswordStatus | PSWinOps.ADPasswordStatus | Table |
| Get-ADPrivilegedAccount | PSWinOps.ADPrivilegedAccount | Table |
| Get-ADReplicationStatus | PSWinOps.ADReplicationStatus | Table |
| Get-ADSiteTopology | PSWinOps.ADSiteTopology | Table |
| Get-ADStaleAccount | PSWinOps.ADStaleAccount | Table |
| Get-ADStaleComputer | PSWinOps.ADStaleComputer | Table |
| Get-ADUserDetail | PSWinOps.ADUserDetail | List |
| Get-ADUserGroupInventory | PSWinOps.ADUserGroupInventory | Table |
| Get-ADUserInventory | PSWinOps.ADUserInventory | Table |
| Invoke-ADSecurityAudit | PSWinOps.ADSecurityFinding | Table |
| Search-ADObject | PSWinOps.ADSearchResult | Table |
| Disable-ADUserAccount | PSWinOps.ADAccountDisableResult | Table |
| Enable-ADUserAccount | PSWinOps.ADAccountEnableResult | Table |
| Reset-ADUserPassword | PSWinOps.ADPasswordResetResult | Table |
| Unlock-ADUserAccount | PSWinOps.ADAccountUnlockResult | Table |
| Get-AdDomainControllerHealth | PSWinOps.AdDomainControllerHealth | List |
| Get-ADFSHealth | PSWinOps.ADFSHealth | List |
| Get-CertificateAuthorityHealth | PSWinOps.CertificateAuthorityHealth | List |
| Get-ClusterHealth | PSWinOps.ClusterHealth | List |
| Get-DfsNamespaceHealth | PSWinOps.DfsNamespaceHealth | List |
| Get-DfsReplicationHealth | PSWinOps.DfsReplicationHealth | List |
| Get-DhcpServerHealth | PSWinOps.DhcpServerHealth | List |
| Get-DnsServerHealth | PSWinOps.DnsServerHealth | List |
| Get-ExchangeServerHealth | PSWinOps.ExchangeServerHealth | List |
| Get-FileServerHealth | PSWinOps.FileServerHealth | List |
| Get-HyperVHostHealth | PSWinOps.HyperVHostHealth | List |
| Get-IISHealth | PSWinOps.IISHealth | List |
| Get-PrintServerHealth | PSWinOps.PrintServerHealth | List |
| Get-RDSHealth | PSWinOps.RDSHealth | List |
| Get-ServiceHealth | PSWinOps.ServiceHealth | List |
| Get-WSUSHealth | PSWinOps.WSUSHealth | List |

**Exempted — return a plain string, no PSTypeName:** `New-RandomPassword`,
`ConvertFrom-MisencodedString`.
**Exempted — RDP action functions return `PSWinOps.RdpSessionAction`:** `Connect-RdpSession`,
`Disconnect-RdpSession`, `Remove-RdpSession`.
**Exempted — interactive monitors, no structured return:** `Show-PingMonitor`,
`Show-NetworkStatisticMonitor`, `Show-SystemMonitor`.

> The `iis`, `vss`, and `windowsupdate` domains were added after this registry was first
> compiled — read each function's source `[PSCustomObject]` and its `PSWinOps.Format.ps1xml`
> `<View>` for their authoritative `PSTypeName` values, and add them here when you touch them.

## Optional dependencies

PSWinOps lazy-imports RSAT/role modules on demand (not in `RequiredModules`) so it stays
loadable on hosts that need only a subset. Health-check functions in particular depend on the
corresponding module/role being present (e.g. `ActiveDirectory`, `WebAdministration`/
`IISAdministration`, `Hyper-V`, `FailoverClusters`, `DhcpServer`, `DnsServer`,
`FileServerResourceManager`, Exchange tools, `RemoteDesktop`, `UpdateServices`, `ADFS`,
`PrintManagement`, `DFSN`). See `readme.md` for the full install matrix.

## CI (`.github/workflows/`)

- `ci.yml` — on PR/push to `main`/`develop`: validate manifest + PSGallery metadata
  (`LicenseUri`, `ProjectUri`, `Tags`, `ReleaseNotes`, `LICENSE`), PSScriptAnalyzer lint (fails
  on any error/warning), Pester suites per domain (Pester ≥ 5.7, Integration excluded).
- `publish.yml` — publishes to PowerShell Gallery.
