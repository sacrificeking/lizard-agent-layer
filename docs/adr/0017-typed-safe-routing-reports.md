# ADR 0017: Typed safe routing reports

## Status

Accepted for incremental implementation on 2026-08-22.

## Context

Route decisions persisted caller-supplied signal strings verbatim and execution receipts accepted a free-form evidence reference while both declared `raw_prompt_stored=false`. Path containment and gitignore rules limited exposure but did not make the metadata-only label true.

## Decision

Routing and execution receipts use one checked-in safe-report module. Caller signals are a closed set of policy IDs. Execution evidence references, model/provider/runtime identities, fingerprints, capabilities, roles, and attestation sources are bounded opaque ASCII identifiers rather than prose.

Every receipt carries typed `sensitivity`, `purpose`, `audience`, `retention_class`, `content_policy`, and `redaction` fields. The shared serializer recursively detects credential, private-key, personal-email, absolute-path, multiline, command, non-ASCII, and oversized-text canaries, replaces the complete value with a deterministic category marker, and records only the affected field paths. Console rendering uses the same string protection. Rejected identifiers produce stable errors that do not echo the rejected value.

`raw_prompt_stored=false` remains for compatibility, but is no longer the only privacy assertion: schemas reject free-form signal/evidence fields and require the typed content contract plus internally consistent redaction status.

## Consequences

- Existing callers must replace descriptive signals and evidence prose with enumerated or opaque IDs.
- Runtime `capability_source` becomes an opaque identifier; descriptive provenance belongs in a separately governed evidence system.
- These controls cover route and execution receipts and their immediate console/error/file channels. They do not yet prove that every unrelated report, transaction journal, or lifecycle artifact follows the same typed metadata contract.
- General retention, legal hold, authenticated evidence, and supported-host assurance remain separate work packages.
