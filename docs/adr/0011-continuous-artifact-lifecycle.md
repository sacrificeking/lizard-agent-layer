# ADR 0011: Continuous Artifact Lifecycle

- Status: Accepted
- Date: 2026-08-08
- Supersedes in part: ADR 0003 for lifecycle retention

## Context

Manifest schema v3 records exact per-artifact ownership and content identity, but a later install serializes only the currently selected profile, packs, skills, and harnesses. Contract reduction can therefore leave an artifact on disk while dropping the record that proves its origin and last installed hash.

## Decision

Manifest schema v4 adds an explicit lifecycle to every artifact: `active`, `retired-present`, `retired-missing`, or `removed`.

Current selections are written as `active`. Previously recorded artifacts that are no longer selected are carried forward as `retired-present` or `retired-missing`, retain their ownership and historical identity, and are bound into canonical plans as preserve-only targets. Contract reduction never deletes retired content. A later selection may reactivate the same record. `removed` is reserved for the separately approved transactional uninstall lifecycle.

Schema-v3 records are read as active and migrate conservatively on the next approved apply. Schema-v4 manifests require a v4-aware reader because older readers would treat retired records as currently required artifacts.

## Consequences

- Profile, pack, skill, and harness contraction remains reversible and does not erase ownership evidence.
- Doctor and manifest diff validate lifecycle consistency and do not mistake an intentionally absent retired artifact for an active missing artifact.
- Uninstall remains out of scope until WP-05; no WP-04 operation deletes target content.
