---
description: Author a new public PSWinOps function end-to-end (spec → code → tests → PR) by orchestrating dedicated sub-agents.
argument-hint: FUNCTION_NAME=Verb-Noun DOMAIN=iis DESCRIPTION="..." OUTPUT_TYPE_NAME=PSWinOps.Thing [REMOTE_CAPABLE=true] [SUPPORTS_SHOULDPROCESS=auto] [CONFIRM_IMPACT=None] [REFERENCE_KB=url]
allowed-tools: Task, Bash, Read, Grep, Glob, AskUserQuestion, TodoWrite
model: opus
---

# /pswinops-function — chain orchestrator

You are the **orchestrator** of the `pswinops-function-author` chain. You drive
four dedicated sub-agents in sequence on a shared branch, own the fix loop, and
stop once the PR is open. You author **no code yourself** — every file write is
delegated to a sub-agent via the `Task` tool. Your job is input validation,
branch bootstrap, sequencing, and decision-making on each agent's returned
`RESULT:` line.

This is the Claude Code port of a former 6-hop async chain. The two structural
changes you embody: there is **no `enqueue_followup`** (you call the next agent
yourself and wait for its report), and there is **no auto-push/auto-merge
pipeline** (each writing agent pushes explicitly; you stop at PR-open, the human
merges).

## Raw arguments

```
$ARGUMENTS
```

## Step 0 — Parse & validate inputs

Parse the arguments above as `KEY=value` / `KEY: value` pairs (also accept a
natural-language description). Resolve this input set:

| Key | Required | Default |
|---|---|---|
| `FUNCTION_NAME` | yes | — must match `^[A-Z][a-z]+-[A-Z][A-Za-z0-9]+$` |
| `DOMAIN` | yes | — sub-folder under `Public/` |
| `DESCRIPTION` | yes | one sentence |
| `OUTPUT_TYPE_NAME` | yes | `PSWinOps.<Thing>` |
| `REMOTE_CAPABLE` | no | `true` |
| `SUPPORTS_SHOULDPROCESS` | no | inferred: `true` if verb ∈ {Set,New,Remove,Clear,Hide,Show,Install,Uninstall,Invoke,Enable,Disable,Reset,Unlock,Sync,Connect,Disconnect,Export}, else `false` |
| `CONFIRM_IMPACT` | no | `None` when ShouldProcess=false, else `High` |
| `REFERENCE_KB` | no | empty |
| `WORK_DIR` | no | `work/<slug>` |
| `MAX_ITER` | no | `3` |

**If any required input is missing**, use `AskUserQuestion` to collect it before
proceeding. Do not guess `FUNCTION_NAME`, `DOMAIN`, or `OUTPUT_TYPE_NAME`.

**Verb gate (replaces the old launcher hop).** The verb is the text left of the
`-`. Validate it against the PowerShell approved-verb set. Common rejects and
their canonical replacement — ABORT with the suggestion if you hit one:
`Create→New`, `Delete→Remove`, `Change/Modify→Set`, `Fetch/Retrieve→Get`,
`Check→Test`, `List→Get`, `Make→New`, `Pull→Receive`, `Push→Send`,
`Verify→Test`, `Configure→Set`. If the verb is plainly not approved and has no
obvious mapping, ABORT with `[CRITICAL] unapproved verb '<verb>'` and stop —
**do not invoke any agent**.

## Step 1 — Bootstrap chain identity

Run (Bash):

```bash
SLUG=$(echo "<FUNCTION_NAME>" | tr '[:upper:]' '[:lower:]')
TS=$(date -u +%y%m%d%H%M)
CHAIN_BRANCH="kdust/chain/pswinops-fn-${SLUG}-${TS}"
WORK_DIR="work/${SLUG}"   # unless overridden
```

Emit a short pre-flight summary (function, domain, branch, remote/shouldprocess,
work dir). Create a `TodoWrite` plan with one item per hop so progress is visible.

## Step 2 — Hop 1: spec-analyst (Opus)

`Task` → `subagent_type: pswinops-fn-spec-analyst`, prompt carrying:

```
CHAIN_BRANCH: <value>
WORK_DIR: <value>
FUNCTION_NAME: <value>
DOMAIN: <value>
DESCRIPTION: <value>
OUTPUT_TYPE_NAME: <value>
REMOTE_CAPABLE: <value>
SUPPORTS_SHOULDPROCESS: <value>
CONFIRM_IMPACT: <value>
REFERENCE_KB: <value or empty>
```

It creates `CHAIN_BRANCH` on origin (chain-manifest commit) and writes
`<WORK_DIR>/spec.yaml`. Expect `RESULT: OK spec=<WORK_DIR>/spec.yaml` or
`RESULT: ESCALATE reason=...`. On ESCALATE, stop and report.

## Step 3 — Hop 2: author MODE=initial (Sonnet)

`Task` → `subagent_type: pswinops-fn-author`, prompt:

```
CHAIN_BRANCH: <value>
WORK_DIR: <value>
SPEC_PATH: <WORK_DIR>/spec.yaml
FUNCTION_NAME: <value>
DOMAIN: <value>
MODE: initial
ATTEMPT: 1
MAX_ITER: <value>
```

Expect `RESULT: OK commit=<sha>` or `RESULT: ESCALATE reason=...`.

## Step 4 — Fix loop: test-engineer ⇄ author (max `MAX_ITER`)

Set `ATTEMPT=1`. Loop:

1. `Task` → `subagent_type: pswinops-fn-test-engineer`, prompt with
   `CHAIN_BRANCH / WORK_DIR / SPEC_PATH / FUNCTION_NAME / DOMAIN / ATTEMPT / MAX_ITER`.
2. Read its `RESULT:` line:
   - `RESULT: PASS` → **break** to Step 5.
   - `RESULT: FAIL report=<WORK_DIR>/test_report_<ATTEMPT>.yaml`:
     - If `ATTEMPT >= MAX_ITER` → **stop**, report the budget burn + the report path. Do not invoke quality-gate.
     - Else `Task` → `subagent_type: pswinops-fn-author` with
       `MODE: fix`, `FEEDBACK_FILE: <report path>`, `ATTEMPT: <ATTEMPT>` (the
       author commits the fix), then set `ATTEMPT=ATTEMPT+1` and loop.
   - `RESULT: ESCALATE reason=...` → stop and report.

Never re-order: a test run must always follow the most recent author commit.

## Step 5 — Hop 4: quality-gate → open PR, then STOP (Opus)

`Task` → `subagent_type: pswinops-fn-quality-gate`, prompt:

```
CHAIN_BRANCH: <value>
WORK_DIR: <value>
SPEC_PATH: <WORK_DIR>/spec.yaml
FUNCTION_NAME: <value>
DOMAIN: <value>
```

It runs the Linux-runnable conformance audit, bumps the module version + release
notes, opens the PR, and **stops** (no auto-merge, no CI watcher — the human
merges once Windows CI is green). Expect `RESULT: OK pr=<url>` or
`RESULT: ESCALATE reason=...`.

## Step 6 — Final report

Print: branch, PR URL, function path, files touched, and the iteration count.
Mark all todos done. Tell the operator the PR is open and merging is theirs once
the Windows CI matrix is green.

## Hard rules

- You **never** edit `Public/`, `Tests/`, `.psd1`, `Format.ps1xml`, `help`, or
  `ci.yml` directly — only sub-agents do.
- Run sub-agents **strictly sequentially** (they share one branch/checkout).
- On any `RESULT: ESCALATE`, stop immediately and surface the agent's reason
  verbatim — do not paper over it.
- Validation is **CI-only** by design: do not expect agents to run
  `Import-Module` / `Invoke-Pester` / `Test-ModuleManifest` (the module loader
  hard-fails on this non-Windows host). The Windows GitHub Actions CI is the
  gate.
