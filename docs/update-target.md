# Update Targets

`update-target.ps1` is the plan-first workflow for keeping an installed target project aligned with the current `lizard-agent-layer` repo.

It reads the target's `.agent/lizard-agent-layer.install.json`, preserves the installed profile, requested packs, expanded pack context, and harnesses, then compares that contract against the current layer version and artifacts.

## Preview

Generate a reviewable update plan without changing the target project:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project
```

The preview writes reports under `.tmp/updates/<timestamp>/` in this layer repo by default:

- `update-plan.md`
- `update-report.json`
- `pre-manifest-diff/manifest-diff.json`
- `pre-manifest-diff/manifest-diff.md`

Preview mode does not write into the target project.

Custom `-OutputDir` and `-PlanPath` values must remain outside the target by default. Use `-AllowTargetReportWrite` only for an intentional compatibility case; linked output ancestors remain rejected.

## Apply

After reviewing the plan, apply the update while preserving existing target files:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Apply
```

Apply mode re-runs `install.ps1` using the installed profile, requested packs, and harnesses. It then runs `manifest-diff.ps1 -Strict` and appends one JSONL entry to:

```text
.agent/lizard-agent-layer.update-history.jsonl
```

That history file records the previous version, current version, profile, requested packs, harnesses, plan path, install plan path, and pre/post manifest diff status.

## Replace Managed Artifacts

Use this only after reviewing the generated update plan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Apply -ForceManaged
```

`-ForceManaged` allows generated layer artifacts to be refreshed from the current layer. This is useful when skills, protocols, adapter files, sidecars, or templates improved and the target should receive the new canonical version. Unowned root instruction files such as an existing project `AGENTS.md` stay on the merge-review path instead of being silently replaced.

## Adapt During Update

You can intentionally adjust the installed contract during an update:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Profile supabase-react-finance -Packs frontend-product,supabase-react,finance-app,security-hardening -Harnesses codex,claude-code,gemini
```

Run that as preview first, review the plan, then add `-Apply` when the contract is correct.

## Recommended Routine

1. Update this `lizard-agent-layer` repository to the latest release.
2. Run `update-target.ps1` against the integrated project without `-Apply`.
3. Review `update-plan.md`, especially version relation, packs, harnesses, manifest differences, and affected areas.
4. Re-run with `-Apply` to update conservatively.
5. Use `-Apply -ForceManaged` only when the plan shows generated layer files should be replaced from the latest layer.
6. Run the target project's own quality gates after update.

## Machine Output

Use `-Json` for automation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Json
```

The JSON report includes mode, installed/current layer versions, selected profile, harnesses, requested packs, plan path, output directory, and pre/post manifest diff summaries.

