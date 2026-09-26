# PSWinOps Module Audit Report

**Date:** 2026-09-26
**Module version audited:** 1.3.0 (`main` @ `4a8a61c`, tag `v1.3.0`)
**Scope:** full-module review against the PowerShell Practice and Style guide,
PSScriptAnalyzer default rules, and Microsoft module-authoring guidelines.

> Environment note: this report was produced on a Linux host without `pwsh`, so
> `PSScriptAnalyzer`, `Test-ModuleManifest` and Pester did **not** execute locally.
> Findings below are the result of static analysis plus the repository's own
> conformance gate (`.claude/scripts/pswinops-audit.sh`, which passed with
> **0 failures / 0 warnings**) and the CI configuration. Dynamic verification is
> delegated to the Windows GitHub Actions pipeline, which enforces zero
> PSScriptAnalyzer warnings and per-domain Pester suites.

## Summary

PSWinOps is a large (146 public / 12 private functions), mature and unusually
well-disciplined module. It has a strong internal conformance gate, a
`PSTypeName` + format-view registry that is fully consistent with the code
(125 `PSTypeName`s referenced in `Public/` map 1:1 to `PSWinOps.Format.ps1xml`
plus the single `PSWinOps.ActionResult` type defined in `Private/`), explicit
manifest lists with no wildcards, and mandatory comment-based help on every
public function. **No Critical or Major issues were found.** The issues below
are documentation/hygiene polish.

### Severity breakdown

| Severity | Count |
|---|---|
| Critical | 0 |
| Major | 0 |
| Minor | 4 |
| Suggestion | 6 |

---

## 1. Structure & Manifest

### 1.1 `coverage.xml` is tracked in git — *Minor*

`coverage.xml` (516 KB) is a CI-generated JaCoCo code-coverage artifact and is
committed to the repository. It is rebuilt on every push (`ci.yml` coverage job)
so the committed copy is immediately stale and bloats the history.

- **File(s):** `coverage.xml`, `.gitignore`
- **Fix:** add a `coverage.xml` entry to `.gitignore` and `git rm --cached
  coverage.xml`. (The existing `*.coverage.xml` pattern does not match the bare
  filename.) **Applied.**

### 1.2 `Get-PSWinOpsFunction.ps1` at the `Public/` root — *Suggestion*

`Public/Get-PSWinOpsFunction.ps1` lives at the root of `Public/` rather than in a
domain folder, which is a deviation from the "one function per file in its domain
folder" rule (Rule 1). This is intentional (the changelog calls it a
"root-level meta-function" and `about_PSWinOps.help.txt` documents that it
"belongs to no domain itself"), and its test mirrors the placement at
`Tests/Public/Get-PSWinOpsFunction.Tests.ps1`, so it is internally consistent.

- **Recommendation:** leave as-is, or document the exception as an explicit rule
  in `CLAUDE.md` alongside Rule 1. **Not applied.**

## 2. Naming Conventions

All verbs are `Get-Verb`-approved (including the often-misflagged `Edit`,
`Show`, `Watch`, `Sync`, `Trace`, and `Uninstall`, which are legitimate
approved verbs). Nouns are singular and PascalCase. No module prefix is used,
matching the documented convention (Rule 3).

### 2.1 `Get-AdDomainControllerHealth` casing — *Minor*

`Get-AdDomainControllerHealth` (and its `PSWinOps.AdDomainControllerHealth`
type) use a lowercase "d" in "Ad", while every other Active Directory function
and type uses uppercase "AD" (`Get-ADComputerDetail`,
`PSWinOps.ADComputerDetail`, `Get-ADFSHealth`, …). This is the only
casing outlier in the codebase.

- **File(s):** `Public/healthcheck/Get-AdDomainControllerHealth.ps1`,
  `PSWinOps.Format.ps1xml`, `PSWinOps.psd1` (`FunctionsToExport`), `PSWinOps.psm1`
  (`$script:AliasMap`), `en-US/about_PSWinOps.help.txt`
- **Fix:** rename to `Get-ADDomainControllerHealth` / `PSWinOps.ADDomainControllerHealth`.
  **This is a breaking change** (public function + PSTypeName rename, alias
  `gadch` unaffected) and is therefore **not applied**; it is flagged here for a
  future MAJOR bump.

### 2.2 Mixed acronym casing in nouns — *Suggestion*

`Get-RdpSession`/`Connect-RdpSession` (lowercase "Rdp") coexist with
`Get-RDSHealth`, `Get-IISHealth` and `Get-ARPTable` (uppercase). PowerShell is
case-insensitive, so this is cosmetic only, but it is inconsistent.

- **Recommendation:** settle on one acronym casing convention for future work.
  Renaming existing functions would be breaking. **Not applied.**

## 3. Manifest Metadata

### 3.1 `CompanyName` — *Suggestion*

`CompanyName = 'kfrlabs'` does not obviously correspond to the repository
organisation (`k9fr4n`) or the author (`Franck SALLET`). Not wrong, just
non-obvious.

- **Recommendation:** confirm the intended value; consider aligning with the
  author or the GitHub org.

The remaining manifest metadata is correct and complete: `ModuleVersion`,
`GUID` (`b8f23fbd-069e-4d11-8e94-e4fc69d71aa5`), `Author`, `Copyright`,
`Description`, `PowerShellVersion = '5.1'`, explicit `FunctionsToExport` /
`AliasesToExport` / `CmdletsToExport = @()`, and complete `PrivateData.PSData`
(`Tags`, `ProjectUri`, `LicenseUri`, `ReleaseNotes`).

## 4. Code Quality & Best Practices

This area is clean. Static analysis confirmed:

- No `Write-Host` anywhere in `Public/`, `Private/` or the loader.
- No `Get-WmiObject` / `Invoke-WmiMethod` (CIM-only, Rule 5).
- No function-scope `$ErrorActionPreference` (Rule 11).
- Every public function declares `[CmdletBinding()]`.
- Every public function has comment-based help including `.SYNOPSIS` and at
  least three `.EXAMPLE` blocks (local, remote, pipeline).
- All typed output carries a `PSTypeName` with a matching format `<View>`.
- The CI lint job runs PSScriptAnalyzer with `-Severity Error, Warning` and
  **fails on any finding**; the repository passes.

### 4.1 `SupportsShouldProcess` — *Suggestion (no action required)*

`Invoke-ADSecurityAudit` and `New-RandomPassword` do not declare
`SupportsShouldProcess`. Both are read-only (the former returns audit findings,
the latter generates a value), so this is correct — noted only for completeness.
All state-changing functions (including `Set-NTPClient`, `Sync-NTPTime`,
`Set-IISCertificateBinding`) correctly declare it.

## 5. Versioning & Release Consistency

- `ModuleVersion` in the manifest (`1.3.0`) matches the latest tag `v1.3.0`
  (which points at `main` @ `4a8a61c`) and the latest GitHub release.
- `CHANGELOG.md` follows a Keep-a-Changelog-style format with an entry for every
  released version and no gaps; each entry cross-checks against the current
  code.

The changes applied in this audit are documentation/repository-hygiene only and
introduce no public API changes, so the version is bumped **PATCH** (`1.3.0`
→ `1.3.1`) in accordance with Semantic Versioning.

## 6. Documentation

### 6.1 Stale domain count in `about_PSWinOps.help.txt` — *Minor*

Line 14–15 reads "organized into **fourteen** functional domains", but there are
**fifteen** (the `disk` domain was split out of `system` in 1.3.0). Line 34
correctly says "fifteen domains".

- **File(s):** `en-US/about_PSWinOps.help.txt:15`
- **Fix:** `fourteen` → `fifteen`. **Applied.**

### 6.2 Domain ordering — *Suggestion*

In the FUNCTION DOMAINS section the domains are not strictly alphabetical
(`windowsupdate` appears before `utils`/`vss`). Rule 14 mandates alphabetical
ordering for function lists and the type registry, but is silent on domain
sub-headings.

- **Recommendation:** order the domain sub-headings alphabetically for
  consistency. **Not applied** (cosmetic; kept to avoid a large diff).

## 7. Tests & CI/CD

- 159 Pester test files mirror the 146 public + 12 private functions exactly
  (`Tests/Public/<domain>/` and `Tests/Private/`).
- CI (`ci.yml`) runs manifest validation, PSGallery-metadata validation,
  PSScriptAnalyzer (zero-tolerance), a per-domain Pester matrix (Integration tag
  excluded), combined result publishing, and a code-coverage gate (70%
  threshold) — all with pinned, non-deprecated action versions
  (`checkout@v4.2.2`, `cache@v4.2.3`, etc.).
- `publish.yml` enforces manifest-version == tag-version before publishing.

### 7.1 `develop` branch referenced but absent — *Suggestion*

`ci.yml` triggers on pushes/PRs to `develop`, but the repository has no
`develop` branch (only `main`, plus the transient `release/*` branches). Harmless
today, but stale.

- **Recommendation:** either create a `develop` branch or drop it from the
  workflow triggers.

## 8. Tooling Config Consistency

### 8.1 `.editorconfig` vs `.gitattributes` — *Suggestion*

`.editorconfig` sets `charset = utf-8-bom` and `end_of_line = crlf`, while
`.gitattributes` normalises `*.ps1`/`*.psm1`/`*.psd1`/`*.ps1xml` to LF in the
repo and the documented policy requires a BOM **only** for files containing
non-ASCII bytes. Editors honouring `.editorconfig` may therefore add a BOM and
CRLF endings, fighting the repository's own normalisation.

- **Recommendation:** align `.editorconfig` with `.gitattributes`/`CLAUDE.md`
  (drop the blanket `charset = utf-8-bom` and `end_of_line = crlf`). **Not
  applied** — it risks editor-driven churn across the working tree and is a
  deliberate trade-off documented in `CLAUDE.md`.

---

## Changes applied in this audit

1. `docs`: corrected the stale domain count in `en-US/about_PSWinOps.help.txt`
   (`fourteen` → `fifteen`).
2. `chore`: added `coverage.xml` to `.gitignore` and stopped tracking the
   committed coverage artifact.
3. `chore(release)`: bumped `ModuleVersion` `1.3.0` → `1.3.1` (PATCH) with a
   matching `CHANGELOG.md` entry and manifest `ReleaseNotes`.
4. Added this report (`AUDIT-REPORT.md`).

## Deferred / requires maintainer decision

- **Breaking change (not applied):** rename `Get-AdDomainControllerHealth` →
  `Get-ADDomainControllerHealth` and its PSTypeName for casing consistency
  (see §2.1). Requires a MAJOR bump.
- Version tagging and PowerShell Gallery publication of `1.3.1` are left to the
  maintainer (the `publish.yml` workflow runs on a `v*` tag and requires the
  manifest version to match).
