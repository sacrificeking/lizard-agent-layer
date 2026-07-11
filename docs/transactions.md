# Target Transactions

Apply operations use `scripts/Lizard.Transaction.psm1` to make multi-file target changes deterministic and recoverable.

## Contract

- One writer acquires `.lizard-agent-layer.lock` with an atomic create operation.
- Each create or replacement is recorded in a write-ahead journal before the target changes.
- Existing files are copied to transaction-local backups and verified by SHA-256 during rollback.
- Installer preflight validates the complete adapter and destination plan before lock acquisition.
- Install, update, update history, loop init, loop sync, and verifier target writes use the same mutation wrappers.
- A successful operation removes its lock and transaction store. A handled failure replays mutations in reverse and restores the prior tree.

The transaction guarantees deterministic rollback across the supported mutation set. It does not claim that an arbitrary multi-file operation is one operating-system-level atomic rename.

## Recovery

An interrupted process leaves `.lizard-agent-layer.lock` and `.lizard-agent-layer-transactions/<operation-id>/journal.json` in the target.

Preview recovery:

```powershell
pwsh -NoProfile -File .\scripts\transaction-recover.ps1 -TargetPath <project>
```

Apply rollback after confirming the recorded owner process is no longer active:

```powershell
pwsh -NoProfile -File .\scripts\transaction-recover.ps1 -TargetPath <project> -Apply -HumanApproved
```

`-Force` is required if the recorded PID is still running. Use it only after verifying that the PID is unrelated or the original operation cannot complete.

## Stable failures

- `TRANSACTION_LOCK_HELD`: another operation owns the target.
- `TRANSACTION_JOURNAL_MISSING` or `TRANSACTION_JOURNAL_INVALID`: recovery evidence is incomplete.
- `TRANSACTION_ROLLBACK_FAILED`: one or more backups could not be restored; retain the journal and repair before another apply.
- `TRANSACTION_FAULT_INJECTED`: test-only failure injection proved the rollback path.
