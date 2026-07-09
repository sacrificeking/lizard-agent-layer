---
name: loop-state-sync
description: Use when a loop needs to refresh state files, prune resolved items, preserve attempts, and prevent stale or conflicting memory.
---
# loop-state-sync

Use this skill when a loop reads, updates, or verifies `.agent/loops/*state*.md` without losing important history.

## When To Use

- At the beginning of a loop run, before interpreting old state.
- At the end of a loop run, before writing next actions or resolved items.
- When two findings conflict, repeat, or appear stale.
- When a user asks to resume an interrupted loop.

## Rules

- Read the state file before writing anything.
- Preserve unresolved items unless evidence proves they are resolved.
- Keep attempt counts, owners, blockers, and last actions intact.
- Move stale but unresolved items to Watch List rather than deleting them.
- Move blocked items to Waiting On Human with a clear decision request.
- Keep state compact enough that older and cheaper models can read it in one pass.

## Checks

- Verify that every removed item has evidence in a command result, run log, or human decision.
- Validate that no item appears in both High Priority and Resolved Recently.
- Check attempt counts before proposing another retry.
- Audit that the next run has one clear starting point.

## Safety

- Never store secrets, credentials, raw private logs, or personal data in state.
- Do not overwrite user-authored context without preserving the decision trail.
- Avoid speculative memory; mark uncertain facts as needing review.
- Stop and ask for human approval if state conflicts with current repository evidence.

## Output Format

```markdown
## Loop State Sync

State file: <path>
Items pruned: <n>
Items added: <n>
Items escalated: <n>
Attempts preserved: yes|no
Conflicts: <none or list>
Next read requirement: read this file at the start of the next run
Evidence: <files or commands checked>
```

## Example

If a CI failure item is no longer present in the latest gate output, move it to Resolved Recently with the command checked. If the gate was not rerun, keep the item in Watch List instead of deleting it.
