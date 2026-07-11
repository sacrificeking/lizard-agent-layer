# Loop Engineering

Loop engineering is the practice of designing repeatable agent workflows as bounded feedback loops instead of one-off prompts. In `lizard-agent-layer`, loops are intentionally conservative: they start at L1/report-only, produce evidence and next actions, and require human approval before writes, dependency changes, releases, or high-risk decisions.

## Why it exists

Modern models are strong enough to run recurring checks, but target projects still need predictable boundaries. Older and cheaper models can be very useful when the loop is decomposed into small, explicit steps: scan, summarize, check state, propose next action, stop. Stronger models are reserved for ambiguity, cross-cutting risk, security-sensitive interpretation, release readiness, and final synthesis.

## Readiness levels

- `L0`: checklist-only prompt pattern, no runtime files.
- `L1`: report-only loop with state, budget, constraints, run log, and human gates.
- `L2`: controlled apply loop for narrow generated artifacts after strong tests and ownership rules exist.
- `L3`: autonomous loop for mature projects with evals, telemetry, rollback, and strict allowlists.

This repository ships L1 report-only patterns and one L2 assisted pattern. L2 is still human-approved, worktree-isolated, verifier-gated, and no-auto-merge.

## Built-in patterns

- `daily-triage`: recurring risk, stale work, open decision, and next-action report.
- `release-readiness`: version, changelog, quality gate, drift, and release decision packet.
- `layer-update-watch`: compares installed targets with the current layer and prepares update plans.
- `minimal-fix-assist`: L2 assisted smallest-scope fixes in an isolated worktree with mandatory verifier review and no auto-merge.

Patterns live in `loops/*.json` and are listed in `loops/registry.json`.

## Install into a target

Install the reusable skills first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs loop-engineering -WritePlan
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs loop-engineering -Apply
```

Create the target loop runtime with a preview plan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -WritePlan
```

Apply after reviewing the plan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -Apply
```

The target receives `.agent/loops/LOOP.md`, state, budget, run-log, constraints, and `lizard-agent-layer.loop-install.json`.

## Operate a loop

Audit an installed loop:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-audit.ps1 -TargetPath D:\path\to\project -Strict
```

Generate a human-readable report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-report.ps1 -TargetPath D:\path\to\project
```

Sync loop metadata after a layer update without overwriting project state:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-sync.ps1 -TargetPath D:\path\to\project
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-sync.ps1 -TargetPath D:\path\to\project -Apply
```

Estimate cost and model budget:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-cost.ps1 -Pattern daily-triage -Level L1 -Cadence 1d
```

## Safety and updateability

- Preview mode does not write into the target unless `-Apply` is used.
- Existing loop files are skipped by default.
- `loop-sync.ps1` updates metadata and creates missing files, but it does not overwrite state files.
- `-ForceTemplates` is limited to static templates and should only be used after reviewing the sync report.
- Human gates are explicit in every pattern and include `human_review_before_write` and `human_review_before_release`.

## Model routing

Use cheaper models for deterministic scanning, inventory, state pruning, and checklist expansion. Use stronger models for ambiguous failures, architecture tradeoffs, security/auth/finance findings, and release verdicts. This keeps loops useful across Codex, Claude, Gemini, Cursor-compatible agents, and older budget models.

## L2 Assisted Worktree Flow

L2 is not autonomy. It is a controlled assisted workflow for one human-approved item.

1. Install the `loop-engineering` pack.
2. Initialize the L2 pattern with `minimal-fix-assist` and review the plan.
3. Preview worktree creation with `loop-worktree.ps1`.
4. Create the worktree only with `-Apply -HumanApproved`.
5. Make the smallest approved change in the assisted worktree.
6. Generate an evidence-bound verifier packet with `loop-verify.ps1` and the lifecycle file produced during creation.
7. Let a human decide whether to merge, revise, discard, or pause.
8. Clean up the isolated worktree only with `loop-worktree-cleanup.ps1 -Apply -HumanApproved`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern minimal-fix-assist -WritePlan
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern minimal-fix-assist -Apply
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-worktree.ps1 -TargetPath D:\path\to\project -ItemId fix-123 -Branch lizard/l2/fix-123
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-worktree.ps1 -TargetPath D:\path\to\project -ItemId fix-123 -Branch lizard/l2/fix-123 -Apply -HumanApproved
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-verify.ps1 -TargetPath D:\path\to\project -LifecyclePath D:\path\to\reports\loop-worktree-lifecycle.json -Implementer implementer-name -Verifier reviewer-name -Status PASS -VerificationCommand "npm test" -Apply
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-worktree-cleanup.ps1 -TargetPath D:\path\to\project -LifecyclePath D:\path\to\reports\loop-worktree-lifecycle.json -RemoveBranch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-worktree-cleanup.ps1 -TargetPath D:\path\to\project -LifecyclePath D:\path\to\reports\loop-worktree-lifecycle.json -RemoveBranch -Apply -HumanApproved
```

L2 never auto-merges, pushes, releases, deploys, changes dependencies, edits migrations, or touches secrets without separate explicit approval. The verifier rejects unsafe report paths, wrong repositories, non-root worktree paths, branch mismatches, self-review, failed commands, tampered lifecycle data, and stale Git state before it can write the target verifier report. See [L2 Lifecycle And Verifier Evidence](loop-evidence.md).
