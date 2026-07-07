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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
```
