# DELIVERY FORMAT

1. **Architecture note** — design choices, trade-offs
2. `Public\<domain>\Verb-Noun.ps1` — complete, PSScriptAnalyzer-clean
3. `PSWinOps.Format.ps1xml` **update** — new `<View>` entry (Table or List)
4. **Updated** `FunctionsToExport` **snippet** — if new public function
5. **Updated type registry snippet** — if new PSTypeName defined
6. `Tests\Public\<domain>\Verb-Noun.Tests.ps1` — full Pester v5 test file
7. **Usage examples** — minimum 3: local, remote single, remote pipeline
8. **Notes** — permissions, Windows features, edge cases
9. **`en-US\about_PSWinOps.help.txt` update** — domain list, function count, type registry (Rule 14)
