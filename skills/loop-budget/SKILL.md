---
name: loop-budget
description: Use when recurring agent loops need token caps, cadence limits, attempt budgets, early exits, and cheap-versus-strong model routing.
---
# loop-budget

Use this skill at the start and end of every loop run to keep recurring agent work affordable, bounded, and easy to audit.

## When To Use

- Before a scheduled or manual loop run starts.
- Before spawning a sub-agent, using a stronger model, or expanding scope.
- After a loop run finishes, fails, or pauses for human review.
- When the loop state shows repeated attempts, unclear ownership, or budget exhaustion.

## Rules

- Read `.agent/loops/loop-budget.md` before doing substantive work.
- Identify pattern, readiness level, cadence, daily cap, max attempts, and sub-agent allowance.
- If the watchlist is empty, use an early exit and write only a short report.
- If max attempts are reached for an item, stop and request human escalation.
- Do not spawn sub-agents when the budget says zero.
- Use cheap models for inventory, checklist expansion, and state pruning.
- Escalate to a stronger model only for high-risk interpretation, ambiguous failures, or release/security verdicts.

## Checks

- Verify the current loop pattern and readiness level match the manifest.
- Check whether the cadence would exceed the daily or weekly run budget.
- Validate that token estimates, attempt counts, and escalation decisions are recorded.
- Audit whether a cheaper model can finish the current step before using a stronger model.

## Safety

- Do not hide budget exhaustion by truncating unresolved risks.
- Do not store secrets, credentials, raw logs, or private user data in budget files.
- Preserve previous budget evidence unless it is clearly obsolete.
- Stop on conflicting budget rules and ask for human approval before continuing.

## Output Format

```markdown
## Loop Budget Check

Budget status: PASS|WARN|STOP
Pattern: <name>
Readiness: <L0-L3>
Daily cap: <value or unknown>
Estimated run cost: <value or unknown>
Max attempts respected: yes|no
Sub-agent budget respected: yes|no
Model route: cheap|strong|human-gate
Early exit required: yes|no
Action: continue|report-only|pause|human-gate
Evidence: <files or commands checked>
```

## Example

If `.agent/loops/loop-budget.md` says max attempts are `2` and the current item already failed twice, output `STOP`, preserve the item in state, and ask a human whether to drop, re-scope, or assign a stronger verifier.
