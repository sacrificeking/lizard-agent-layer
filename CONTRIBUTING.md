# Contributing

`lizard-agent-layer` is infrastructure that writes into other repositories, so changes must be boring, inspectable, and conservative.

## Rules

- Default to preview/dry-run behavior.
- Preserve target-project files unless a force flag is explicit.
- Add or update smoke coverage for installer behavior.
- Keep skills concise and trigger descriptions clear.
- Do not add raw project memory or secrets to this repository.

## Local checks

```powershell
npm ci
pwsh -NoProfile -File .\scripts\validate.ps1
pwsh -NoProfile -File .\tests\run-focused.ps1
pwsh -NoProfile -File .\tests\smoke.ps1
```

Changes to a declarative JSON contract must update its schema and, for a new document family, `tools/schema-validator/bindings.json`. Add a negative mutation case when the change introduces a new required invariant.
