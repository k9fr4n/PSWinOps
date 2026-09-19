#!/usr/bin/env bash
# pswinops-audit.sh — the Linux-runnable conformance gate for PSWinOps changes.
#
# This host has no pwsh, so Test-ModuleManifest / PSScriptAnalyzer / Pester
# cannot run here; the Windows GitHub Actions CI is the dynamic gate. What CAN be
# checked locally is structure, encoding and convention conformance — that is
# this script. Run it before every push so the CI is not used as a linter.
#
# Usage: pswinops-audit.sh [base-ref]        (default base-ref: origin/main)
# Exit:  0 = all checks pass, 1 = at least one FAIL. Every finding is printed as
#        "FAIL: <check> — <detail>" so an agent can act on it without parsing.
set -uo pipefail

BASE="${1:-origin/main}"
cd "$(git rev-parse --show-toplevel)"

fails=0
warns=0
ok()   { printf '  ok   %s\n' "$1"; }
warn() { printf 'WARN: %s — %s\n' "$1" "$2"; warns=$((warns+1)); }
fail() { printf 'FAIL: %s — %s\n' "$1" "$2"; fails=$((fails+1)); }

git rev-parse --verify --quiet "$BASE" >/dev/null || { echo "FAIL: base-ref — '$BASE' does not exist (git fetch first)"; exit 1; }

CHANGED=$(git diff --name-only --diff-filter=ACMR "$BASE"...HEAD)
DIFF=$(git diff "$BASE"...HEAD -- '*.ps1' '*.psm1')

echo "== PSWinOps conformance audit (base: $BASE) =="
[[ -z "$CHANGED" ]] && echo "  (no changes vs $BASE)"

# ── 1. Encoding ──────────────────────────────────────────────────────────────
# A UTF-8 BOM is REQUIRED only when the file contains non-ASCII bytes: PowerShell
# 5.1 reads a BOM-less file as ANSI/Windows-1252 and would mangle those bytes. A
# pure-ASCII file is byte-identical either way, and 20 of the 140 files on main
# ship BOM-less — so a blanket BOM requirement would be stricter than the repo's
# own invariant and would fail legitimate PRs. Missing BOM on ASCII is a WARN.
#
# Line endings are NOT checked at all: .gitattributes marks *.ps1 as `text`, so
# git normalises to LF in the repo and checks out native endings, and CI sets
# core.autocrlf=true for PS 5.1. Forcing CR bytes into the working tree here
# would fight that configuration rather than help it.
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  case "$f" in
    *.ps1|*.psm1|*.psd1|*.ps1xml) ;;
    *) continue ;;
  esac
  has_bom=0
  head -c 3 "$f" | od -An -tx1 | tr -d ' \n' | grep -q '^efbbbf' && has_bom=1
  non_ascii=0
  LC_ALL=C grep -qP '[\x80-\xFF]' "$f" && non_ascii=1
  if (( has_bom )); then
    ok "BOM present: $f"
  elif (( non_ascii )); then
    fail "utf8-bom" "$f contains non-ASCII bytes and has no UTF-8 BOM; PowerShell 5.1 will read it as ANSI. Fix: printf '\\xEF\\xBB\\xBF' | cat - \"$f\" > t && mv t \"$f\""
  else
    warn "utf8-bom" "$f has no UTF-8 BOM (pure ASCII, so harmless; add one to match the majority of the module)"
  fi
done <<<"$CHANGED"

# ── 2. Forbidden constructs in added lines (CLAUDE.md anti-patterns) ──────────
check_added() { # <regex> <check-name> <detail>
  local hits
  hits=$(grep -nE "^\+" <<<"$DIFF" | grep -vE '^\+\+\+' | grep -E "$1" || true)
  if [[ -n "$hits" ]]; then
    fail "$2" "$3"
    sed -n '1,5p' <<<"$hits" | sed 's/^/        /'
  else
    ok "no $2"
  fi
}
if [[ -n "$DIFF" ]]; then
  check_added 'Write-Host'                              'write-host'      'Write-Host added; use Write-Information -InformationAction Continue'
  check_added '(Get-WmiObject|Invoke-WmiMethod)'        'wmi'             'WMI cmdlet added; CLAUDE.md Rule 5 requires Get-CimInstance/Invoke-CimMethod'
  check_added '\$ErrorActionPreference[[:space:]]*='    'eap-assignment'  '$ErrorActionPreference assigned; CLAUDE.md Rule 11 requires -ErrorAction Stop per call'
  check_added '#Requires -PSEdition'                    'requires-psedition' '#Requires -PSEdition added; CLAUDE.md Rule 2 forbids it unless truly PS7-incompatible'
else
  ok "no PowerShell source changes to scan"
fi

# ── 3. FunctionsToExport: alphabetical, no duplicates, matches Public/ ────────
psd1_array() { # <field>
  awk -v field="$1" '
    $0 ~ field "[[:space:]]*=[[:space:]]*@\\(" {f=1}
    f {print}
    f && /\)/ {exit}' PSWinOps.psd1 | grep -oE "'[^']+'" | tr -d "'"
}
EXPORTED=$(psd1_array FunctionsToExport)
if [[ -z "$EXPORTED" ]]; then
  fail "functions-to-export" "could not parse FunctionsToExport from PSWinOps.psd1"
else
  # Case-insensitive: the manifest's own order has Get-AdDomainControllerHealth
  # before Get-ADDomainInfo, i.e. human-alphabetical, not byte order.
  if sort -c -f <<<"$EXPORTED" 2>/dev/null; then ok "FunctionsToExport alphabetically sorted"
  else
    fail "functions-to-export-sort" "FunctionsToExport is not alphabetically sorted, case-insensitively (CLAUDE.md Rule 4): $(sort -c -f <<<"$EXPORTED" 2>&1 | head -1)"
  fi

  dupes=$(sort <<<"$EXPORTED" | uniq -d)
  [[ -z "$dupes" ]] && ok "FunctionsToExport has no duplicates" \
    || fail "functions-to-export-dupes" "duplicated entries: $(tr '\n' ' ' <<<"$dupes")"

  ON_DISK=$(find Public -name '*.ps1' -printf '%f\n' 2>/dev/null | sed 's/\.ps1$//' | sort)
  missing=$(comm -13 <(sort <<<"$EXPORTED") <(sort <<<"$ON_DISK"))
  extra=$(comm -23 <(sort <<<"$EXPORTED") <(sort <<<"$ON_DISK"))
  [[ -z "$missing" ]] && ok "every Public/ function is exported" \
    || fail "functions-to-export-missing" "on disk but not exported: $(tr '\n' ' ' <<<"$missing") (run build.ps1 -Task SyncManifest on Windows, or patch by hand)"
  [[ -z "$extra" ]] && ok "no exported function lacks a file" \
    || fail "functions-to-export-extra" "exported but no Public/ file: $(tr '\n' ' ' <<<"$extra")"

  grep -qE "FunctionsToExport[[:space:]]*=[[:space:]]*'?\*" PSWinOps.psd1 \
    && fail "functions-to-export-wildcard" "wildcard in FunctionsToExport (CLAUDE.md Rule 4)" \
    || ok "no wildcard in FunctionsToExport"
fi

# ── 4. Short aliases: AliasMap / AliasesToExport / FunctionsToExport (Rule 15) ─
ALIAS_LINES=$(awk '/^\$script:AliasMap = @\{/,/^\}/' PSWinOps.psm1 \
              | grep -E "^[[:space:]]*'[^']+'[[:space:]]*=[[:space:]]*'[^']+'" || true)
ALIAS_MAP=$(sed -E "s/^[[:space:]]*'([^']+)'[[:space:]]*=[[:space:]]*'([^']+)'$/\1 \2/" <<<"$ALIAS_LINES")
ALIAS_KEYS=$(awk '{print $1}' <<<"$ALIAS_MAP")
ALIAS_VALUES=$(awk '{print $2}' <<<"$ALIAS_MAP")
MANIFEST_ALIASES=$(psd1_array AliasesToExport)

if [[ -z "$ALIAS_MAP" ]]; then
  fail "aliasmap-parse" "could not parse \$script:AliasMap entries from PSWinOps.psm1 (CLAUDE.md Rule 15)"
else
  if [[ -n "$EXPORTED" ]]; then
    # 1) every exported function has an AliasMap value
    missing_aliases=$(comm -23 <(sort -u <<<"$EXPORTED") <(sort -u <<<"$ALIAS_VALUES"))
    [[ -z "$missing_aliases" ]] && ok "every exported function has an AliasMap entry" \
      || fail "aliasmap-missing" "exported functions missing from \$script:AliasMap: $(tr '\n' ' ' <<<"$missing_aliases") (CLAUDE.md Rule 15)"

    # 2) every AliasMap value is an exported function
    orphan_aliases=$(comm -13 <(sort -u <<<"$EXPORTED") <(sort -u <<<"$ALIAS_VALUES"))
    [[ -z "$orphan_aliases" ]] && ok "every AliasMap value is exported" \
      || fail "aliasmap-orphan" "AliasMap values that are not exported functions: $(tr '\n' ' ' <<<"$orphan_aliases") (CLAUDE.md Rule 15)"
  else
    fail "aliasmap-missing" "FunctionsToExport could not be parsed; AliasMap value coverage could not be verified"
  fi

  # 3) no duplicate alias keys
  alias_dupe_keys=$(sort <<<"$ALIAS_KEYS" | uniq -d)
  [[ -z "$alias_dupe_keys" ]] && ok "AliasMap has no duplicate keys" \
    || fail "aliasmap-dupe-key" "duplicated alias keys: $(tr '\n' ' ' <<<"$alias_dupe_keys") (CLAUDE.md Rule 15)"

  # 4) no two alias keys mapping to the same function
  alias_dupe_values=$(sort <<<"$ALIAS_VALUES" | uniq -d)
  [[ -z "$alias_dupe_values" ]] && ok "no two alias keys map to the same function" \
    || fail "aliasmap-dupe-value" "functions with more than one alias: $(tr '\n' ' ' <<<"$alias_dupe_values") (CLAUDE.md Rule 15)"

  # 5) AliasMap keys and AliasesToExport are a symmetric match
  aliases_missing_export=$(comm -23 <(sort -u <<<"$ALIAS_KEYS") <(sort -u <<<"$MANIFEST_ALIASES"))
  aliases_extra_export=$(comm -23 <(sort -u <<<"$MANIFEST_ALIASES") <(sort -u <<<"$ALIAS_KEYS"))
  [[ -z "$aliases_missing_export" ]] && ok "every AliasMap key is in AliasesToExport" \
    || fail "aliases-to-export-missing" "AliasMap keys missing from AliasesToExport: $(tr '\n' ' ' <<<"$aliases_missing_export") (CLAUDE.md Rule 15)"
  [[ -z "$aliases_extra_export" ]] && ok "every AliasesToExport entry has an AliasMap key" \
    || fail "aliases-to-export-extra" "AliasesToExport entries with no AliasMap key: $(tr '\n' ' ' <<<"$aliases_extra_export") (CLAUDE.md Rule 15)"

  # 6) AliasesToExport alphabetically sorted (case-insensitive, like FunctionsToExport)
  if sort -c -f <<<"$MANIFEST_ALIASES" 2>/dev/null; then ok "AliasesToExport alphabetically sorted"
  else
    warn "aliases-to-export-sort" "AliasesToExport is not alphabetically sorted, case-insensitively (CLAUDE.md Rule 15): $(sort -c -f <<<"$MANIFEST_ALIASES" 2>&1 | head -1)"
  fi
fi

# ── 5. Format file: valid XML, and a <View> for every new PSTypeName ─────────
if yq -p=xml -o=xml '.' PSWinOps.Format.ps1xml >/dev/null 2>&1; then
  ok "PSWinOps.Format.ps1xml is well-formed XML"
else
  fail "format-xml" "PSWinOps.Format.ps1xml is not well-formed XML"
fi

NEW_TYPES=$(grep -hoE "PSTypeName[[:space:]]*=[[:space:]]*'PSWinOps\.[A-Za-z0-9]+'" <<<"$DIFF" \
            | grep -oE "PSWinOps\.[A-Za-z0-9]+" | sort -u)
if [[ -n "$NEW_TYPES" ]]; then
  while IFS= read -r t; do
    grep -q "<TypeName>$t</TypeName>" PSWinOps.Format.ps1xml \
      && ok "Format <View> exists for $t" \
      || fail "format-view" "no <View> selected by <TypeName>$t</TypeName> in PSWinOps.Format.ps1xml (CLAUDE.md Rule 8)"
    grep -q "$t" en-US/about_PSWinOps.help.txt \
      && ok "type registry lists $t" \
      || fail "help-type-registry" "$t missing from en-US/about_PSWinOps.help.txt type registry (CLAUDE.md Rule 14)"
  done <<<"$NEW_TYPES"
else
  ok "no new PSTypeName introduced"
fi

# ── 6. Test mirroring: a touched Public/ function has a mirrored test ────────
while IFS= read -r f; do
  [[ "$f" == Public/*/*.ps1 ]] || continue
  t="Tests/${f%.ps1}.Tests.ps1"
  [[ -f "$t" ]] && ok "test mirrored: $t" \
    || fail "test-mirror" "missing $t for $f (CLAUDE.md Rule 1)"
done <<<"$CHANGED"

# ── 7. Comment-based help completeness on touched public functions ──────────
while IFS= read -r f; do
  [[ "$f" == Public/*/*.ps1 && -f "$f" ]] || continue
  for tag in .SYNOPSIS .DESCRIPTION .OUTPUTS .NOTES .LINK; do
    grep -q -- "$tag" "$f" || fail "help-$tag" "$f has no $tag block"
  done
  ex=$(grep -c -- '\.EXAMPLE' "$f")
  (( ex >= 3 )) && ok "$f has $ex .EXAMPLE blocks" \
    || fail "help-examples" "$f has $ex .EXAMPLE block(s); CLAUDE.md requires at least 3 (local, remote, pipeline)"
  grep -q "Author: Franck SALLET" "$f" && ok "$f author field correct" \
    || fail "help-author" "$f .NOTES Author must be 'Franck SALLET' (CLAUDE.md Rule 13)"
done <<<"$CHANGED"

# ── 8. New domain ⇒ CI matrix entry exists ──────────────────────────────────
while IFS= read -r f; do
  [[ "$f" == Public/*/*.ps1 ]] || continue
  d=$(basename "$(dirname "$f")")
  grep -q "\"Public/$d\"" .github/workflows/ci.yml \
    && ok "ci.yml matrix covers Public/$d" \
    || fail "ci-matrix" "Public/$d is not in the ci.yml test matrix — its tests would never run"
done <<<"$CHANGED"
yq '.' .github/workflows/ci.yml >/dev/null 2>&1 && ok "ci.yml is valid YAML" || fail "ci-yaml" "ci.yml is not valid YAML"

echo
if (( fails == 0 )); then
  echo "AUDIT: PASS (0 failures, $warns warning(s))"
  exit 0
fi
echo "AUDIT: FAIL ($fails failure(s), $warns warning(s))"
exit 1
