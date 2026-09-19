# 0008 — Measurable loop control and dampener (HumanLayer harvest)

**Work package:** optional extension of **existing** `loop.schema.json` + verifier packets. Pack `loop-engineering` only. Not overlay default. Not a new skill OS.
**Source:** humanlayer/skills (`design-control-loop`, `build-iterated-agentic-loop`). No code, no submodule, no five-skill import.
**Priority:** **after residuals of** 0001, 0004, 0005, 0006, 0007 (0002/0003 already shipped). Massive only if the next product goal is recurring improvement loops. For daily overlay / first install, **do nothing**.
**Status (2026-09-10):** **Later. Keep.** Loop-init `-Apply` without `-HumanApproved` is documented and is **not** this WP (do not turn 0008 into an installer). Coverage≥80% as a default gate stays out. Ruflo/SPARC/workflow MCP stay rejected.

Do not change product files until this idea is explicitly approved for implementation.

## Verdict on the comparison

The write-up is directionally right and slightly too eager.

| Claim | Ours |
| --- | --- |
| Do not absorb humanlayer/skills | Agree. Claude plugin + five skills. Wrong layer. |
| Lizard already stronger on governance | Agree. Lease, budget, DoD packets, identity split, no auto-merge (ADR 0008). |
| Control-loop vocabulary is the harvest | **Partial.** Useful as *measurable intent*, not as a second ontology beside `definitionOfDone`. |
| Dampener is the best idea | Agree **if** there is a numeric/ordinal sensor from a **constrained** command plan. Otherwise it is prose. |
| Workflow compiler LoopDef → GHA/Codex/Claude | **Reject as lizard core.** Scheduler-independent by ADR 0008. That compiler is an adjacent CI product (Spec-Kit class). |
| Ruflo `workflow_*` MCP + SPARC orchestrator + 12 background workers | **Reject.** Stateful MCP pipelines and queen-led swarms are a second runtime. Overlay loops stay lease + budget + HumanApproved, no `npx ruflo`. Coverage≥80% as a default gate is not a layer contract (optional `control` sensor later, pack only). |
| `loop-designer` meta-skill + four reference files | **Reject.** Catalog calorie. `loop-init` can ask for a sensor later. |
| Anshu “cheap orchestrator + frontier coder” (X 2098014776886448337) | **Reject as overlay.** ChatGPT Plus / Codex subagent recipe. ADR 0009: no model names in portable skills. Existing `loop-budget` already has cheap-vs-strong **roles** and sub-agent allowance; do not pin Luna/Astra or “always fresh contexts.” |
| PR bounding / maxOpenPRs | **Not yet.** Lizard has no PR actuator (no auto-merge, no GitHub client). Lease already ≈ `maxActiveRuns: 1`. |
| improve-claude-md / show-me / react prop narrowing | Agree reject. Conditional context = adapters; React tactic = optional pack note, not a skill. |

Lizard `successMetrics` today is a **string list**. `definitionOfDone` is categorical (`tests`, `diff-scope`, `manifest`, …). The runtime budget is **tokens/runs/attempts/lease**, not “coverage must not fall.” That is the real gap — and it does not hurt `standard` overlay users.

## What already covers “backpressure”

- One active lease per pattern (`loop-runtime-lease.schema.json`).
- `max_runs_per_day`, `max_attempts_per_item`, `on_exceed: pause`.
- Stale lease is never stolen; recover needs `-HumanApproved`.

Do not add a parallel `backpressure:` object that restates the lease. If a later GitHub Action **adapter** (out of this repo or a future optional pack) needs `maxOpenPRs`, that adapter owns GitHub, not `loop.schema.json`.

## Solution (minimal, lizard-shaped)

Extend the **existing** loop pattern with an **optional** `control` block. No `LoopIntent` product, no HumanLayer names required in the overlay.

```text
definitionOfDone          # keep: this-run evidence packets
control?                  # optional: measurable trajectory
  metric_id
  sensor                  # constrained verification-plan command, not free shell
  parser                  # number | count | bytes | enum
  baseline                # verified-head | first-run
  target                  # optional setpoint
  dampener?               # no-regression vs last PASS baseline, with tolerance
  max_iterations          # already close to max_attempts_per_item — prefer reuse
```

**Dampener** is a **new verifier packet kind**, not a skill:

- After this run’s commands (ADR 0018 constrained plan), parse metric M.
- Load last **PASS** baseline for `(pattern, metric_id)` from loop runtime state (not from target prose).
- If dampener on and M is worse than baseline beyond tolerance → FAIL / WARN, even if this-run DoD would pass.
- Implementer must not write the baseline; verifier writes it on PASS.

Sensor commands are the same class as `loop-verify.ps1` allowlisted commands. Never “run `npm test` because the skill said so.”

## Implementation (only when periodic improvement loops are an explicit goal)

1. Additive fields on `schemas/loop.schema.json` (`control` optional; `additionalProperties` stays false). Existing four patterns omit it — still valid.
2. Runtime state: last verified `{ metric_id, value, head_sha, evidence_hash }` per pattern.
3. `loop-verify.ps1`: if `control` present, require sensor command on the verification plan; apply dampener; persist baseline only on PASS.
4. Docs: `docs/loop-engineering.md` — “measurable control is opt-in; L1 remains report-only; L2 still no auto-merge.”
5. One fixture pattern (not shipped as default): e.g. lint-count monotonic decrease in tests, not in `profiles/standard.json`.
6. Changelog + `changes/` for the loop contract.

Do not:

- Vendor humanlayer/skills or copy SKILL.md text.
- Add `skills/loop-designer/` or `sensors.md` encyclopedias.
- Generate `.github/workflows/*` from lizard.
- Put control-loop into always-on adapters or the six-skill diet.
- Require RSA for L1 reports.
- Treat coverage % as a default bank metric (noisy; prefer counts from constrained commands).

## Premortem

- Dual spec (`LoopIntent` + `definitionOfDone`) will fork the runtime. One schema.
- Unconstrained sensor = untrusted target script. Same ADR 0018 hole as “L2 runs npm test.”
- Dampener on flaky metrics causes infinite FAIL. Require deterministic parse; allow `WARN` + human gate, not silent skip.
- “Backpressure” as GitHub PR labels pulls a network client into a no-telemetry layer.
- Implementing this **before** 0004/0002/0005 burns the operator-product gap for a loop feature most installs never enable (`loop-engineering` is opt-in).

## Done when

- A loop pattern *may* declare a constrained sensor + no-regression dampener; default patterns still work without it.
- Verifier can FAIL a run that would otherwise PASS if the metric regressed vs last PASS baseline.
- Overlay calorie and default profiles unchanged.
- No HumanLayer files in the tree.
- Explicit product decision recorded: this ships only with a named improvement-loop goal, not as overlay vNext theater.
