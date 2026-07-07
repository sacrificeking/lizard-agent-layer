# AGENTS.md - lizard-agent-layer

This repository builds portable agent infrastructure for other repositories.

## Operating rules

- Treat target-project installers as high-risk filesystem tools.
- Default every installer to preview/dry-run behavior.
- Never overwrite a target project's `AGENTS.md`, existing skills, memory, or protocol files unless the user passes an explicit force flag.
- Keep reusable logic generic. Put project-specific policy in profiles or target-local files.
- Prefer small, inspectable scripts over hidden magic.
- Keep all generated target-project memory free of secrets and private raw logs by default.

## Quality bar

Before release-worthy changes:

- Run the installer in preview mode against a scratch target.
- Run the installer in apply mode against a scratch target.
- Verify rerunning apply mode is idempotent.
- Confirm existing target files are skipped or written as merge sidecars, not clobbered.

## Repository shape

- `profiles/`: project profile definitions
- `skills/`: reusable skill packages
- `protocols/`: reusable governance rules
- `adapters/`: harness-specific instruction shims
- `templates/`: target-project seed files
- `scripts/`: installer and maintenance commands
- `schemas/`: config schemas
