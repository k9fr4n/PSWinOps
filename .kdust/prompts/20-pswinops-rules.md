# PSWINOPS RULES

### Rule 1 — Sub-folder structure
Place each function in the matching domain folder. New domain -> new folder.
Test file must mirror source path:
- `Public\<domain>\Foo.ps1` → `Tests\Public\<domain>\Foo.Tests.ps1`
- `Private\Bar.ps1` → `Tests\Private\Bar.Tests.ps1`

| Domain | Folder |
|--------|--------|
| Active Directory | `Public\activedirectory\` |
| Health checks | `Public\healthcheck\` |
| Network | `Public\network\` |
| NTP / time | `Public\ntp\` |
| Proxy | `Public\proxy\` |
| RDP / sessions | `Public\rdp\` |
| System info | `Public\system\` |
| String/misc utils | `Public\utils\` |
| New domain | `Public\<domain>\` |

### Rule 2 — Windows-only
Windows-specific APIs (registry, WMI/CIM, WTS, event logs) are allowed.
Always note in `.NOTES`:
```
Requires: PowerShell 5.1+ / Windows only
```
Do NOT add `#Requires -PSEdition Desktop` unless truly incompatible with PS 7+ on Windows.

### Rule 3 — Noun prefix
No module prefix. Plain singular nouns only.
```
# CORRECT
Get-NTPConfiguration
# WRONG
Get-PSWinOpsNTPConfiguration
```

### Rule 4 — Manifest and help-file updates
When adding, removing, or renaming a public function:
- Update `FunctionsToExport` in `PSWinOps.psd1` — explicit alphabetical list, no wildcards.
- If adding format/type files, update `FormatsToProcess` / `TypesToProcess` accordingly.
- Update `en-US\about_PSWinOps.help.txt` — see **Rule 14** for details.
- Run `.\build.ps1 -Task SyncManifest` to keep the manifest in sync.

### Rule 5 — CIM over WMI
Always `Get-CimInstance` / `Invoke-CimMethod`. Never `Get-WmiObject` / `Invoke-WmiMethod`.

### Rule 6 — Standard output shape
All public functions return `[PSCustomObject]` with at minimum:
- `ComputerName` `[string]` — `$env:COMPUTERNAME` for local
- `Timestamp` `[string]` — ISO 8601: `Get-Date -Format 'o'`
- + domain fields (function-specific)

**Exception:** pure utility functions (`New-RandomPassword`, `ConvertFrom-MisencodedString`) are exempt from `ComputerName`/`Timestamp` but must still return `[PSCustomObject]`.
**Exception:** interactive monitor functions (`Show-PingMonitor`, `Show-NetworkStatisticMonitor`, `Show-SystemMonitor`) render directly to the console and do not return structured output.

### Rule 7 — PSTypeName on output objects
All `[PSCustomObject]` outputs must include a `PSTypeName` matching the format `PSWinOps.<ObjectType>`.
```
[PSCustomObject]@{
    PSTypeName   = 'PSWinOps.ActiveRdpSession'
    ComputerName = $computer
    # ...
}
```
This enables the format file (`PSWinOps.Format.ps1xml`) to apply custom table views.
The canonical PSTypeName-per-function registry lives in `30-type-registry.md`.
When adding a new function, **add its PSTypeName to the registry before coding**.

### Rule 8 — Format file
`PSWinOps.Format.ps1xml` defines default table and list views for typed output objects.
When adding a new public function that returns a typed `[PSCustomObject]`:
- Add a matching `<View>` entry in `PSWinOps.Format.ps1xml`.
- Use `<TableControl>` for tabular data (sessions, peers, uptime).
- Use `<ListControl>` for wide objects with many properties (NTP config, system summary).
- `FormatsToProcess` in `PSWinOps.psd1` must reference `'PSWinOps.Format.ps1xml'`.
- `build.ps1` automatically copies `*.Format.ps1xml` to the output directory.

### Rule 9 — Session functions output shape
```
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
Use `quser.exe` for enumeration (not `Win32_LogonSession` — stale LSA records, duplicate auth-package entries). Always parse into `[PSCustomObject]` — never return raw text.

### Rule 10 — NTP functions
- Read via `w32tm.exe /query` — do not parse registry directly when w32tm provides the data.
- Registry writes and `Restart-Service w32tm` require `SupportsShouldProcess`.
- Do NOT set `$ErrorActionPreference = 'Stop'` in `begin {}` — use `-ErrorAction Stop` on individual calls to avoid polluting the caller's scope.

### Rule 11 — ErrorActionPreference scope
Never set `$ErrorActionPreference` at function scope (`begin`/`process`/`end` blocks). Always use `-ErrorAction Stop` on individual cmdlet calls instead.
```
# WRONG
begin { $ErrorActionPreference = 'Stop' }
# CORRECT
$service = Get-Service -Name 'w32time' -ErrorAction Stop
```

### Rule 12 — Remote computer support pattern
```
[Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
[ValidateNotNullOrEmpty()]
[string[]]$ComputerName = $env:COMPUTERNAME
```
Iterate in `process {}`. Per-machine failure must NOT stop remaining machines:
```
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

### Rule 13 — Author field
Always use `'Franck SALLET'` in `.NOTES` Author field. Never use team or company names.

### Rule 14 — about_PSWinOps.help.txt maintenance
The file `en-US\about_PSWinOps.help.txt` is the module's conceptual help topic (`Get-Help about_PSWinOps`). It must stay in sync with the module at all times.

**When to update:**
- Adding a new public function → add to the matching domain list, update function count.
- Removing a public function → remove from the domain list, update function count.
- Renaming a public function → update the entry in the domain list.
- Adding a new domain folder → add a new domain section in `FUNCTION DOMAINS`.
- Adding a new PSTypeName → add to the `PSWINOPS TYPE REGISTRY` section (alphabetical order).
- Removing or renaming a PSTypeName → update the registry accordingly.

**Sections to keep in sync:**

| Section | What to update |
|---|---|
| `SHORT DESCRIPTION` | Mention new domains if significant |
| `LONG DESCRIPTION` | Update domain count ("eight functional domains") |
| `FUNCTION DOMAINS` | Domain name, function count, function list (alphabetical) |
| `OVERALLHEALTH VALUES` | Update health check function count if changed |
| `PSWINOPS TYPE REGISTRY` | PSTypeName list (alphabetical), total count |
| `SEE ALSO` | Add `Get-Help` entries for major new functions |
| `KEYWORDS` | Add keywords for new domains |

**Formatting rules for about_PSWinOps.help.txt:**
- Section headers (`TOPIC`, `FUNCTION DOMAINS`, etc.) are left-aligned, UPPERCASE.
- Content under sections is indented 4 spaces.
- Sub-section headers (domain names) are indented 2 spaces.
- Function lists within domains are indented 6 spaces, one per line, alphabetical.
- PSTypeName entries in the registry are indented 6 spaces, one per line, alphabetical.
