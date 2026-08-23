# ADR 0023: Records Retention, Legal Hold, and Cryptographic Deletion Lifecycle

- Status: Accepted
- Date: 2026-08-22
- Extends: ADR 0006, ADR 0007, ADR 0010, ADR 0014, and ADR 0017

## Context

Target repositories accumulate durable records across memory files, routing decisions, execution receipts, update histories, loop runtime events, and loop run logs. Without an explicit, verifiable lifecycle, durable data risks indefinite retention, uncontrolled privacy exposure, or uncoordinated deletion that violates legal hold requirements or lacks verifiable audit trails.

## Decision

Records lifecycle management is governed by explicit retention policies, cryptographic legal holds, and preview-first transactional operations through ecords-lifecycle.ps1:

1. **Typed Artifact Classes**: Records are categorized into discrete classes: memory, outing-decision, outing-execution, update-history, loop-events, and loop-run-log.
2. **Deterministic Retention Policies**: Policies declare maximum and minimum TTLs per artifact class, sensitivity thresholds, and required actions (inventory, export, purge).
3. **Cryptographic Legal Holds**: Holds are asserted through signed envelopes (ecords-hold.schema.json, ecords-hold-payload.schema.json) bound to an authorized owner, trusted public key, and active validity window. A hold strictly overrides normal retention expiration and prevents purge operations for its matched scope (ll, classes, or ecords).
4. **Exact-Plan Bound Operations**:
   - Inventory evaluates current artifacts against the active retention policy and active holds, producing deterministic status classifications (ctive, expired, held, unmanaged).
   - Export creates an outside-target archive verified by content hashes before deletion is authorized.
   - Purge requires an approved canonical operation plan, independently supplied SHA-256, and explicit human approval (-HumanApproved). Purge mutations use handle-bound SafeFs transactions, delete records in descending sequence, and write a machine-readable deletion receipt (ecords-deletion-receipt.schema.json) outside the target.
5. **Fail-Closed Guarantees**: Any tampered hold, invalid signature, unverified export, modified artifact, or concurrent hold collision halts execution and rolls back all purge actions.

## Consequences

- Target repositories gain auditable compliance for GDPR/enterprise retention mandates with verifiable deletion evidence.
- Purge operations are completely reversible prior to final commit and idempotent on repeat.
- Deletion receipts provide immutable audit records containing artifact IDs, hashes, timestamps, and active policy references without leaking sensitive contents.
