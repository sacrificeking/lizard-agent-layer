---
name: minimal-fix
description: Use when a human-approved L2 assisted loop needs the smallest safe fix after constraints, isolation, verifier, and rollback checks pass.
---
# minimal-fix

Use this skill only for L2 assisted loops after L1 report-only signal has proven useful. It must not be used for default unattended changes.

## When To Use

- A human explicitly approved moving a specific loop item from report-only to assisted fix.
- The target file ownership, constraints, and rollback path are clear.
- The item is narrow enough to verify with existing tests, lint, build, or a focused manual check.
- A separate verifier is available and cannot be the same session as the implementer.

## Preconditions

- Human approval is recorded in the loop run log or current task instruction.
- Worktree isolation is available and unrelated local changes are preserved.
- Denylist and human gates were checked with `loop-constraints`.
- The target item has fewer than three failed attempts.
- The expected verification command or review checklist is known before editing.

## Procedure

- Restate the target item, intended files, denied paths, and rollback plan.
- Make the smallest possible diff that solves the approved item.
- Do not refactor unrelated code, rename public APIs, or expand the task scope.
- Run or request the narrowest useful verification: test, typecheck, lint, build, validate, audit, or review.
- Record changed files, verification evidence, residual risk, and next human decision.

## Checks

- Verify that the diff only touches the approved files.
- Check that no secrets, auth rules, finance-critical code, Supabase migrations, production infrastructure, dependencies, tags, pushes, releases, or deploys were touched without approval.
- Validate that rollback is possible from the current worktree state.
- Require a verifier review before considering the item done.

## Safety

- Do not use this skill for autonomous writes, broad cleanup, speculative refactors, or dependency upgrades.
- Preserve existing project style, tests, and unrelated user changes.
- Stop if verification fails twice or the fix requires a design decision.
- Escalate to human review when the smallest safe diff is no longer obvious.

## Output Format

```markdown
## Minimal Fix Plan

Mode: L2 assisted
Target item: <id>
Human approval: <where recorded>
Files expected: <list>
Denied paths touched: no
Verifier required: yes
Verification command: <command or checklist>
Human gate required: <yes/no and reason>
Rollback: <how to revert>
Residual risk: <none or list>
```

## Example

If a loop item asks for a missing docs link, the minimal fix may touch one Markdown file and run `scripts/validate.ps1`. If the fix requires changing release automation, stop and ask for a new human-approved scope.
