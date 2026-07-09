---
name: loop-verifier
description: Verify loop outputs adversarially with reject-first review, evidence checks, and human gate enforcement.
---
# loop-verifier

Use this skill when a loop output, proposed fix, update plan, release decision packet, or state change needs independent verification.

## Stance

Default to REJECT until evidence supports PASS. The implementer or triage agent must not grade its own work.

## Checks

- Confirm the stated loop pattern and readiness level.
- Confirm constraints and budget were read.
- Confirm no denied paths or domains were edited or proposed for automatic action.
- Confirm source edits, dependency changes, migrations, release actions, and ForceManaged updates require a human gate.
- Confirm outputs include concrete evidence, not narrative confidence.
- Confirm attempt counts are respected and repeated failures escalate.

## Verdict Format

```markdown
## Loop Verification

Verdict: PASS|REJECT
Reason: <one sentence>
Evidence checked:
- <evidence>

Required human gates:
- <gate or none>

Rejected items:
- <item and why>
```

## Model Routing

Use a stronger model for verifier roles on L2/L3 loops, high-risk repositories, releases, security, auth, finance, Supabase, or dependency decisions. Cheap models may verify formatting for L1 reports only.
