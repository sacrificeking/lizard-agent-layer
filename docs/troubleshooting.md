# Troubleshooting And Recovery

Use preview commands first. Preserve `.lizard-agent-layer.lock`, `.lizard-agent-layer-transactions/`, lifecycle envelopes, verifier evidence, and generated reports until recovery is complete.

## Install Or Update Interrupted

Symptom: `.lizard-agent-layer.lock` remains, or a later apply reports `TRANSACTION_LOCK_HELD`.

```powershell
pwsh -NoProfile -File .\scripts\transaction-recover.ps1 -TargetPath <project>
```

If status is `RECOVERY_AVAILABLE`, confirm the recorded process is no longer the active writer, then run:

```powershell
pwsh -NoProfile -File .\scripts\transaction-recover.ps1 -TargetPath <project> -Apply -HumanApproved
```

- `TRANSACTION_JOURNAL_MISSING` / `TRANSACTION_JOURNAL_INVALID`: keep the lock and transaction directory; do not start another apply. Recover the journal from backup or inspect affected paths manually.
- `TRANSACTION_ROLLBACK_FAILED`: retain every backup and journal, repair the named mutation, then rerun preview recovery.
- Use `-Force` only after proving the recorded PID is stale or unrelated.

## Manifest Or Version Gate Stops

- `MANIFEST_SCHEMA_UNSUPPORTED`: update through a reader that supports the installed schema or restore a supported manifest backup.
- `MANIFEST_READER_TOO_OLD`: upgrade this layer before touching the target.
- `DOWNGRADE_APPROVAL_REQUIRED`: review the update plan, then use `-AllowDowngrade -HumanApproved` only when the downgrade is intentional.
- `integrity-unknown`: do not force-refresh ambiguous files; run `manifest-diff.ps1` and review ownership.

```powershell
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath <project> -Strict
```

## Worktree Or Verifier Stops

- Nested/equal worktree rejected: choose a sibling path outside the target.
- Detached HEAD or branch mismatch: restore the lifecycle branch before verification.
- `EVIDENCE_HASH_MISMATCH`: discard the tampered report and regenerate from the original lifecycle envelope.
- Stale verifier evidence: rerun verification after the final worktree change.
- `SELF_VERIFICATION_FORBIDDEN`: assign a distinct verifier identity.
- Cleanup rejected: pass the same `-LifecyclePath` used for creation and verification.

Never merge automatically. The human decision remains merge, revise, discard, or pause.

## Loop Runtime Stops

Inspect authoritative state without mutation:

```powershell
pwsh -NoProfile -File .\scripts\loop-run.ps1 -TargetPath <project> -Action Status -Json
```

- `LOOP_LEASE_HELD`: another non-expired run owns the target. Do not start a duplicate.
- `LOOP_LEASE_STALE_RECOVERY_REQUIRED`: preview `loop-recover.ps1`, verify the recorded owner is no longer active, then use `-Apply -HumanApproved`.
- `LOOP_RUN_DUPLICATE`: choose a new stable RunId; completed and failed IDs are never reusable.
- `LOOP_RUN_BUDGET_EXHAUSTED` / `LOOP_TOKEN_BUDGET_EXHAUSTED`: keep the runtime paused until the UTC budget window resets or a human reviews the machine-readable budget.
- `LOOP_ATTEMPT_BUDGET_EXHAUSTED`: stop retrying the item and resolve or re-scope it with a human.
- `LOOP_EVENT_HASH_MISMATCH` / `LOOP_EVENT_CHAIN_BROKEN` / `LOOP_EVENT_STATE_DIVERGED`: preserve all runtime files and restore the last trusted state/event set; never truncate or rewrite the event log to bypass the failure.
- `LOOP_VERIFIER_REQUIRED` / `LOOP_VERIFIER_REJECTED`: L2 cannot complete until `loop-verify.ps1` produced PASS evidence for the same operation and target.
- `LOOP_RUNTIME_NOT_INITIALIZED`: preview and apply `loop-sync.ps1` once with the current layer. Sync creates missing runtime files but does not replace existing runtime state.

## Schema Validator Missing

`SCHEMA_VALIDATOR_NODE_MISSING` requires Node.js 22 or newer. `SCHEMA_VALIDATOR_DEPENDENCY_MISSING` requires:

```powershell
npm ci
pwsh -NoProfile -File .\scripts\validate.ps1
```

## Contract Governance Stops

When `contract-check.ps1` reports a missing declaration:

1. Identify the impacted contract in `registry/contracts.json`.
2. Link its ADR from a new `changes/<date>-<id>.json`.
3. State migration disposition and compatibility impact.
4. Add or update executable fixtures for changed invariants.
5. Run schema, contract, focused, drift, quality, smoke, and matrix gates.
