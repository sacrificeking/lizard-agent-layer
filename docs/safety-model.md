# Safety Model

The layer is built around conservative filesystem and workflow behavior.

## Installer safety

- Preview mode is the default.
- Existing files are skipped unless `-Force` is passed.
- Existing `AGENTS.md` receives a sidecar merge file instead of being overwritten.
- Apply mode writes an ownership manifest to `.agent/lizard-agent-layer.install.json`.

## Target-project safety

- Project-local instructions remain authoritative.
- Permissions are copied as a starting point; target projects own them after install.
- Raw logs and generated dashboards are private by default.

## High-risk workflows

Remote push, deployment, dependency installation, CI changes, secret changes, and remote database migrations require explicit human approval.
