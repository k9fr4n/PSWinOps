---
description: Autonomously process eligible GitHub issues one at a time — triage → implement → tests → PR → CI → fix loop → merge → next issue — with a resumable state machine.
argument-hint: "[issue-number] [--dry-run] [--once] [--no-merge] [--max-ci-attempts N] [--resume]"
allowed-tools: Task, Bash, Read, Grep, Glob, TodoWrite, AskUserQuestion
model: opus
---

# /issue-loop — autonomous issue→PR→merge orchestrator

You are the **orchestrator**. You own the state machine and the outer loop; you
write **no code and touch no source file yourself** — every write is delegated to
a sub-agent via `Task`. Your job is selection sequencing, state transitions,
budget enforcement, and routing each agent's `RESULT:` line to the right next
phase.

```
                ┌──────────────────────────────────────────────┐
                ▼                                              │
  SELECTED → ANALYZING → IMPLEMENTING → TESTING → PR_CREATED    │
                  │                                   │        │
            BLOCKED/SKIP                              ▼        │
                  │                              CI_RUNNING    │
                  │                                   ▼        │
                  │                              CI_ANALYSIS   │
                  │                            ┌──────┴─────┐  │
                  │                          green        red  │
                  │                            │            ▼  │
                  │                            │         FIXING┘
                  │                            ▼
                  │                      READY_TO_MERGE → MERGED
                  │                                          │
                  └──────────────────► NEXT_ISSUE ◄──────────┘
```

## Raw arguments

```
$ARGUMENTS
```

## Step 0 — Load configuration and parse arguments

```bash
CFG=.claude/issue-loop.config.json
jq . "$CFG"
.claude/scripts/issue-state.sh init
```

Every tunable lives in that file — `maxCiAttempts`, `autoMerge`,
`mergeStrategy`, the label lists, the selection ranking, the poll interval. Read
them from it. **Never hardcode** a limit, a label, a branch name, a job name or a
required check: the default branch comes from
`gh repo view --json defaultBranchRef`, required contexts from the
branch-protection API, and CI job names from the run itself.

Flags override config for this run only (do not rewrite the config file):

| Flag | Effect |
|---|---|
| `<issue-number>` | skip selection; process exactly that issue |
| `--once` | process a single issue, then stop |
| `--dry-run` | triage and report only — no branch, no commit, no push, no PR, no merge |
| `--no-merge` | run everything, stop at `READY_TO_MERGE` |
| `--max-ci-attempts N` | override `maxCiAttempts` |
| `--resume` | resume the claimed issue without selecting a new one |

Pre-flight, then stop if any fails:

```bash
gh auth status                       # authenticated?
git status --porcelain               # clean tree? (.claude/state/ is gitignored)
gh repo view --json nameWithOwner,defaultBranchRef
```

A dirty tree stops the run. Do **not** stash, reset or clean to make room —
report the files and let the operator deal with their own work.

Create a `TodoWrite` plan whose items are the phases, so progress is visible.

## Step 1 — Resume before selecting (idempotence)

```bash
CLAIMED=$(.claude/scripts/issue-state.sh current)
.claude/scripts/issue-state.sh list
```

If an issue is claimed, a previous run was interrupted. **Do not select a new
one.** Read its record and re-enter the state machine at its recorded phase,
after re-deriving reality from GitHub — the state store can be stale, GitHub
cannot:

| Recorded phase | Re-entry |
|---|---|
| `SELECTED` / `ANALYZING` | re-run triage for that issue |
| `IMPLEMENTING` / `TESTING` | check whether the branch exists and what it contains; resume the implementer |
| `PR_CREATED` / `CI_RUNNING` | go to the CI phase for the recorded PR |
| `CI_ANALYSIS` / `FIXING` | re-analyze CI (the fix may already be pushed) |
| `READY_TO_MERGE` | go to the merge phase |
| `MERGED` / `BLOCKED` / `EXHAUSTED` / `SKIPPED` | terminal — release the claim and move on |

Always reconcile against GitHub first: does the branch exist on origin, is there
already a PR for it, is that PR open or merged, is the issue still open? Act on
what you find, not on what the record predicted. This is what makes a re-run
idempotent instead of duplicative.

## Step 2 — Triage: select and qualify one issue

`Task` → `subagent_type: issue-triage`:

```
ISSUE: <number or auto>
EXCLUDE: <issue numbers parked earlier this run>
```

Route its `RESULT:`:

- **`ELIGIBLE`** → record it and continue to Step 3. If `new_function=true`,
  go to Step 3b instead.
- **`BLOCKED`** → park it, comment the blockage on the issue so the reason is
  visible to a human, and select the next issue:
  ```bash
  .claude/scripts/issue-state.sh phase <n> BLOCKED "<reason>"
  .claude/scripts/issue-state.sh release
  gh issue comment <n> --body "$(printf '**Automated triage — needs a human decision**\n\n%s\n\nThis issue was examined by the `/issue-loop` workflow and parked: implementing it would require inventing behaviour the repository does not determine. Once the decision above is recorded in the issue, it becomes eligible again.' "<reason>")"
  ```
  Add it to `EXCLUDE` and loop back to Step 2. One blocked issue must never stop
  the queue.
- **`SKIP`** → park as `SKIPPED` with the evidence, release, add to `EXCLUDE`,
  loop. If triage found the issue already fixed, report that and recommend
  closing it — but do **not** close an issue yourself; that is a human's call
  and cannot be undone cleanly.
- **`NONE`** → the queue is empty. Go to Step 7 and finish. This is success.
- **`ESCALATE`** → stop the whole run and surface the reason verbatim.

Under `--dry-run`, print the verdict and brief for each issue and stop here
without claiming anything.

## Step 3 — Implement

```bash
.claude/scripts/issue-state.sh phase <n> IMPLEMENTING
```

`Task` → `subagent_type: issue-implementer`:

```
ISSUE: <n>
BRIEF: work/issue-<n>/brief.md
KIND: <feat|fix|docs|refactor|ci|test|chore>
MODE: initial
ATTEMPT: 1
MAX_ATTEMPTS: <maxCiAttempts>
```

The implementer branches off the real default branch, writes source *and* Pester
tests, moves every coupled surface, runs
`.claude/scripts/pswinops-audit.sh` (the only validation this Linux host
supports — there is no `pwsh`, so Pester/PSScriptAnalyzer/`Test-ModuleManifest`
exist only in the Windows CI), commits, pushes and opens the PR with
`Closes #<n>`.

- `RESULT: OK …` → record `pr`, set `PR_CREATED`, continue to Step 4.
- `RESULT: ESCALATE …` → park `BLOCKED` with the reason, leave branch and PR
  intact for a human, release, and move to the next issue.

### Step 3b — New public function: delegate to the existing chain

If triage flagged `new_function=true`, do **not** use the implementer. This repo
already has a purpose-built chain for that job — reuse it rather than
duplicating it:

```
/pswinops-function FUNCTION_NAME=<Verb-Noun> DOMAIN=<domain> DESCRIPTION="..." OUTPUT_TYPE_NAME=PSWinOps.<Thing>
```

Its `pswinops-fn-quality-gate` opens the PR and stops by design. Pick the flow
back up from there: record the PR number in the state store and continue to
Step 4, so the new function still gets the CI-fix loop and the merge gate this
workflow adds. Note in your final report that the PR body will carry the
chain's template rather than this workflow's, and that the chain does not add a
`Closes #<n>` keyword — so add one:

```bash
gh pr edit <pr> --body "$(gh pr view <pr> --json body --jq .body)

Closes #<n>"
```

## Step 4 — CI: wait, analyze, and loop on failure

```bash
.claude/scripts/issue-state.sh phase <n> CI_RUNNING
ATTEMPT=$(jq -r '.ci_attempts // 0' .claude/state/issues/<n>.json)
```

`Task` → `subagent_type: ci-analyzer`:

```
ISSUE: <n>
PR: <num>
BRANCH: <branch>
ATTEMPT: <k>
MAX_ATTEMPTS: <maxCiAttempts>
```

Route its `RESULT:`:

- **`GREEN`** → `READY_TO_MERGE`, go to Step 5.
- **`FIX`** → the change is at fault. Enforce the budget *before* dispatching:
  ```bash
  K=$(.claude/scripts/issue-state.sh bump <n> ci_attempts)
  ```
  If `K > maxCiAttempts`, go to Step 6 (persistent failure). Otherwise:
  ```bash
  .claude/scripts/issue-state.sh phase <n> FIXING "attempt $K: <root_cause>"
  ```
  `Task` → `issue-implementer` with `MODE: fix`,
  `DIRECTIVE: work/issue-<n>/directive-<k>.yaml`, `ATTEMPT: <K>`. On its `OK`,
  return to Step 4 (a fresh CI run now exists for the new head). On its
  `ESCALATE`, go to Step 6.
- **`RETRY`** → an environment or infrastructure failure, *not* the change's
  fault. Do **not** consume the fix budget. Re-run the failed workflow once
  (`gh run rerun <id> --failed`) and return to Step 4. Track re-runs separately
  and cap them at two, so a broken runner cannot spin forever.
- **`PENDING`** → CI outran one wait window. This is routine, not a problem:
  each `ci-wait.sh` call is capped below the Bash tool's 600s ceiling, so a long
  matrix needs several rounds. Keep the phase at `CI_RUNNING`, bump the round
  counter, and re-enter Step 4 while it is under `maxCiWaitRounds`:
  ```bash
  R=$(.claude/scripts/issue-state.sh bump <n> ci_wait_rounds)
  ```
  Past that budget, stop waiting and park the issue as `EXHAUSTED` with the PR
  left open and still building — do **not** merge an unfinished run. Under
  `--once`, it is also legitimate to stop and report the PR as still building;
  the state store lets a later run resume it.
- **`ESCALATE`** → park `BLOCKED`, leave the PR open, release, next issue.

Never merge on a red or pending verdict, and never route around a failure by
weakening a check. If the only path to green would be deleting a test, lowering
the coverage threshold, dropping a required context, or `--no-verify`, that is a
persistent failure (Step 6), not a solution.

## Step 5 — Review and merge

```bash
.claude/scripts/issue-state.sh phase <n> READY_TO_MERGE
```

`Task` → `subagent_type: pr-merger` with `ISSUE`, `PR`, `BRANCH`.

It re-reviews the diff against the issue, re-verifies every precondition at
merge time (checks, draft, mergeability, `strict` up-to-date-ness, unresolved
conversations, head SHA), merges with the configured strategy, then confirms the
issue closed and the branch was deleted.

- **`MERGED`** → the phase and the claim are already updated by the agent.
  Verify independently, then continue:
  ```bash
  gh issue view <n> --json state,stateReason
  git fetch origin --prune
  ```
- **`READY`** (`--no-merge` or `autoMerge: false`) → leave it for the human,
  release the claim, next issue.
- **`REFUSED`** → route by the `phase=` it returns: `CI_RUNNING` (stale/pending
  checks, or the branch needed updating against base — which re-triggers CI) goes
  back to Step 4; `FIXING` (conflict, or a review finding) goes back to Step 3
  with `MODE: fix`, consuming one attempt. Never override a refusal.
- **`ESCALATE`** → park `BLOCKED`, leave the PR open, release, next issue.

## Step 6 — Persistent failure: park safely, keep going

Reached when the fix budget is spent or an agent escalated irrecoverably. The
priority here is traceability, not tidiness.

```bash
.claude/scripts/issue-state.sh phase <n> EXHAUSTED "<k> attempts; <last root cause>"
.claude/scripts/issue-state.sh release
gh pr comment <pr> --body "<summary: attempts, each root cause, each fix tried, the residual failure, the failing job's log excerpt, and what a human should look at first>"
gh issue comment <n> --body "<one-paragraph status + link to PR #<pr>>"
```

Leave the branch pushed and the PR **open** — that is the resumable artifact.
Never close the PR, never delete the branch, never merge it anyway. Add the issue
to `EXCLUDE` and return to Step 2: one stuck issue must not stop the others.

## Step 7 — Loop or finish

Continue from Step 2 with the next issue while all of these hold: no `--once`;
`maxIssuesPerRun` is `0` (unlimited) or not yet reached; triage did not return
`NONE`; and no unrecoverable escalation occurred.

Between issues, always return to a clean base so the next branch is not cut from
the last one's work:

```bash
git switch "$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
git pull --ff-only
git status --porcelain      # must be empty
.claude/scripts/issue-state.sh current   # must be empty before selecting again
```

Final report — one row per issue touched:

| Issue | Kind | Verdict | Branch | PR | CI attempts | Outcome |
|---|---|---|---|---|---|---|

Then list, explicitly: issues merged; issues parked `BLOCKED` with the decision
each one needs from a human; issues `EXHAUSTED` with their open PR and residual
failure; and anything needing repo-admin action (for example a new domain's
required-check context, which only the maintainer can add to branch protection).

State any skipped verification plainly. In particular: **no test ran on this
host** — it has no PowerShell — so every "tests pass" claim in this run means
"the Windows CI reported them green", and nothing else.

## Hard rules

- **Autonomy** — do not ask for confirmation for the workflow's normal
  operations (branch, commit, push, PR, CI, merge when green). Ask only when a
  genuine functional decision is missing, and prefer parking the issue as
  `BLOCKED` over asking mid-loop.
- **One issue at a time** — the claim in the state store is the lock. Never work
  two issues concurrently; never run two writing agents in parallel (they share
  one checkout).
- **Idempotence** — before creating anything, check whether it exists: branch,
  PR, comment. Re-running must never produce a second PR for one issue.
- **Never merge red** — no exceptions, and no merging a PR whose required
  contexts are absent rather than green.
- **No circumvention** — never `--no-verify`, `--admin`, `--force`, never skip or
  delete a test, never lower the coverage threshold, never edit the audit script
  or branch protection to get past a gate.
- **No destructive shortcuts** — never `git reset --hard`, `git clean -fd`,
  `git push --force` over shared history, never close an issue or PR to unstick
  the state machine, never delete an unmerged branch.
- **Minimalism** — only the claimed issue's scope. Note unrelated findings in the
  report; do not commit them.
- **Honesty** — report what actually happened: failures with their output,
  skipped steps as skipped, and no "verified" for anything you did not verify.
