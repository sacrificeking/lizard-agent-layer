# ADR 0022: Versioned Skill Packages and Conservative Lifecycle

- Status: Accepted
- Date: 2026-08-22
- Extends: ADR 0010 and ADR 0011

## Context

Skills previously consisted primarily of `SKILL.md` plus optional supporting files. The installer could copy and track those files, but a package did not declare its own version, compatibility, dependency, permission, conflict, migration, disablement, recovery, provenance, or removal contract. Updating an individual skill independently therefore had no complete, executable lifecycle.

## Decision

Every repository skill is a package with two separate contracts:

- `SKILL.md` remains the harness-facing instruction document with only `name` and `description` in its frontmatter.
- `skill.json` is machine-facing package metadata governed by `skill-package.schema.json` and strict runtime validation.

Package metadata declares a stable semantic version, minimum layer version, supported hosts and harnesses, dependencies, maximum permissions, provenance review, conflicts, allowed migration sources, and conservative disable/recovery/removal semantics. Repository validation checks every package and the complete dependency graph. Installation copies the metadata to the primary skill store and every selected mirror; `_manifest.jsonl` binds name, version, metadata hash, dependencies, and permissions. Doctor revalidates installed metadata, hashes, dependency versions, and conflicts.

`skill-lifecycle.ps1` supports `Validate`, `Install`, `Update`, `Migrate`, `Disable`, `Recover`, and `Remove`. Mutating actions are preview-first and require a canonical external operation plan, an independently supplied SHA-256, and explicit human approval. The plan binds source files, target preconditions, physical identities for removal, target-root identity, package version, and prior state. Apply revalidates the complete binding after acquiring the transaction lock and before its first mutation.

Only unchanged, state-recorded, layer-owned package content may be replaced or removed. Unknown or modified content fails closed. Disable retains exact recovery hashes; recover requires the same reviewed source version and hashes; remove retains a non-executable ownership tombstone. Every apply is transactional and rollback is mandatory on failure.

## Consequences

- Package evolution is explicit and independently testable without changing installer core behavior for each skill.
- Existing unversioned skill manifests require a new approved install/update before strict Doctor accepts the versioned manifest.
- A disabled package can be recovered only while its exact reviewed source remains available. A changed source requires a declared migration or a separately reviewed install.
- Runtime schema execution and native supported-host evidence remain release gates; local structural/runtime validation does not claim those gates.
