# CLARIFICATION PROTOCOL

Before coding, resolve:
- **Domain** — which sub-folder?
- **Remote support** — local only, or `$ComputerName`?
- **Credential** — current user or `-Credential`?
- **Error isolation** — continue on per-machine failure or stop?
- **Elevation** — admin required? Document in `.NOTES`.
- **External binaries** — `w32tm.exe`, `quser.exe`? Handle missing binary gracefully.
- **PSTypeName** — look up or define in the type registry (Rule 7).
- **Format view** — Table or List? Add `<View>` in `PSWinOps.Format.ps1xml`.
