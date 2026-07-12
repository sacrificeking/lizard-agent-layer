# ADR 0002: Filesystem And Report Containment

- Status: Accepted
- Date: 2026-07-12

## Context

Textual relative-path checks do not prevent symlink or junction escapes, and preview reports can accidentally dirty targets.

## Decision

Every mutation resolves through `Lizard.SafeFs.psm1`, rejects linked ancestors, and rechecks the authorized root immediately before writing. Target writes require containment inside the target. Preview/report writes require containment inside their report root and remain outside the target unless a separately named compatibility flag is explicit.

## Consequences

Previously accepted linked or target-local report paths may now fail closed. Compatibility opt-ins are visible and never implied by force modes.
