# COMMENT-BASED HELP — MANDATORY FORMAT (PSWINOPS)

Every public function MUST include all seven fields below, indented exactly as shown. One `.PARAMETER` block is required **for each declared parameter** — omitting any parameter is a violation.

### Formatting rules
- The `<#` opener sits on its own line, indented **4 spaces**
- Every `.FIELD` tag is indented **8 spaces** (`.SYNOPSIS`)
- Every content line under a tag is indented **8 spaces**
- `.OUTPUTS` content is on the **next line**, indented 8 spaces — NOT on the same line as the tag
- `.LINK` is repeated once per URL — do NOT put multiple URLs under a single `.LINK`
- The `#>` closer sits on its own line, indented **4 spaces**
- A blank line separates each section for readability

### Mandatory `.NOTES` format
```
        .NOTES
            Author: Franck SALLET
            Version: 1.0.0
            Last Modified: YYYY-MM-DD
            Requires: PowerShell 5.1+ / Windows only
            Requires: <privilege or dependency if applicable>
```

### Mandatory `.LINK` format (one block per URL)
```
        .LINK
            https://github.com/k9fr4n/PSWinOps
        .LINK
            https://learn.microsoft.com/en-us/...
```

### Canonical help block template (PSWinOps)
```
    <#
    .SYNOPSIS
        One-line summary of what the function does (no period, max 80 chars).

    .DESCRIPTION
        Full description. Must contain at least two sentences.
        Each continuation line is indented 8 spaces.

    .PARAMETER ComputerName
        One or more computer names to target. Defaults to the local computer.
        Accepts pipeline input by value and by property name.

    .EXAMPLE
        Verb-Noun
        Description of the local usage example.

    .EXAMPLE
        Verb-Noun -ComputerName 'SRV01'
        Description of the remote single-machine example.

    .EXAMPLE
        'SRV01', 'SRV02' | Verb-Noun
        Description of the pipeline usage example.

    .OUTPUTS
        PSWinOps.<ObjectType>
        Description of what is returned and when.

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

### Comment-based help anti-patterns

| Anti-pattern | Correct approach |
|---|---|
| `.OUTPUTS` content on same line as tag | Content on next line, 8-space indent |
| Single `.LINK` with two URLs | Two separate `.LINK` blocks |
| 4-space indent for content lines | 8-space indent for all content |
| Missing any of the 7 mandatory fields | All 7 fields always present |
| `.NOTES` without Author / Version / Last Modified / Requires | All 4 base fields always present |
| Only 1 or 2 `.EXAMPLE` blocks | Minimum 3 examples: local, remote, pipeline |
| Author != `'Franck SALLET'` | Fix `.NOTES` Author field |
