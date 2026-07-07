# CI

`lizard-agent-layer` has one canonical local gate runner and one GitHub Actions workflow.

## Local runner

Run all gates:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1
```

Fast local check without smoke or matrix:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1 -SkipSmoke -SkipMatrix
```

Fail if the working tree is dirty after checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1 -StrictGitStatus
```

The runner writes JSON reports under `.tmp/ci/`.

## GitHub Actions

The workflow lives at `.github/workflows/lizard-agent-layer-ci.yml` and runs on pull requests, pushes to `main` or `master`, and manual dispatches.

The workflow executes:

- `scripts/validate.ps1`
- `tests/smoke.ps1`
- `scripts/matrix.ps1`

## Required gate before release

Before cutting a release or adapting a target project, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1
```

For quick iteration, `-SkipMatrix` is acceptable while developing, but the full matrix should pass before a version commit.
