# ADR 0015: Effective memory modes

## Status

Accepted for incremental implementation on 2026-08-22.

## Context

Profiles and installation guidance advertised `curated`, `private-episodic`, and `off`, while the installer always created curated memory files and adapters always referenced them. A declared `off` value therefore did not disable persistence. Mode changes also need to preserve the ownership and exact-plan guarantees introduced by manifest schema v4 and the transactional uninstall lifecycle.

## Decision

The effective memory mode is selected by an explicit command option, otherwise by the existing install manifest, and only for a fresh target by the selected profile. Install, update, upgrade, canonical plans, manifests, update history, doctor, manifest diff, uninstall plans, and uninstall receipts bind the same effective value.

Installed harness instructions are mode-neutral and consult `.agent/protocols/project-context.md`. The installer selects a static mode-specific project-context contract, memory policy, gitignore source, and exact memory artifact set:

- `curated` installs preferences, decisions, lessons, and working handoff artifacts.
- `private-episodic` installs the curated set plus a managed, recursively ignored episodic seed and its private policy.
- `off` installs no `.agent/memory` namespace or memory policy and permits no operational `.agent/memory` reference in active managed instructions.

Mode transitions are explicit canonical-plan operations. A transition may automatically remove only unchanged `layer-owned` files and directories selected by the old mode. Every removal binds kind, file hash where applicable, and physical object identity. Apply rechecks the complete physical set before the first mutation and rechecks each object immediately before transactional removal. Unknown, linked, adopted, user-owned, modified, reappeared, or wrong-kind content blocks the transition without changing the previous manifest mode. Files are removed before empty directories, and rollback restores exact bytes after an interruption.

Successfully removed memory records remain as non-executable `removed`/`missing` tombstones. This preserves ownership continuity and detects paths that reappear while `off`; it is historical evidence, not an active memory reference or update residue. Reactivation converts the same identities back to active artifacts through a fresh exact plan.

## Consequences

- Manifest schema v4 now requires `memory_mode`; older schema-v4 writers that omitted it must be upgraded before strict lifecycle operations.
- `off` is a physical and operational postcondition, enforced by the installer and doctor rather than a documentation hint.
- Switching away from private episodic mode requires users to export or move any changed or additional episodic content first.
- Mode transitions replace only unchanged layer-owned mode-contract files automatically; unrelated no-clobber behavior is unchanged.
- Native PowerShell 7, Ubuntu, and macOS execution evidence remains required before the audit finding is closed across supported hosts.
