#!/usr/bin/env bash
# ci-wait.sh — block until a PR's checks reach a terminal state, then emit JSON.
#
# `gh pr checks --watch` exits non-zero on failure and prints a human table; this
# wrapper instead always exits 0 on a reached verdict and emits machine-readable
# JSON so the orchestrator can branch on it. It also distinguishes the states the
# workflow must treat differently: SUCCESS / FAILURE / CANCELLED / TIMEOUT /
# NO_CHECKS. "Pending" is never a verdict — it keeps polling until the timeout.
#
# Required checks are resolved from the branch-protection API, never hardcoded.
# Note that unlisted checks can fail while every required one is green: the
# emitted JSON reports both, and the merge decision belongs to the caller.
#
# Usage: ci-wait.sh <pr-number> [interval-seconds] [timeout-seconds]
set -uo pipefail

PR="${1:?usage: ci-wait.sh <pr-number> [interval] [timeout]}"
INTERVAL="${2:-45}"
TIMEOUT="${3:-2700}"

cd "$(git rev-parse --show-toplevel)"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
BASE=$(gh pr view "$PR" --json baseRefName --jq .baseRefName)

# Required contexts, discovered. Absent/403 protection ⇒ empty list, not a crash.
REQUIRED=$(gh api "repos/$REPO/branches/$BASE/protection/required_status_checks" \
             --jq '[.contexts[]?]' 2>/dev/null || echo '[]')

deadline=$(( $(date +%s) + TIMEOUT ))

while :; do
  checks=$(gh pr checks "$PR" --json name,state,bucket,link 2>/dev/null || echo '[]')

  if [[ "$(jq 'length' <<<"$checks")" == "0" ]]; then
    # No checks yet: could be "not started" or "none configured". Give CI a
    # grace window before declaring NO_CHECKS so we never merge a PR whose
    # workflows simply had not registered yet.
    if (( $(date +%s) > deadline )); then
      jq -n --argjson r "$REQUIRED" '{verdict:"NO_CHECKS",required:$r,checks:[]}'; exit 0
    fi
    sleep "$INTERVAL"; continue
  fi

  pending=$(jq '[.[] | select(.bucket=="pending")] | length' <<<"$checks")
  if (( pending > 0 )); then
    if (( $(date +%s) > deadline )); then
      jq -n --argjson r "$REQUIRED" --argjson c "$checks" \
        '{verdict:"TIMEOUT",required:$r,
          still_pending:[$c[]|select(.bucket=="pending")|.name],checks:$c}'
      exit 0
    fi
    sleep "$INTERVAL"; continue
  fi

  # Terminal. Classify.
  jq -n --argjson r "$REQUIRED" --argjson c "$checks" '
    ($c | map(select(.bucket=="fail"))            ) as $failed |
    ($c | map(select(.state=="CANCELLED"))        ) as $cancelled |
    ($failed | map(select(.name as $n | $r | index($n))) ) as $failedRequired |
    {
      verdict: (if   ($failed|length) > 0    then "FAILURE"
                elif ($cancelled|length) > 0 then "CANCELLED"
                else "SUCCESS" end),
      required: $r,
      failed:          ($failed    | map({name,link})),
      failed_required: ($failedRequired | map(.name)),
      failed_optional: ($failed | map(select(.name as $n | $r | index($n) | not)) | map(.name)),
      cancelled:       ($cancelled | map(.name)),
      total: ($c|length)
    }'
  exit 0
done
