# ANTI-PATTERNS (PSWINOPS-SPECIFIC)

| Anti-pattern | Correct approach |
|---|---|
| `Get-WmiObject` | `Get-CimInstance` |
| Raw `quser`/`query` text returned | Parse into `[PSCustomObject]` |
| Session output missing `SessionId` | Always include for pipeline chaining |
| Output missing `ComputerName`/`Timestamp` | Always include (except pure utilities and monitors) |
| Output missing `PSTypeName` | Look up type registry (Rule 7), always define |
| `PSTypeName` not in type registry | Add to registry before coding |
| Format view missing for typed output | Add `<View>` in `PSWinOps.Format.ps1xml` |
| Table vs List not chosen deliberately | Table for rows, List for wide objects |
| Multi-machine loop stops on error | Catch per-machine, write error, continue |
| Function in wrong sub-folder | Match domain; create new folder if needed |
| Wildcard in `FunctionsToExport` | Explicit alphabetical list |
| Test path not mirroring source path | `Tests\Public\<domain>\` / `Tests\Private\` |
| `$ErrorActionPreference` in `begin {}` | Use `-ErrorAction Stop` per call |
| Author != `'Franck SALLET'` | Fix `.NOTES` Author field |
| `w32tm.exe` called inside a loop | Call once in `begin {}`, parse result |
| External binary without exit code check | Always verify exit code, handle missing binary |
| `*.Format.ps1xml` not copied in build | `build.ps1` copies `*.Format.ps1xml` automatically |
| `.OUTPUTS` content on same line as tag | Content on next line, 8-space indent |
| Single `.LINK` with two URLs | Two separate `.LINK` blocks |
| Missing any of the 7 mandatory help fields | All 7 fields always present |
| Only 1 or 2 `.EXAMPLE` blocks | Minimum 3 examples: local, remote, pipeline |
| Missing `.PARAMETER` for a declared param | One `.PARAMETER` block per param, always |
| `about_PSWinOps.help.txt` not updated | Update domain list, counts, and type registry (Rule 14) |
