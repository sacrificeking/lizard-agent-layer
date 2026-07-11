# CI

`lizard-agent-layer` has one canonical local gate runner and one GitHub Actions workflow.

Install the pinned validator dependencies once after checkout or lockfile changes:

```powershell
npm ci
```

Node.js 20 or newer is required. PowerShell 7 is the portable default; Windows PowerShell 5.1 is retained as a compatibility host.

## Local runner

Run all gates:

```powershell
pwsh -NoProfile -File .\scripts\ci.ps1
```

Fast local check without smoke or matrix:

```powershell
pwsh -NoProfile -File .\scripts\ci.ps1 -SkipSmoke -SkipMatrix
```

Fail if the working tree is dirty after checks:

```powershell
pwsh -NoProfile -File .\scripts\ci.ps1 -StrictGitStatus
```

The runner writes JSON reports under `.tmp/ci/`.

## GitHub Actions

The workflow lives at `.github/workflows/lizard-agent-layer-ci.yml` and runs on pull requests, pushes to `main` or `master`, and manual dispatches.

The workflow executes the canonical local CI runner on Windows, Ubuntu, and macOS with PowerShell 7. A separate Windows job executes the same gates with Windows PowerShell 5.1. All jobs use the committed npm lockfile.

The runner includes:

- `scripts/validate.ps1`
- `tools/schema-validator/validate.mjs --mutation-corpus ...`
- `tests/run-focused.ps1`
- `scripts/pack-report.ps1 -Strict`
- `scripts/drift-check.ps1 -Strict`
- `scripts/score-layer.ps1 -Strict`
- `tests/smoke.ps1`
- `scripts/matrix.ps1`

## Required gate before release

Before cutting a release or adapting a target project, run:

```powershell
pwsh -NoProfile -File .\scripts\ci.ps1
```

For quick iteration, `-SkipMatrix` is acceptable while developing, but the full matrix should pass before a version commit.

## Schema contract gate

`scripts/validate.ps1` runs the pinned Ajv Draft 2020-12 validator against every bound profile, pack, adapter, model profile, loop, and registry document. CI then runs a separate mutation corpus that proves wrong types, missing fields, invalid enums, unknown fields, unsafe paths, and unsupported shapes fail deterministically. Focused integration tests also validate generated manifest and loop-evidence instances.

## Quality gate

CI runs `scripts/score-layer.ps1 -Strict` after structural validation. This writes quality reports under `.tmp/quality/` and fails on artifacts below the default minimum score or critical risk signals.


## Drift gate

CI runs `scripts/drift-check.ps1 -Strict` after structural validation. This compares tracked agent artifacts against `registry/drift-baseline.json` and fails when behavior changed without an intentional baseline update.


## Pack gate

CI runs `scripts/pack-report.ps1 -Strict` after structural validation. This writes reports under `.tmp/packs/` and fails on invalid pack manifests, missing skills, invalid harnesses, invalid model profiles, or incomplete bundle metadata.


## Smoke hardening

The smoke test includes pack install checks, target pack overlay checks, loop-engineering init/audit/report/sync/cost plus L2 worktree/verifier negative-gate and cleanup coverage, `manifest-diff.ps1 -Strict`, upgrade verification that requested packs are preserved, and `update-target.ps1` preview/apply coverage with update-history validation.

## Focused safety gate

`tests/run-focused.ps1` runs before the broader smoke suite and writes `.tmp/tests/focused-test-report.json`. Its unit, integration, and adversarial fixtures exercise host discovery, path containment, root equality, traversal, linked ancestors, ownership, transactions, version gates, loop evidence, force modes, adapter mirrors, and preview target no-op behavior. Windows uses junction fixtures; PowerShell on Linux and macOS uses symbolic-link fixtures.
