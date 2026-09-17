#!/usr/bin/env bash
# issue-state.sh — persistent state store for the /issue-loop workflow.
#
# One JSON file per issue under $STATE_DIR/issues/<n>.json, plus a single
# current.json naming the issue being processed (the "logical lock"). The store
# is local and gitignored: it exists so an interrupted run can resume, and so a
# second run cannot pick up an issue that is already in flight.
#
# GitHub remains the source of truth for everything it knows (issue state, PR
# existence, CI result). This store only holds what GitHub cannot tell us: which
# issue we claimed, which phase we reached, and how many fix attempts we burned.
#
# Usage:
#   issue-state.sh init
#   issue-state.sh claim <issue>              # fails if another issue is claimed
#   issue-state.sh release                    # drop the claim (keeps issue record)
#   issue-state.sh current                    # print claimed issue number, or empty
#   issue-state.sh get <issue>                # print the record (empty object if none)
#   issue-state.sh phase <issue> <PHASE> [note]
#   issue-state.sh set <issue> <key> <value>  # value stored as JSON string
#   issue-state.sh setnum <issue> <key> <n>   # value stored as JSON number
#   issue-state.sh bump <issue> <key>         # increment a numeric counter, echo new value
#   issue-state.sh list                       # one line per known issue
#   issue-state.sh blocked                    # issue numbers parked as BLOCKED/EXHAUSTED
#   issue-state.sh done <issue>               # true (exit 0) if terminally finished
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
STATE_DIR="${ISSUE_LOOP_STATE_DIR:-$REPO_ROOT/.claude/state}"
ISSUES_DIR="$STATE_DIR/issues"
CURRENT="$STATE_DIR/current.json"

# Phases mirror the orchestrator state machine. TERMINAL_* never resume.
VALID_PHASES="SELECTED ANALYZING IMPLEMENTING TESTING PR_CREATED CI_RUNNING CI_ANALYSIS FIXING READY_TO_MERGE MERGED BLOCKED EXHAUSTED SKIPPED"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
record() { echo "$ISSUES_DIR/$1.json"; }

need_issue() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "error: issue number required" >&2; exit 2; }
}

ensure_record() {
  local f; f="$(record "$1")"
  [[ -f "$f" ]] || printf '{"issue":%s,"phase":"SELECTED","ci_attempts":0,"local_attempts":0,"created":"%s","history":[]}\n' "$1" "$(now)" >"$f"
}

cmd_init() {
  mkdir -p "$ISSUES_DIR"
  [[ -f "$CURRENT" ]] || echo '{"issue":null,"since":null}' >"$CURRENT"
  echo "state dir: $STATE_DIR"
}

cmd_claim() {
  need_issue "${1:-}"; cmd_init >/dev/null
  local held; held="$(jq -r '.issue // empty' "$CURRENT")"
  if [[ -n "$held" && "$held" != "$1" ]]; then
    echo "error: issue #$held is already claimed; release it or resume it first" >&2
    exit 1
  fi
  ensure_record "$1"
  jq -n --argjson i "$1" --arg t "$(now)" '{issue:$i,since:$t}' >"$CURRENT"
  echo "claimed #$1"
}

cmd_release() {
  cmd_init >/dev/null
  jq -n '{issue:null,since:null}' >"$CURRENT"
  echo "released"
}

cmd_current() { cmd_init >/dev/null; jq -r '.issue // empty' "$CURRENT"; }

cmd_get() { need_issue "${1:-}"; local f; f="$(record "$1")"; [[ -f "$f" ]] && cat "$f" || echo '{}'; }

cmd_phase() {
  need_issue "${1:-}"; local n="$1" p="${2:-}" note="${3:-}"
  grep -qw -- "$p" <<<"$VALID_PHASES" || { echo "error: unknown phase '$p' (valid: $VALID_PHASES)" >&2; exit 2; }
  cmd_init >/dev/null; ensure_record "$n"
  local f; f="$(record "$n")"
  jq --arg p "$p" --arg t "$(now)" --arg note "$note" \
     '.phase=$p | .updated=$t | (if $note=="" then . else .note=$note end)
      | .history += [{phase:$p,at:$t,note:($note|if .=="" then null else . end)}]' \
     "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  echo "#$n → $p"
}

cmd_set() {
  need_issue "${1:-}"; cmd_init >/dev/null; ensure_record "$1"
  local f; f="$(record "$1")"
  jq --arg k "$2" --arg v "$3" --arg t "$(now)" '.[$k]=$v | .updated=$t' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

cmd_setnum() {
  need_issue "${1:-}"; cmd_init >/dev/null; ensure_record "$1"
  local f; f="$(record "$1")"
  jq --arg k "$2" --argjson v "$3" --arg t "$(now)" '.[$k]=$v | .updated=$t' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

cmd_bump() {
  need_issue "${1:-}"; cmd_init >/dev/null; ensure_record "$1"
  local f; f="$(record "$1")"
  jq --arg k "$2" --arg t "$(now)" '.[$k]=((.[$k] // 0)+1) | .updated=$t' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  jq -r --arg k "$2" '.[$k]' "$f"
}

cmd_list() {
  cmd_init >/dev/null
  shopt -s nullglob
  local any=0
  for f in "$ISSUES_DIR"/*.json; do
    any=1
    jq -r '"#\(.issue)\t\(.phase)\tci=\(.ci_attempts // 0)\tbranch=\(.branch // "-")\tpr=\(.pr // "-")\t\(.note // "")"' "$f"
  done
  [[ $any -eq 1 ]] || echo "(no issues tracked yet)"
}

cmd_blocked() {
  cmd_init >/dev/null
  shopt -s nullglob
  for f in "$ISSUES_DIR"/*.json; do
    jq -r 'select(.phase=="BLOCKED" or .phase=="EXHAUSTED" or .phase=="SKIPPED") | .issue' "$f"
  done
}

cmd_done() {
  need_issue "${1:-}"
  local f; f="$(record "$1")"
  [[ -f "$f" ]] || return 1
  jq -e '.phase|IN("MERGED","BLOCKED","EXHAUSTED","SKIPPED")' "$f" >/dev/null
}

case "${1:-}" in
  init)    cmd_init ;;
  claim)   cmd_claim "${2:-}" ;;
  release) cmd_release ;;
  current) cmd_current ;;
  get)     cmd_get "${2:-}" ;;
  phase)   cmd_phase "${2:-}" "${3:-}" "${4:-}" ;;
  set)     cmd_set "${2:-}" "${3:-}" "${4:-}" ;;
  setnum)  cmd_setnum "${2:-}" "${3:-}" "${4:-}" ;;
  bump)    cmd_bump "${2:-}" "${3:-}" ;;
  list)    cmd_list ;;
  blocked) cmd_blocked ;;
  done)    cmd_done "${2:-}" ;;
  *) sed -n '2,30p' "$0" >&2; exit 2 ;;
esac
