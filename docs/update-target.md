# Update Targets

For interrupted transactions, unsupported manifests, integrity-unknown files, and downgrade gates, follow [Troubleshooting and recovery](troubleshooting.md).

`update-target.ps1` is the plan-first workflow for keeping an installed target project aligned with the current `lizard-agent-layer` repo.

It reads the target's `.agent/lizard-agent-layer.install.json`, preserves the installed profile, requested packs, expanded pack context, and harnesses, then compares that contract against the current layer version and artifacts.

## Preview

Generate a reviewable update plan without changing the target project:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\project-update
```

The preview writes reports under `.tmp/updates/<timestamp>/` in this layer repo by default:

- `update-plan.md`
- `update-plan.json` and `update-plan.json.sha256`
- `install-plan.json` and `install-plan.json.sha256` for the exact nested installer operation
- `update-report.json`
- `pre-manifest-diff/manifest-diff.json`
- `pre-manifest-diff/manifest-diff.md`

Preview mode does not write into the target project.

Custom `-OutputDir` and `-PlanPath` values must remain outside the target by default. Use `-AllowTargetReportWrite` only for an intentional compatibility case; linked output ancestors remain rejected.

## Apply

After reviewing the plan, apply the update while preserving existing target files:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\project-update -Apply -ApprovedPlanPath .\.tmp\project-update\update-plan.json -ApprovedPlanSha256 <independently-reviewed-sha256> -HumanApproved
```

Apply validates the independently supplied outer digest, the bound nested install plan, all current options and inputs, and target preconditions before locking. It revalidates after locking and before mutation. It then runs the exact nested `install.ps1` plan, executes `manifest-diff.ps1 -Strict`, and appends one JSONL entry to:

```text
.agent/lizard-agent-layer.update-history.jsonl
```

That history file records the previous version, current version, profile, requested packs, harnesses, plan path, install plan path, and pre/post manifest diff status.

## Replace Managed Artifacts

Use this only after reviewing the generated update plan:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\project-update -ForceManaged
# review the new canonical plan, then repeat the same options with:
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\project-update -ForceManaged -Apply -ApprovedPlanPath .\.tmp\project-update\update-plan.json -ApprovedPlanSha256 <sha256> -HumanApproved
```

`-ForceManaged` refreshes only exact manifest-v3 entries whose current hash still matches their installed hash and whose ownership is `layer-owned`. User-owned, adopted, locally modified, legacy-ambiguous, missing-identity, or conflicting files remain untouched and are listed in the install plan and manifest conflicts.

Schema v2 targets migrate conservatively on apply. Because v2 cannot prove per-file provenance, existing ambiguous files become `user-owned`; `-ForceManaged` does not adopt or replace them implicitly.

## Version and schema gates

Schemas newer than the current reader, unsupported old schemas, and malformed versions stop before report or target writes. A target created by a newer layer version can still produce a preview plan, but apply requires both explicit switches:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\downgrade-plan -AllowDowngrade
# after exact-plan review:
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\downgrade-plan -AllowDowngrade -Apply -ApprovedPlanPath .\.tmp\downgrade-plan\update-plan.json -ApprovedPlanSha256 <sha256> -HumanApproved
```

Applied update history records the old and new manifest schemas plus downgrade approval state. `upgrade.ps1` delegates installed targets to this same workflow.

## Adapt During Update

You can intentionally adjust the installed contract during an update:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Profile supabase-react-finance -Packs frontend-product,supabase-react,finance-app,security-hardening -Harnesses codex,claude-code,gemini
```

Run that as preview first, review the plan, then add `-Apply` when the contract is correct.

## Recommended Routine

1. Update this `lizard-agent-layer` repository to the latest release.
2. Run `update-target.ps1` against the integrated project without `-Apply`.
3. Review `update-plan.md`, especially version relation, packs, harnesses, manifest differences, and affected areas.
4. Independently retain the canonical plan SHA-256 and re-run with the same options plus `-Apply -ApprovedPlanPath ... -ApprovedPlanSha256 ... -HumanApproved`.
5. Use `-Apply -ForceManaged` only when the plan shows generated layer files should be replaced from the latest layer.
6. Run the target project's own quality gates after update.

## Machine Output

Use `-Json` for automation:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Json
```

The JSON report includes mode, installed/current layer versions, selected profile, harnesses, requested packs, plan path, output directory, and pre/post manifest diff summaries.

