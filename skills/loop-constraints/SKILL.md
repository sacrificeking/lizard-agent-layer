---
name: loop-constraints
description: Use when a loop must enforce denylist paths, allowlisted actions, human gates, secrets policy, and report-only defaults.
---
# loop-constraints

Use this skill before a loop proposes, verifies, or performs any action. The constraints file is authoritative for safety.

## When To Use

- Before turning a finding into a proposed action.
- Before any write, dependency change, release step, migration, deploy, or generated patch.
- When a loop touches auth, security, precision calculations, databases, production data, permissions, or secrets.
- When the planned action is ambiguous or not explicitly allowlisted.

## Required Reads

- `.agent/loops/loop-constraints.md`
- `.agent/loops/LOOP.md`
- `.agent/loops/lizard-agent-layer.loop-install.json`
- Current planned action, file list, command list, or diff summary

## Strict Rules

- Default mode is report-only unless a human explicitly approves a higher readiness level.
- The loop NEVER auto-merges to `main` or `master`.
- The loop NEVER force-pushes.
- The loop NEVER modifies `.agent/loops/` during a run.
- The loop NEVER runs tests with side effects on production systems.
- Auth, security, precision calculations, database migrations, production infrastructure, dependencies, tags, pushes, releases, and deploys require human approval.
- Auto-merge and unattended release actions are forbidden unless a future L2/L3 policy explicitly allows them.
- If proposed action scope expands, re-run this skill before continuing.

## Checks

- Verify that every touched path is outside the denylist or has explicit approval.
- Verify that the action appears in `allowedActions` for the active pattern.
- Audit whether `human_review_before_write` or `human_review_before_release` applies.
- Check that rollback or no-op behavior is clear before any assisted fix is proposed.
- Use `git status --porcelain` to verify only expected paths changed.
- Use `git diff --stat` to verify change size is within minimal-fix bounds.
- Check that no files matching secret patterns (`.env*`, `*.pem`, `*.key`) were created or modified.
- Verify worktree was cleanly removed after L2 operations.

## Safety

- Do not edit secrets, credentials, tokens, production state, or migration files from a loop without explicit human approval.
- Preserve unrelated local work and project-specific instructions.
- Stop on conflicting constraints instead of choosing the more permissive rule.
- Record the reason for every human gate in the loop run log.

## Output Format

```markdown
## Loop Constraints Check

Status: PASS|HUMAN-GATE|STOP
Default mode: <mode>
Pattern: <name>
Denied path touched: yes|no
Unlisted action: yes|no
Human gate required: yes|no
Reason: <reason>
Allowed next action: <report-only action or explicit human decision>
Evidence: <files or commands checked>
```

## Example: Release Loop Gating

If a release loop finds that database migration files changed, output `HUMAN-GATE`, cite the migration path, and allow only a readiness report until the human approves the release path.
