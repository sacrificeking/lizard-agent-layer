# Safety Model

The layer is built around conservative filesystem and workflow behavior.

## Installer safety

- Preview mode is the default.
- Install and update apply require a canonical, independently digested, human-approved plan; Markdown and `.sha256` sidecars alone never authorize mutation.
- Existing files are skipped unless `-Force` is passed.
- Existing harness instruction files receive sidecar merge files instead of being overwritten.
- Apply mode writes an ownership manifest to `.agent/lizard-agent-layer.install.json`.
- Every destination is checked against an explicit authorized root immediately before mutation.
- Existing symlinks, junctions, and other reparse points in a destination ancestry are rejected by default.
- Textual relative-path checks are never treated as proof of resolved filesystem containment.

## Filesystem boundaries

`scripts/Lizard.SafeFs.psm1` is the shared enforcement layer for target and report writes. It normalizes roots and destinations, rejects root equality unless explicitly allowed, inspects existing ancestors, and emits stable `SAFEFS_*` rejection codes.

Target writes are authorized only beneath the selected target root. Report writes use a separate report root. Preview reports remain outside the target by default; commands that expose `-AllowTargetReportWrite` require that explicit opt-in for compatibility use cases.

The guard is intentionally conservative: a target root or destination ancestry containing a link is rejected instead of followed. On Unix, fresh mount identity is also compared for the authorized root and every destination component. Linux uses mount ID plus device identity so that same-device bind mounts and cross-device mounts both fail closed; macOS combines mounted-root enumeration with device identity. Missing or malformed identity evidence is a rejection, not a fallback. This keeps force modes from widening the filesystem boundary.

The sole host-alias normalization is for an internally selected temporary root on macOS: `/var` and its descendants are converted to their canonical `/private/var` spelling before SafeFs validation. The resulting root still passes the normal linked-ancestor and mount checks. This does not permit `/var`, `/tmp`, or any other linked spelling for user-selected targets, sources, plans, reports, or arbitrary paths.

Protected read consumers use the same authorized-root boundary. `Get-SafeContent`, `Get-SafeFileMetadata`, and `Get-SafeFileHash` open the source relative to held ancestor handles/descriptors, require an existing ordinary file, and reject linked or hard-linked terminal objects. Loop verifier evidence and Git-reported untracked-file evidence use these primitives instead of direct `Get-Content`, `Get-Item`, or `Get-FileHash` access.

SafeFs exposes an executable, root-specific capability document. Full assurance requires held ancestor handles/descriptors, terminal no-follow, physical file and volume/mount identity, atomic create-new and replacement, and relative deletion. Windows NTFS/ReFS uses parent-relative `NtCreateFile` and `NtSetInformationFile`. Linux uses `openat`, `statx`, `linkat`, `renameat`, and `unlinkat`; macOS uses the corresponding `*at` operations with `fstat`/`fstatfs`. Content is committed through a unique stage created relative to the held destination parent. Unsupported backends fail with `SAFEFS_HANDLE_MUTATION_UNAVAILABLE`; no SafeFs mutation helper falls back to the older name-based path.

This is not yet an H-03 closure. Windows PowerShell 5.1 behavior is locally verified for protected reads, writes, copies, initialization, transactions, plans, deletion, hard-link rejection, and synchronized ancestor swaps. The Unix interop source compiles and its ABI offsets were checked against the operating-system headers, but Ubuntu/macOS runtime evidence and executable schema validation remain pending. Built-in Git worktree creation, removal, and branch deletion fail closed with `SAFEFS_EXTERNAL_MUTATOR_UNBOUND`; a reviewed externally created clean worktree can be registered without repository mutation for the verifier lifecycle.

## Ownership and integrity

Manifest v4 records each managed artifact separately. Layer-owned and adopted files carry source, installed, and current SHA-256 hashes; user-owned files are visible in the contract but are not claimed as generated content. Deselected artifacts retain this evidence as `retired-present` or `retired-missing` and are never deleted by install or update.

`-ForceManaged` is evidence-based. It may refresh an unchanged layer-owned artifact, but it preserves user-owned, adopted, locally modified, legacy-ambiguous, and integrity-unknown files. Schema v2 migration defaults ambiguous paths to user-owned.

Strict manifest checks fail on missing identities, content changes, source drift, incomplete mirrors, or adapter identity mismatches. A legacy manifest can report only `integrity-unknown`, never a strict pass.

## Transactions and recovery

Exact-plan verification completes before transaction lock acquisition. Bound inputs and target preconditions are revalidated after the lock and before the first mutation. The applied plan digest is retained in the ownership manifest or update history.

Apply operations acquire a per-target lock and journal every target mutation before it occurs. Replacements receive SHA-256-verified backups. Install, update, update history, loop init, loop sync, and verifier writes commit through the shared transaction module or replay the journal in reverse.

Interrupted operations remain locked and recoverable through `scripts/transaction-recover.ps1`. See [Target Transactions](transactions.md) for the exact guarantees and recovery workflow.

## Harness safety

- Adapters are declarative manifests under `adapters/<name>/adapter.json`.
- Adapters may mirror skills into harness-specific folders.
- GitHub Copilot instructions use a dedicated `.github/copilot-instructions.md` adapter and preserve existing repository instructions through sidecars.
- Duplicate or overlapping destinations fail before mutation unless instruction adapters declare a shared compatibility group with unique precedence.
- Generic `AGENTS.md` is intended for tools without a dedicated adapter, not as a default companion to Codex.

## Target-project safety

- Project-local instructions remain authoritative.
- Pre-existing project files remain user-owned. Files created by the layer remain layer-owned until explicitly adopted or locally modified.
- Raw logs and generated dashboards are private by default.
- L2 worktrees must be outside the target root. External creation is registered read-only; verification and cleanup preview share one hashed lifecycle identity, while built-in Git mutation remains disabled.
- L2 verdicts bind reviewer role, HEAD, final Git state, command exits, command-output hashes, and evidence-file hashes. Changed or tampered evidence fails closed.
- L2 remains assisted: verifier PASS is a decision packet for human merge review, never merge permission.

## High-risk workflows

Remote push, deployment, dependency installation, CI changes, secret changes, and remote database migrations require explicit human approval.
