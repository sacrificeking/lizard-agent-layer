---
name: staged-execution
description: Use when non-trivial implementation, review, research, or migration work benefits from a provider-neutral 10-80-10 workflow without manual model switches.
---

# Staged Execution

Use this skill when a task needs deliberate planning, sustained execution, and explicit verification.

## Workflow

- Start from the user's ordinary task prompt. Apply routing and phases internally; never require the user to invoke a routing script or understand role names.
- Read `.agent/routing/policy.json`, `.agent/project-profile.json`, and `.agent/protocols/staged-execution.md`.
- Strategy: clarify the outcome, constraints, acceptance criteria, affected areas, risks, and verification plan before editing.
- Execution: perform the work with bounded checkpoints; return to strategy on material plan deviation.
- Verification: start a fresh review pass against the original criteria, inspect the diff, and run risk-proportionate checks.
- Treat the 10-80-10 split as approximate. Correctness and safety take precedence over exact percentages.

## Model mode

- In `inherit-current` mode, complete every phase with the active harness model. Never ask the user to change a model picker mid-task.
- In `inventory-routing` mode, require a ready automatic runtime with actual-model reporting, then use only available, approved, non-expired, calibrated inventory entries whose runtime fingerprint and role score meet policy.
- Never infer capability from a provider or model name. Unknown and future models remain uncalibrated until evaluated.
- If Advanced routing cannot satisfy its contract, stop that route and direct configuration back to `inherit-current`; do not create a manual switch workflow.

## Verification

- Verify the changed behavior, not only that commands exit successfully.
- Run the target's relevant tests, typecheck, lint, build, validation, or audit commands in proportion to risk.
- Record `self-review` unless a different automatically selected model actually performed verification. A route recommendation alone is not proof.
- Keep receipts metadata-only and confirm `raw_prompt_stored` remains false.

## Safety

- Stop for human review on policy signals, unapproved scope expansion, secrets, regulated data, or exhausted attempts.
- Preserve unrelated user changes and obey repository permissions before destructive or remote actions.
- For database or production migrations, require explicit approval, a reviewed rollback path, and environment-specific verification.

## Example

For an ordinary IDE implementation, plan the change, implement it, and review the diff with the currently selected model. The route decision reports `model_mode: inherit-current`, `recommended_model: null`, and `model_switch_required: false`.
