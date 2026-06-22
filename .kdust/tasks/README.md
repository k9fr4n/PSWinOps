# PSWinOps `pswinops-function-author` Chain — Task Prompts

This directory captures the full prompt of every KDust task in the
**`pswinops-function-author`** chain, in execution order. These are the
decoupled-chain hops (ADR-0008 / ADR-0009) that author a new public PSWinOps
function end-to-end: spec → code → tests → PR/release → CI feedback loop.

Each hop runs as its own top-level KDust run and hands off to the next via
`enqueue_followup` (at most one per run). The sandbox `work/<slug>/` is
gitignored; only `.kdust/chains/<slug>-<ts>.yaml` is tracked (created by the
spec-analyst hop, which is what materialises `CHAIN_BRANCH` on origin).

## Sequence order

| # | File | Task | Agent | Role |
|---|------|------|-------|------|
| 00 | `00-pswinops-function.md` | `pswinops-function` | Claude_Opus_4.7 | Launcher — computes `CHAIN_BRANCH`, dispatches spec-analyst. No file writes. |
| 10 | `10-pswinops-fn-spec-analyst.md` | `pswinops-fn-spec-analyst` | Claude_Opus_4.7 | Hop 1 — reads the module, produces `work/<fn>/spec.yaml` + tracked chain manifest. |
| 20 | `20-pswinops-fn-author.md` | `pswinops-fn-author` | claude-sonnet | Hop 2 — writes the function, Format view, manifest + help. `initial`/`fix` modes. |
| 30 | `30-pswinops-fn-test-engineer.md` | `pswinops-fn-test-engineer` | claude-sonnet | Hop 3 — writes Pester v5 suite, optional CI matrix patch, local validation. |
| 40 | `40-pswinops-fn-quality-gate.md` | `pswinops-fn-quality-gate` | Claude_Opus_4.7 | Hop 4 — static + conformance audit, version bump, PR open, arm auto-merge. |
| 50 | `50-pswinops-fn-ci-watcher.md` | `pswinops-fn-ci-watcher` | Claude_Opus_4.7 | Hop 5 (manual) — parses failing CI logs, loops back to fn-author MODE=fix. |

## Flow

```
pswinops-function (launcher)
        └─▶ pswinops-fn-spec-analyst        (creates CHAIN_BRANCH)
                └─▶ pswinops-fn-author MODE=initial
                        └─▶ pswinops-fn-test-engineer
                                ├─ PASS ─▶ pswinops-fn-quality-gate ─▶ (PR + auto-merge) ─▶ END
                                │                                          ▲
                                └─ FAIL ─▶ pswinops-fn-author MODE=fix ────┘ (max 3)

pswinops-fn-ci-watcher (manual, post-PR)
        └─ on red CI ─▶ pswinops-fn-author MODE=fix  (same CHAIN_BRANCH / same PR, max 3)
```

> Snapshot exported from the KDust task catalogue. The task definitions remain
> the source of truth; refresh these files if a hop prompt changes.
