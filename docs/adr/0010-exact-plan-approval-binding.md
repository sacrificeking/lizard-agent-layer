# ADR 0010: Exact Plan Approval Binding

- Status: accepted
- Date: 2026-08-01

## Context

The earlier Markdown install and update reports were review aids, but `-Apply` recomputed a fresh operation without proving that its target, options, source bytes, target preconditions, or merge decisions were the ones a human reviewed.

## Decision

Install and update previews emit an immutable canonical JSON operation plan and a convenience SHA-256 sidecar. Apply requires the canonical plan path, the independently retained lowercase SHA-256, and `-HumanApproved`. The sidecar is never trusted automatically.

The canonical intent binds the logical target root, layer root and version, effective options, consumed source and target input hashes, planned target actions and preconditions, expiry, and—during update—the exact nested install plan. Apply validates the approved bytes and current bindings before acquiring the target lock, then revalidates critical bindings after acquiring the lock and before the first target mutation.

Plan JSON uses ordinal key ordering, invariant scalar encoding, UTF-8 without BOM, strict schemas, and no unknown properties. Unsupported versions and edited, expired, noncanonical, mismatched, or wrong-operation plans fail with stable `PLAN_BINDING_*` codes.

Applied plan IDs and digests are recorded in the install manifest and update history. Authentication of approver identity is outside this local digest contract and remains a separate trust concern.

## Consequences

This is intentionally breaking for direct `install.ps1 -Apply` and `update-target.ps1 -Apply` callers. Existing installed targets require no data rewrite, but legacy Markdown plans cannot authorize mutation. A fresh canonical preview is required after any relevant source, option, target, overlay, inventory, runtime, or manifest change.

The target-root identity remains logical and path-based. Mount-aware and handle-bound physical containment remain governed by ADR 0002 and the open H-03 work.
