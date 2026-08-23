# ADR 0013: Handle-Bound Filesystem Access

- Status: Accepted
- Date: 2026-08-22
- Supersedes in part: ADR 0002 and ADR 0012 for race-resistant physical containment

## Context

Lexical containment, reparse-point inspection, and fresh Unix mount identity reject paths that are already unsafe when inspected. They do not bind the later read or mutation to the inspected filesystem objects. A local process with write access to the same ancestry can rename an inspected component and replace its name before a later name-based operation. In-place writes also modify every hard-link alias of the same inode.

The repository supports Windows PowerShell 5.1 and PowerShell 7.5+ on Windows, Ubuntu, and macOS. A runtime download, package install, or silent fallback to the older name-based path is not acceptable for this boundary.

## Decision

SafeFs publishes a root-specific capability document governed by `schemas/safe-fs-capability.schema.json`. The only full assurance value is `handle-bound-no-follow`. It requires ancestor handles, terminal no-follow access, descriptor identity, mount or volume identity, atomic replacement, atomic create-new, and relative deletion. Missing platform, kernel, filesystem, or interop support is reported as `SAFEFS_HANDLE_MUTATION_UNAVAILABLE` before a protected mutation; it is never converted into a name-based fallback.

Windows uses an in-repository, C# 5-compatible interop backend. It walks every component from the volume root with `NtCreateFile`, a parent handle, `OBJ_DONT_REPARSE`, and `FILE_OPEN_REPARSE_POINT`. Content is written to a unique file created relative to the held destination parent, flushed, and committed with parent-relative `NtSetInformationFile`. Existing hard links are rejected or their contained directory entry is replaced; an outside alias is never modified in place. Directory creation and deletion use the same relative-handle boundary.

Linux walks each component with held `openat` descriptors and obtains file, device, and mount identity through `statx`. macOS uses iterative `openat`/`*at` operations with held descriptors and `fstat`/`fstatfs` identity. Atomic replacement uses `renameat`; atomic create-new uses `linkat` followed by removal of the stage name so an existing destination is never overwritten. These backends remain release-unverified until synchronized link and mount fixtures pass on their native hosts.

Protected reads, copy sources, transaction lock/journal/backup/rollback/cleanup operations, plan persistence, and repository-owned external mutators must migrate to the same capability boundary or fail closed. Set, append, and copy use stage-and-replace instead of in-place writes. Git cannot consume held SafeFs handles portably, so built-in worktree create/remove apply fails with `SAFEFS_EXTERNAL_MUTATOR_UNBOUND`; the layer can only register an externally created, clean, identity-matched worktree without mutating it. Test synchronization hooks remain private to the module, require `LIZARD_SAFEFS_TESTING=1`, and are not exported.

## Consequences

- SafeFs reads, writes, copy, directory initialization, plans, and transaction primitives use the handle/descriptor-relative backend; Windows PowerShell 5.1 has local behavior evidence, while native Unix evidence remains pending.
- Unsupported volumes, network paths, or unavailable native primitives are intentional compatibility failures rather than reduced-assurance writes.
- Stage-and-replace changes file identity and may change inherited ACL, alternate-stream, extended-attribute, or hard-link behavior. Those semantics require explicit regression evidence before release.
- Append is containment-safe but does not claim multi-writer serializability.
- WP-01C and H-03 remain open until Ubuntu and macOS satisfy the executable contract and the complete supported-host matrix is green.
- Denial of service by a principal that can concurrently modify the authorized tree is outside the containment claim. Kernel or administrator compromise and mounts outside the current process namespace are also outside scope.
