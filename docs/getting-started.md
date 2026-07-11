# Getting Started

## 1. Analyze the target

Start with a read-only recommendation for profile, risk level, harnesses, skills, and packs.

```powershell
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project
```

Use `-Json` when another script should consume the recommendation.

## 2. Choose a profile

Use `minimal` for small repositories, `standard` for normal product work, and `supabase-react-finance` for high-risk React/Supabase finance projects. Treat the analyzer as a starting point, not as an irreversible decision.

## 3. Choose packs when useful

Use packs to add reusable project-shape logic on top of the chosen profile. The analyzer prints `recommendedPacks` and includes `-Packs` in the preview command when signals match known bundles.

Example:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs frontend-product -WritePlan
```

See [Packs](packs.md) for the current bundle catalog.

## 4. Write a plan report

Generate a human-readable plan before touching the target project.

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -WritePlan
```

Use `-PlanPath` to choose the report location:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -WritePlan -PlanPath .\.tmp\plans\project-plan.md
```

Preview mode still does not create `.agent/`, sidecars, or harness files in the target. The plan is the only explicit write.

## 5. Generate merge suggestions

When a target already has `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, or a Cursor rule, generate patch artifacts for review.

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard
```

Use `-OutputDir` to choose where reports, patch files, and copy-block files are written.

## 6. Preview first

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard
```

Preview mode prints planned creates, existing skips, harness files, skill mirrors, manual merge needs, and merge suggestion counts.

## 7. Optionally override harnesses

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,cursor
```

## 8. Apply when the plan is acceptable

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Apply
```

If an existing instruction file such as `AGENTS.md` already exists, the installer writes a sidecar and records merge suggestions instead of modifying the original file.

## 9. Audit the target

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project
```

Use `-Strict` in CI or release-style checks.

## 10. Compare an installed target

After installing or upgrading a target, compare the install manifest against the current layer:

```powershell
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

## 11. Update an installed target

After this layer repository has a newer release, generate a reviewable update plan for the integrated project:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project
```

Review `update-plan.md`. If the selected profile, packs, harnesses, and manifest differences look correct, apply conservatively:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Apply
```

Use `-Apply -ForceManaged` only when the plan shows generated layer artifacts should be replaced from the current layer.

## 12. Add loop engineering when useful

Install loop skills through the pack, then initialize a pattern-specific runtime after reviewing the plan:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs loop-engineering -Apply
pwsh -NoProfile -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -WritePlan
pwsh -NoProfile -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -Apply
```

Audit, report, sync, or estimate budget with:

```powershell
pwsh -NoProfile -File .\scripts\loop-audit.ps1 -TargetPath D:\path\to\project -Strict
pwsh -NoProfile -File .\scripts\loop-report.ps1 -TargetPath D:\path\to\project
pwsh -NoProfile -File .\scripts\loop-sync.ps1 -TargetPath D:\path\to\project
pwsh -NoProfile -File .\scripts\loop-cost.ps1 -Pattern daily-triage -Level L1 -Cadence 1d
```

For L2 assisted fixes, initialize `minimal-fix-assist`, preview the worktree, require `-Apply -HumanApproved` before any worktree is created, verify against the exact branch/worktree, and clean up with the same human gate:

```powershell
pwsh -NoProfile -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern minimal-fix-assist -WritePlan
pwsh -NoProfile -File .\scripts\loop-worktree.ps1 -TargetPath D:\path\to\project -ItemId fix-123 -Branch lizard/l2/fix-123
pwsh -NoProfile -File .\scripts\loop-worktree.ps1 -TargetPath D:\path\to\project -ItemId fix-123 -Branch lizard/l2/fix-123 -Apply -HumanApproved
pwsh -NoProfile -File .\scripts\loop-verify.ps1 -TargetPath D:\path\to\project -WorktreePath D:\path\to\worktree -Branch lizard/l2/fix-123 -Verifier reviewer-name -Status NEEDS_REVIEW -Apply
pwsh -NoProfile -File .\scripts\loop-worktree-cleanup.ps1 -TargetPath D:\path\to\project -WorktreePath D:\path\to\worktree -Branch lizard/l2/fix-123 -RemoveBranch
pwsh -NoProfile -File .\scripts\loop-worktree-cleanup.ps1 -TargetPath D:\path\to\project -WorktreePath D:\path\to\worktree -Branch lizard/l2/fix-123 -RemoveBranch -Apply -HumanApproved
```

See [Loop engineering](loop-engineering.md) for the readiness model and safety rules.

## 13. Validate this layer before changing it

Run the full local CI gate:

```powershell
pwsh -NoProfile -File .\scripts\ci.ps1
```

Or run individual gates:

```powershell
pwsh -NoProfile -File .\scripts\validate.ps1
pwsh -NoProfile -File .\tests\smoke.ps1
pwsh -NoProfile -File .\scripts\matrix.ps1
```
