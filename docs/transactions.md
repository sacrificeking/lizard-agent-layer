# Target Transactions

Apply operations use `scripts/Lizard.Transaction.psm1` to make multi-file target changes deterministic and recoverable.

## Contract

- One writer acquires `.lizard-agent-layer.lock` with an atomic create operation.
- Each create or replacement is recorded in a write-ahead journal before the target changes.
- Existing files are copied to transaction-local backups and verified by SHA-256 during rollback.
- Lock and journal v2 bind the operation ID, operation name, canonical target root, target-root identity, owner PID, and start timestamp.
- Runtime validation rejects unknown fields, unsafe/control-plane mutation paths, non-canonical backup paths, invalid state transitions, and non-contiguous or reordered mutation sequences before recovery mutates the target.
- Installer preflight validates the complete adapter and destination plan before lock acquisition.
- Install, update, update history, loop init, loop sync, and verifier target writes use the same mutation wrappers.
- A successful operation removes its lock and transaction store. A handled failure replays a descending copy of the chronological mutation ledger and restores the prior tree.
- Each successful rollback mutation is marked `rolled-back` and persisted immediately. A retry skips that highest-sequence suffix and stops at the first new rollback error.

The transaction guarantees deterministic rollback across the supported mutation set. It does not claim that an arbitrary multi-file operation is one operating-system-level atomic rename.

## Recovery

An interrupted process leaves `.lizard-agent-layer.lock` and `.lizard-agent-layer-transactions/<operation-id>/journal.json` in the target.

Preview recovery validates the complete lock/journal identity and preflights every remaining file backup with protected existence and SHA-256 checks before reporting recovery available:

```powershell
pwsh -NoProfile -File .\scripts\transaction-recover.ps1 -TargetPath <project>
```

Apply rollback after confirming the recorded owner process is no longer active:

```powershell
pwsh -NoProfile -File .\scripts\transaction-recover.ps1 -TargetPath <project> -Apply -HumanApproved
```

`-Force` is required if the recorded PID is still running. Use it only after verifying that the PID is unrelated or the original operation cannot complete.

If preview reports `COMMITTED_CLEANUP_AVAILABLE` or `ROLLED_BACK_CLEANUP_AVAILABLE`, apply performs metadata cleanup only. It never rolls back committed target content. `-Action Rollback` and `-Action Cleanup` can enforce the expected classification; the default `-Action Auto` uses the validated journal state.

Journal v1 is intentionally rejected rather than guessed or silently rewritten. An interrupted target carrying v1 metadata requires manual evidence review with the lock, journal, backups, and affected paths preserved. Clean targets require no migration because successful operations remove transaction metadata.

The v2 journal is a structural and replay-safety boundary, not an authenticity proof. A writer already able to modify target-local control metadata could forge internally consistent journal data and unkeyed hashes. That trust-boundary limitation remains tracked under H-09. Name-based filesystem operations also retain the race limitations documented in the safety model.

## Stable failures

- `TRANSACTION_LOCK_HELD`: another operation owns the target.
- `TRANSACTION_JOURNAL_MISSING` or `TRANSACTION_JOURNAL_INVALID`: recovery evidence is incomplete.
- `TRANSACTION_JOURNAL_SCHEMA_UNSUPPORTED`: legacy or future evidence cannot be recovered by this reader.
- `TRANSACTION_LOCK_JOURNAL_MISMATCH`: the operation identities disagree; retain all evidence and stop.
- `TRANSACTION_BACKUP_PATH_INVALID`, `TRANSACTION_BACKUP_MISSING`, or `TRANSACTION_BACKUP_HASH_MISMATCH`: the next required backup is unsafe or unusable.
- `TRANSACTION_ROLLBACK_FAILED`: the next reverse-order mutation could not be restored; no lower sequence is attempted. Retain the journal, repair the named mutation, and retry.
- `TRANSACTION_JOURNAL_ATOMIC_WRITE_FAILED`: rollback progress could not be durably replaced; preserve evidence and retry only after correcting the filesystem problem.
- `TRANSACTION_FAULT_INJECTED`: test-only failure injection proved the rollback path.
