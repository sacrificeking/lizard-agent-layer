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

## Harness safety

- Adapters are declarative manifests under `adapters/<name>/adapter.json`.
- Adapters may mirror skills into harness-specific folders.
- Duplicate instruction destinations should be avoided in the same profile unless intentional.
- Generic `AGENTS.md` is intended for tools without a dedicated adapter, not as a default companion to Codex.

## Target-project safety

- Project-local instructions remain authoritative.
- Permissions are copied as a starting point; target projects own them after install.
- Raw logs and generated dashboards are private by default.
- L2 worktrees must be outside the target root; creation, verification, and cleanup reject unsafe path identities.

## High-risk workflows

Remote push, deployment, dependency installation, CI changes, secret changes, and remote database migrations require explicit human approval.
