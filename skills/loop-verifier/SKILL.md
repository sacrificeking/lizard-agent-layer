---
name: loop-verifier
description: Independently verify loop outputs, assisted fixes, worktree changes, update plans, and release packets using reject-first review, immutable repository evidence, role separation, and human gates.
---
# loop-verifier

Use this skill when a loop output, proposed fix, update plan, release decision packet, or state change needs independent verification.

## Stance

Default to REJECT until evidence supports PASS. The implementer or triage agent must not grade its own work.

For L2/L3 work, require the lifecycle contract produced by `scripts/loop-worktree.ps1`. Run checks through `scripts/loop-verify.ps1`; do not construct PASS packets manually.

## Checks

- Confirm the stated loop pattern and readiness level.
- Confirm constraints and budget were read.
- Confirm no denied paths or domains were edited or proposed for automatic action.
- Confirm source edits, dependency changes, migrations, release actions, and ForceManaged updates require a human gate.
- Confirm outputs include concrete evidence, not narrative confidence.
- Bind the verdict to operation ID, lifecycle hash, HEAD SHA, final git-state hash, command exit codes, output hashes, and supplied evidence-file hashes.
- Reject a changed or tampered lifecycle, wrong repository or branch, detached HEAD, stale worktree state, missing command evidence, or identical implementer/verifier identities.
- Confirm attempt counts are respected and repeated failures escalate.

Use `NEEDS_REVIEW` only as a non-verdict packet. `PASS`, `WARN`, and `FAIL` require a named implementer, a distinct verifier, and at least one verification command. A PASS or WARN requires every command to exit successfully.

## Verdict Format

```markdown
## Loop Verification

Verdict: PASS|WARN|FAIL|NEEDS_REVIEW
Reason: <one sentence>
Evidence checked:
- Lifecycle operation/hash: <id>/<sha256>
- Reviewed HEAD/state: <sha>/<sha256>
- Commands and evidence files: <exit codes and hashes>

Required human gates:
- <gate or none>

Rejected or warned items:
- <item and why>
```

## Model Routing

Use a stronger model for verifier roles on L2/L3 loops, high-risk repositories, releases, security, auth, finance, Supabase, or dependency decisions. Cheap models may verify formatting for L1 reports only.
