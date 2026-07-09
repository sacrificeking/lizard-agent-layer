---
name: ci-triage
description: Classify CI failures for loop reports without modifying code, retrying flakes blindly, or hiding root causes.
---
# ci-triage

Use this skill when a loop reviews CI failures, build logs, test output, or lint failures.

## Classification

Classify each failure as one of:

- regression
- flake
- environment
- dependency
- configuration
- unknown

## Rules

- Do not edit code in L1 mode.
- Do not treat flakes as application bugs.
- Do not disable tests, increase timeouts blindly, or hide failing checks.
- Record job name, commit SHA, failing step, first failing assertion, and suggested human action.
- Escalate after three failed fix attempts on the same item.

## Output Format

```markdown
## CI Triage

Job: <job>
Commit: <sha or unknown>
Classification: regression|flake|environment|dependency|configuration|unknown
Evidence:
- <log excerpt summary>
Suggested loop action: report-only|open worktree after approval|human-gate
Human gate: <reason or none>
```
