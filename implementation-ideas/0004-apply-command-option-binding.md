# 0004 — Generated apply command omits bound install options

**Work package:** one installer fix plus a focused test. Highest-priority product bug from the degen-resource-hub install.
**Live evidence:** Preview bound `-WritePlan`, `-PlanPath`, TTL, and `-MemoryMode off`. The plan Markdown **Apply:** block did not echo those flags. First apply failed `PLAN_BINDING_OPTIONS_MISMATCH`.

Do not change product files until this idea is explicitly approved for implementation.

## Problem

`Get-InstallInvocationOptions` in `scripts/install.ps1` puts these keys into the canonical plan intent:

- `memory_mode` (effective, including explicit `off`)
- `write_plan` / `plan_path` (`-WritePlan` or `-PlanPath`)
- `plan_ttl_minutes`

`New-InstallPlanMarkdown` builds the printed Apply command from a short `previewArguments` list: target, profile, harnesses, packs, routing, model mode. It does **not** add `-MemoryMode`, `-WritePlan`, `-PlanPath`, or `-PlanTtlMinutes`.

Apply then rebuilds current options from the **live** CLI. Following the printed command therefore yields `write_plan=false` and profile-default memory mode against a plan that recorded `write_plan=true` and `memory_mode=off`. `Assert-ApprovedInstallPlanCurrent` fails with `PLAN_BINDING_OPTIONS_MISMATCH`.

`Get-CurrentInstallProbePlan` has the same hole: it forwards `-MemoryMode` only if the apply CLI set `$MemoryMode`, and `-WritePlan`/`-PlanPath` only if `$ShouldWritePlan` is already true on this process.

`tests/integration/install-plan-binding.tests.ps1` never uses the Markdown Apply block. `New-TestInstallApprovalArguments` replays the **preview** argv plus `-Apply`, so CI cannot see this.

Any operator who uses `-WritePlan`/`-PlanPath` (the documented front door) and then copies **Apply:** from the plan report hits this. That is a product defect, not user error.

## Solution

Two complementary changes; do both.

1. **Intent hygiene:** `write_plan` and `plan_path` are preview-report flags, not mutation intent. Drop them from `Get-InstallInvocationOptions` (keep them on the Markdown report as facts). Apply must not require the caller to re-pass `-WritePlan` in order to mutate the target. TTL remains bound if it affects plan expiry (`expires_at` already exists); prefer binding expiry, not the raw TTL flag, if they can drift independently.
2. **Printed Apply command** must include every CLI flag that **remains** in invocation options after (1), at least:
   - `-MemoryMode` when it is not the profile default or was explicitly passed
   - `-PlanTtlMinutes` if still bound
   - packs, routing, model flags already present
   - `-Apply`, `-ApprovedPlanPath`, SHA placeholder, `-HumanApproved`

Never tell the human to pass `-WritePlan` on apply just to satisfy a byte-equal options dict.

## Implementation

1. `scripts/install.ps1`
   - Remove `write_plan` and `plan_path` from `Get-InstallInvocationOptions` (and thus from plan `intent.options`).
   - `New-InstallPlanMarkdown`: build apply argv from the same function that builds probe argv, minus `-InternalPlanProbe` / `-SuppressPlanReport` / probe canonical path, plus `-Apply` + approved-plan placeholders. Include `-MemoryMode $EffectiveMemoryMode` whenever `$MemoryMode` was passed **or** effective mode ≠ profile default.
   - `Get-CurrentInstallProbePlan`: pass `-MemoryMode $EffectiveMemoryMode` whenever the approved/current effective mode must be reproduced, not only when the apply CLI string is non-empty.
2. Tests (must land in `tests/run-focused.ps1`, preferably `tests/integration/install-plan-binding.tests.ps1` or a sibling):
   - Preview with `-WritePlan -PlanPath <outside> -MemoryMode off -Profile minimal` (or standard + harnesses).
   - Parse the Markdown **Apply:** command (or the structured equivalent).
   - Running that apply argv (with a real SHA) must exit 0. Today it must fail; after the fix it must pass.
   - Negative: apply with a **different** `-MemoryMode` than the plan still `PLAN_BINDING_OPTIONS_MISMATCH`.
3. Changelog: Fixed, not a feature.

Do not weaken intent matching for profile, harnesses, packs, memory mode, routing, or force flags.

## Premortem

- Leaving `write_plan` in options and only echoing `-WritePlan` on apply “fixes” copy-paste but makes apply rewrite reports and couples mutation to report paths. Drop the keys.
- Forgetting explicit `off` memory on the printed command recreates the live failure even after write_plan is unbound.
- Probe vs printed command drifting again: one helper for “reproducible install argv”.
- Tests that only replay TestHelper argv will go green while Markdown stays wrong. Assert on the plan report text.

## Done when

- Copy-pasting the plan report Apply command after a normal `-WritePlan` preview succeeds.
- Memory mode `off` in the plan cannot be silently replaced by profile default.
- Focused tests fail if Markdown apply omits a still-bound option.
