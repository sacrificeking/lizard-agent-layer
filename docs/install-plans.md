# Install Plans

Install preview can emit two complementary artifacts: a human-readable Markdown report and a canonical JSON approval plan. Only the canonical plan can authorize apply.

## Why they exist

Target projects often already have local instruction files such as `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md`. The layer must not silently overwrite those files. A plan report makes the operation reviewable before apply and records the exact merge advice when sidecars are needed.

## Usage

Default report path under `.tmp/install-plans/`:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot -WritePlan -PlanPath .\.tmp\plans\project-plan.md -CanonicalPlanPath .\.tmp\plans\project-plan.json
```

Custom report path:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot -WritePlan -PlanPath .\.tmp\plans\project-plan.md
```

## Contents

A plan report includes:

- Target, profile, risk level, memory mode, layer version, and harnesses.
- Preview and apply commands.
- Selected skills.
- Planned, created, skipped, and manual-merge paths.
- Retired artifacts that contract reduction will preserve without deletion.
- Merge suggestions for existing instruction files.
- Suggested Markdown block for wiring the sidecar intentionally.

## Patch workflow

After reviewing the Markdown report and canonical JSON, independently retain the lowercase SHA-256 shown in `project-plan.json.sha256` (or compute it yourself). The sidecar is convenience output, not approval evidence. Apply with the same options and the independently retained digest:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot -Apply -ApprovedPlanPath .\.tmp\plans\project-plan.json -ApprovedPlanSha256 <sha256> -HumanApproved
```

After reviewing the install plan, run `scripts/merge-suggestions.ps1` to generate concrete patch files and copy-ready Markdown blocks for existing instruction files.

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot
```

## Safety behavior

Preview plus `-WritePlan` writes only the requested report file. It does not create `.agent/`, harness instruction files, skill mirrors, or sidecars in the target. The plan path must remain outside the target by default and is protected by the same linked-ancestor checks as target writes.

Apply fails before lock acquisition when approval is missing or when canonical bytes, expiry, roots, options, source inputs, target inputs, or planned preconditions differ. Critical input and target bindings are checked again after lock acquisition and before mutation. Regenerate the plan after any mismatch; plans are immutable and are never migrated or overwritten.

When a profile, pack, skill, or harness is deselected, its previously recorded artifacts remain preserve-only targets in the canonical plan. Apply carries their ownership and last installed identity forward as `retired-present` or `retired-missing`; install and update never delete them.

For a deliberate compatibility case, `-AllowTargetReportWrite` permits a target-local plan after explicit opt-in. Such a plan is a report artifact and is not tracked as a layer-owned target path.
