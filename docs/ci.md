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

The workflow executes the canonical local CI runner, which includes validate, packs, drift, quality, smoke, and matrix gates by default.

The runner includes:

- `scripts/validate.ps1`
- `scripts/pack-report.ps1 -Strict`
- `scripts/drift-check.ps1 -Strict`
- `scripts/score-layer.ps1 -Strict`
- `tests/smoke.ps1`
- `scripts/matrix.ps1`

## Required gate before release

Before cutting a release or adapting a target project, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1
```

For quick iteration, `-SkipMatrix` is acceptable while developing, but the full matrix should pass before a version commit.

## Quality gate

CI runs `scripts/score-layer.ps1 -Strict` after structural validation. This writes quality reports under `.tmp/quality/` and fails on artifacts below the default minimum score or critical risk signals.


## Drift gate

CI runs `scripts/drift-check.ps1 -Strict` after structural validation. This compares tracked agent artifacts against `registry/drift-baseline.json` and fails when behavior changed without an intentional baseline update.


## Pack gate

CI runs `scripts/pack-report.ps1 -Strict` after structural validation. This writes reports under `.tmp/packs/` and fails on invalid pack manifests, missing skills, invalid harnesses, invalid model profiles, or incomplete bundle metadata.


## Smoke hardening

The smoke test includes pack install checks, target pack overlay checks, `manifest-diff.ps1 -Strict`, upgrade verification that requested packs are preserved, and `update-target.ps1` preview/apply coverage with update-history validation.
