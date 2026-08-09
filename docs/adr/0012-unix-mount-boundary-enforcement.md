# ADR 0012: Unix Mount Boundary Enforcement

- Status: Accepted
- Date: 2026-08-09
- Supersedes in part: ADR 0002 for Unix physical mount containment

## Context

Lexical containment plus symlink and reparse-point rejection does not identify a filesystem mounted below an authorized Unix root. A Linux bind mount may retain the same device identity as its source while introducing a distinct mount identity, so device comparison alone is insufficient.

## Decision

Safe filesystem resolution reads fresh mount identity for every Unix validation. Linux uses strict `/proc/self/mountinfo` parsing and compares both mount ID and device identity for the authorized root and every destination path component. macOS enumerates mounted roots through the runtime and binds each to the device identity reported by `stat`. A nested identity change fails closed; the authorized root may itself be a mountpoint. Missing, empty, malformed, or incomplete identity data also fails closed.

Windows continues to use reparse-point enforcement. A dedicated privileged Ubuntu CI fixture must prove rejection of both a same-device bind mount and a cross-device `tmpfs` mount. The implementation installs no dependency and invokes no shell during ordinary Windows validation.

## Consequences

- Unix targets and report roots cannot silently cross a mount boundary that is visible in the current process mount namespace.
- Previously accepted target layouts containing nested mounts now fail with stable `SAFEFS_MOUNT_BOUNDARY` or `SAFEFS_DEVICE_BOUNDARY` codes; no stored target data requires migration.
- Mount identity is not cached across validation calls, but validation and mutation remain separate name-based operations. A synchronized mount or ancestor swap after validation remains WP-01C scope.
- Container or host mounts outside the current process mount namespace are not claimed as observable.
