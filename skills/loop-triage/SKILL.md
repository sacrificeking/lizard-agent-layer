---
name: loop-triage
description: Run report-only loop triage with structured findings, state updates, early exit, and human escalation rules.
---
# loop-triage

Use this skill when a loop needs to inspect a project, update loop state, and produce a concise report without modifying source code.

## Inputs

- `.agent/loops/LOOP.md`
- `.agent/loops/loop-state.md` or the pattern-specific state file
- `.agent/loops/loop-constraints.md`
- recent git status, CI summaries, issue summaries, or user-provided findings

## Rules

- Default to L1 report-only.
- Do not edit source code, dependencies, migrations, secrets, auth, finance logic, or production infrastructure.
- Read existing state before producing new findings.
- Prune resolved or stale items when evidence is clear.
- Record attempt counts and escalate after three failed attempts.
- If there are no actionable items, write an early-exit summary and stop.

## Output Format

Return these sections exactly:

```markdown
## Loop Triage

Mode: L1 report-only
Pattern: <pattern-name>
State read: yes|no
Constraints read: yes|no

### High Priority
- <id> | <one-line finding> | Suggested action: <human action or next loop action>

### Watch List
- <id> | <one-line finding> | Recheck: <condition>

### Waiting On Human
- <id> | <decision needed> | Blocking reason: <reason>

### Resolved Or Pruned
- <id> | <why it was removed>

### Run Log Entry
- <timestamp> | pattern: <name> | items: <n> | actions: 0 | escalations: <n> | outcome: <summary>
```

## Model Routing

Cheap models may run inventory, classification, and state pruning. Use a stronger model when findings touch security, auth, finance, Supabase migrations, release readiness, or cross-module architecture.
