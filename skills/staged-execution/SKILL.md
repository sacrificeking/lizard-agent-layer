---
name: staged-execution
description: Use when non-trivial implementation, review, research, or migration work benefits from a provider-neutral 10-80-10 workflow without manual model switches.
---

# Staged Execution

## When to Use
Use when a multi-step task benefits from deliberate planning, bounded implementation, and an independent verification pass.

## Success Criteria
- Pre-check: If DECISIONS.md contains `Status: placeholder`, run `project-decision-harvest` and stop.
- Strategy: Ground implementation in existing sibling patterns (`repo-grounded-change`), run `premortem` for medium/high-risk plans, clarify target files, constraints, and testable acceptance criteria before editing.
- Execution: Perform changes incrementally with bounded checkpoints.
- Verification: Perform a fresh review pass against original criteria using visible evidence.

## Boundaries
- Follow `.agent/protocols/permissions.md` as the authoritative boundary.
- In `inherit-current` mode, complete all phases with the active harness model without requesting a model switch.
- Never encode raw prompts, secrets, customer data, or internal credentials into receipts or memory.

## Verification & Evidence
- Run repository-defined test, typecheck, lint, or build commands.
- Verify actual behavior changes rather than command success alone.

## Output
- List modified files, verification commands executed, and the 3-question review packet.

## Stop Conditions
- Stop when the task acceptance criteria are verified or when an explicit permission gate is encountered.
