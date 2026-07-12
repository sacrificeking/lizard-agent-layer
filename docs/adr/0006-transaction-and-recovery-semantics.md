# ADR 0006: Transaction And Recovery Semantics

- Status: Accepted
- Date: 2026-07-12

## Context

Multi-file target operations can be interrupted after partial mutation or overlap with another writer.

## Decision

Apply workflows acquire one target lock, persist a write-ahead journal, hash backups, and mutate only through transaction wrappers. Handled failures roll back in reverse order. Interrupted operations retain the lock and journal for explicit preview-first recovery. Recovery never claims operating-system-level atomicity beyond the supported mutation sequence.

## Consequences

Concurrent writers fail closed. Operators must retain incomplete journals until recovery succeeds and use `-Force` only after verifying recorded process ownership.
