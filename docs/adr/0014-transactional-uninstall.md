# ADR 0014: Transactional uninstall

## Status

Accepted for incremental implementation on 2026-08-22.

## Context

Manifest schema v4 preserves active and retired ownership evidence, but the layer has no executable removal lifecycle. Path names and a schema-valid target-local manifest are insufficient authority for deletion. An approved preview can also become stale before apply through content, object-identity, root, mount, type, or option changes.

## Decision

`uninstall.ps1` is preview-only by default. Apply requires an immutable canonical `uninstall` operation plan, an independently supplied SHA-256 digest, and explicit human approval. Every removal entry is restricted to `layer-owned` content and binds the target-root physical identity, relative path, object kind, current file hash where applicable, and a physical object-identity digest. Apply rederives the complete plan before locking, revalidates all bound inputs and target preconditions after acquiring the target transaction lock, and revalidates each entry immediately before mutation.

Files are removed before directories. Directories are removed only when empty. Every mutation is journaled before deletion; existing files are copied into the contained transaction backup store and verified before their directory entry is removed. Rollback restores deleted files and recreates deleted empty directories. Modified, adopted, user-owned, ambiguous, reappeared, linked, cross-mount, or identity-mismatched content fails closed or is preserved according to the explicitly approved scope.

The install manifest is removed after other files and before its now-empty parent directories only when no artifact is preserved. If managed-only removal leaves modified, ambiguous, missing, adopted, user-owned, or reappeared artifacts, the manifest and its ownership history remain present and the receipt status is `partial`. A machine-readable receipt is written outside the target root and binds the approved plan, transaction, removals, preserved paths, unresolved residue, and final verification. A target with no valid install manifest is a conservative no-op unless a separate file-by-file recovery plan is introduced in a future decision.

The installer records the complete parent-directory closure for every layer-created path, including nested skill-package directories. This makes empty-directory removal derivable from explicit artifact ownership instead of directory-name inference.

## Consequences

- Existing install and update plans remain valid; the operation-plan contract adds `uninstall`, `remove`, and a removal-only physical identity field.
- Uninstall cannot use recursive deletion or infer ownership from directory names.
- Complete scope requires a second plan-bound confirmation before modified layer-owned content becomes removable. Export-then-complete additionally binds an existing outside-target export-root identity, an exact manifest-file allowlist, and a sensitive-data confirmation; every create-new copy is hash-verified before deletion starts.
- Interrupted transactions use reviewed rollback/cleanup followed by a fresh plan; in-place continuation of a partial delete journal is not yet supported.
- Target-local evidence remains unauthenticated against a malicious target writer; that residual trust boundary remains H-09 scope.
