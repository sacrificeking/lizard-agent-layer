# Drift Intelligence

Drift intelligence makes changes to reusable agent behavior explicit.

It tracks hashes, sizes, line counts, word counts, and token estimates for the source artifacts that define how lizard-agent-layer behaves in target projects.

## Tracked artifacts

The drift baseline tracks files under:

- `adapters/`
- `skills/`
- `protocols/`
- `profiles/`
- `model-profiles/`
- `packs/`
- `registry/`, excluding `registry/drift-baseline.json`
- `schemas/`

It intentionally does not track generated `.tmp/` reports.

## Commands

Check drift against the committed baseline:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\drift-check.ps1 -Strict
```

Generate a report without failing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\drift-check.ps1
```

Update the baseline after intentional behavior changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\drift-check.ps1 -UpdateBaseline
```

## Reports

Reports are written under `.tmp/drift/`:

- `drift-report.json`: machine-readable comparison.
- `drift-report.md`: human-readable summary.

## CI behavior

`ci.ps1` runs drift after structural validation and before quality scoring. If tracked artifacts changed without updating `registry/drift-baseline.json`, strict CI fails.

Use `-SkipDrift` only for local diagnosis. Do not use it for release-worthy changes.

## Review discipline

A baseline update is an explicit acknowledgment that agent behavior, prompt surface, profile behavior, or risk policy has changed.

Before updating the baseline:

- Read the changed artifacts.
- Check whether token estimates changed materially.
- Confirm new or changed behavior is intentional.
- Run `validate`, `packs`, `drift`, `quality`, `smoke`, and `matrix` gates.
