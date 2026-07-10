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

## Destination composition

The installer expands every selected adapter before writing. Undeclared equal or overlapping destinations fail preflight. A shared instruction destination is permitted only when all participants declare the same compatibility group and distinct precedence values.

`generic-agents-md` and `codex` both target `AGENTS.md`; they declare the `agents-md` group and Codex has higher precedence. The manifest records Codex as the effective adapter and Generic as a compatibility alias. Reversing selection order produces the same result.

Focused tests evaluate every built-in adapter pair in both orders. `doctor.ps1 -Strict` and `manifest-diff.ps1 -Strict` require the exact effective instruction or sidecar hash instead of accepting a shared keyword.
