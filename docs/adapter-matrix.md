# Adapter Matrix

`scripts/matrix.ps1` installs every selected profile/harness pair into scratch targets and runs `doctor.ps1 -Strict` against each result.

## Full matrix

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\matrix.ps1
```

## Focused matrix

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\matrix.ps1 -Profiles standard,supabase-react-finance -Harnesses codex,claude-code,gemini
```

## Output

Each run writes a timestamped scratch directory under `.tmp/` and produces `matrix-report.json`. Scratch output is retained for audit so failures can be inspected after the run.

Use the matrix whenever a profile, adapter manifest, skill mirror, installer behavior, or doctor rule changes.
