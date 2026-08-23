# ADR 0016: Regulated data defaults to human review

## Status

Accepted for incremental implementation on 2026-08-22.

## Context

The staged routing policy includes `regulated` in ordinary technical routes. Previously, a caller had to supply a separate escalation signal to stop those routes. Inventory fields such as `approved` only describe technical model eligibility and cannot establish an organization's provider, legal, privacy, residency, purpose, or runtime approval.

The repository does not yet have an authenticated organization trust root, signed approval issuer, revocation source, or replay-resistant runtime evidence. A target-local JSON document is controlled by the target and therefore cannot act as organization-owned authority.

## Decision

`DataClass=regulated` is an authoritative core-router gate. It returns `human-review` before signal processing, route selection, inventory loading, or model recommendation unless a future authenticated approval implementation satisfies the complete organization-owned contract.

The current implementation intentionally has no positive automatic-routing exception. `schemas/regulated-data-approval.schema.json` defines only the structural fields a future approval envelope must bind: organization and approval identities, approver and decision reference, validity, provider, model, harness, purpose, data class, region, runtime fingerprint, phases, and risks. Schema validity alone is never authorization.

Installed policy must declare the same fail-closed default. Doctor rejects a policy that weakens the default or treats target-local approval as sufficient. Route receipts expose stable `reason_codes` separately from explanatory prose.

A positive exception may be added only with a superseding or extending decision that also defines authenticated issuer trust, signature verification, external revocation, runtime attestation, freshness, replay protection, and consumer validation. `inherit-current` cannot qualify because provider, model, and runtime identity are not attestable.

## Consequences

- Missing, target-local, caller-asserted, stale, or otherwise unauthenticated approval cannot route regulated data automatically.
- Caller signals, attempt counts, available-model lists, and inventory eligibility cannot bypass the gate.
- The repository provides a conservative containment control, not a legal conclusion, compliance certification, or organization approval.
- H-06 remains open for full assurance until the authenticated WP-10 trust boundary, mismatch/revocation matrix, and supported-host evidence exist.
