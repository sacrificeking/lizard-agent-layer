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

## Contract changes

Before changing a path matched by `registry/contracts.json`:

1. Read the linked ADR.
2. Add `changes/<date>-<id>.json` covering the exact changed paths.
3. Link every impacted ADR and state migration plus compatibility disposition.
4. Add a new or superseding ADR when the durable decision itself changes.
5. Run `pwsh -NoProfile -File .\scripts\contract-check.ps1 -Strict` before committing.

See [Compatibility](docs/compatibility.md), [Deprecation policy](docs/deprecation-policy.md), and [Troubleshooting](docs/troubleshooting.md).
