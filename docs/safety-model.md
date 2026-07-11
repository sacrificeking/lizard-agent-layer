# Safety Model

The layer is built around conservative filesystem and workflow behavior.

## Installer safety

- Preview mode is the default.
- Existing files are skipped unless `-Force` is passed.
- Existing harness instruction files receive sidecar merge files instead of being overwritten.
- Apply mode writes an ownership manifest to `.agent/lizard-agent-layer.install.json`.
- Every destination is checked against an explicit authorized root immediately before mutation.
- Existing symlinks, junctions, and other reparse points in a destination ancestry are rejected by default.
- Textual relative-path checks are never treated as proof of resolved filesystem containment.

## Filesystem boundaries

`scripts/Lizard.SafeFs.psm1` is the shared enforcement layer for target and report writes. It normalizes roots and destinations, rejects root equality unless explicitly allowed, inspects existing ancestors, and emits stable `SAFEFS_*` rejection codes.

Target writes are authorized only beneath the selected target root. Report writes use a separate report root. Preview reports remain outside the target by default; commands that expose `-AllowTargetReportWrite` require that explicit opt-in for compatibility use cases.

The guard is intentionally conservative: a target root or destination ancestry containing a link is rejected instead of followed. This keeps force modes from widening the filesystem boundary.

## Ownership and integrity

Manifest v3 records each managed artifact separately. Layer-owned and adopted files carry source, installed, and current SHA-256 hashes; user-owned files are visible in the contract but are not claimed as generated content.

`-ForceManaged` is evidence-based. It may refresh an unchanged layer-owned artifact, but it preserves user-owned, adopted, locally modified, legacy-ambiguous, and integrity-unknown files. Schema v2 migration defaults ambiguous paths to user-owned.

Strict manifest checks fail on missing identities, content changes, source drift, incomplete mirrors, or adapter identity mismatches. A legacy manifest can report only `integrity-unknown`, never a strict pass.

## Transactions and recovery

Apply operations acquire a per-target lock and journal every target mutation before it occurs. Replacements receive SHA-256-verified backups. Install, update, update history, loop init, loop sync, and verifier writes commit through the shared transaction module or replay the journal in reverse.

Interrupted operations remain locked and recoverable through `scripts/transaction-recover.ps1`. See [Target Transactions](transactions.md) for the exact guarantees and recovery workflow.

## Harness safety

- Adapters are declarative manifests under `adapters/<name>/adapter.json`.
- Adapters may mirror skills into harness-specific folders.
- Duplicate or overlapping destinations fail before mutation unless instruction adapters declare a shared compatibility group with unique precedence.
- Generic `AGENTS.md` is intended for tools without a dedicated adapter, not as a default companion to Codex.

## Target-project safety

- Project-local instructions remain authoritative.
- Pre-existing project files remain user-owned. Files created by the layer remain layer-owned until explicitly adopted or locally modified.
- Raw logs and generated dashboards are private by default.
- L2 worktrees must be outside the target root; creation, verification, and cleanup share one hashed lifecycle identity.
- L2 verdicts bind reviewer role, HEAD, final Git state, command exits, command-output hashes, and evidence-file hashes. Changed or tampered evidence fails closed.
- L2 remains assisted: verifier PASS is a decision packet for human merge review, never merge permission.

## High-risk workflows

Remote push, deployment, dependency installation, CI changes, secret changes, and remote database migrations require explicit human approval.
