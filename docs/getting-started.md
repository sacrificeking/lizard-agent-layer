# Getting Started

## 1. Analyze the target

Start with a read-only recommendation for profile, risk level, harnesses, skills, and packs.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project
```

Use `-Json` when another script should consume the recommendation.

## 2. Choose a profile

Use `minimal` for small repositories, `standard` for normal product work, and `supabase-react-finance` for high-risk React/Supabase finance projects. Treat the analyzer as a starting point, not as an irreversible decision.

## 3. Choose packs when useful

Use packs to add reusable project-shape logic on top of the chosen profile. The analyzer prints `recommendedPacks` and includes `-Packs` in the preview command when signals match known bundles.

Example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs frontend-product -WritePlan
```

See [Packs](packs.md) for the current bundle catalog.

## 4. Write a plan report

Generate a human-readable plan before touching the target project.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -WritePlan
```

Use `-PlanPath` to choose the report location:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -WritePlan -PlanPath .\.tmp\plans\project-plan.md
```

Preview mode still does not create `.agent/`, sidecars, or harness files in the target. The plan is the only explicit write.

## 5. Generate merge suggestions

When a target already has `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, or a Cursor rule, generate patch artifacts for review.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard
```

Use `-OutputDir` to choose where reports, patch files, and copy-block files are written.

## 6. Preview first

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard
```

Preview mode prints planned creates, existing skips, harness files, skill mirrors, manual merge needs, and merge suggestion counts.

## 7. Optionally override harnesses

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,cursor
```

## 8. Apply when the plan is acceptable

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Apply
```

If an existing instruction file such as `AGENTS.md` already exists, the installer writes a sidecar and records merge suggestions instead of modifying the original file.

## 9. Audit the target

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project
```

Use `-Strict` in CI or release-style checks.

## 10. Compare an installed target

After installing or upgrading a target, compare the install manifest against the current layer:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

## 11. Update an installed target

After this layer repository has a newer release, generate a reviewable update plan for the integrated project:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project
```

Review `update-plan.md`. If the selected profile, packs, harnesses, and manifest differences look correct, apply conservatively:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Apply
```

Use `-Apply -ForceManaged` only when the plan shows generated layer artifacts should be replaced from the current layer.

## 12. Add report-only loop engineering when useful

Install loop skills through the pack, then initialize a pattern-specific runtime after reviewing the plan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs loop-engineering -Apply
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -WritePlan
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -Apply
```

Audit, report, sync, or estimate budget with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-audit.ps1 -TargetPath D:\path\to\project -Strict
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-report.ps1 -TargetPath D:\path\to\project
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-sync.ps1 -TargetPath D:\path\to\project
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\loop-cost.ps1 -Pattern daily-triage -Level L1 -Cadence 1d
```

See [Loop engineering](loop-engineering.md) for the readiness model and safety rules.

## 13. Validate this layer before changing it

Run the full local CI gate:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1
```

Or run individual gates:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\matrix.ps1
```
