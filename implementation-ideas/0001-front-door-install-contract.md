# 0001 — Front-door install contract

**Work package:** WP-A docs and regression tests only. Mandatory signed-apply kit is **withdrawn** — see [0002](0002-human-plan-approval.md).
**Trigger:** Live install into an external target (`degen-resource-hub`) failed because public lizard docs describe commands that `install.ps1` / `update-target.ps1` / `uninstall.ps1` reject.

Do not change product files until this idea is explicitly approved for implementation.

## Problem

The installer is the source of truth. Several public documents and one generated preview command describe a front door that the scripts fail closed on. An AI-guided install that follows Markdown therefore cannot finish, even when the target repository is clean.

Three independent contract breaks showed up in the same attempt:

### 1. Missing `-Harnesses` in documented commands

`install.ps1` throws `INSTALL_HARNESSES_REQUIRED` for `standard` and `enterprise-fullstack` when `-Harnesses` is omitted. That is intentional (one org-approved harness).

These documents still show those profiles without `-Harnesses`:

- `docs/install-plans.md` (preview and apply)
- `docs/packs.md` (`standard` + one pack; `enterprise-fullstack` + packs)
- `docs/loop-engineering.md` (`standard` + `loop-engineering` preview and apply)

`README.md`, `INSTALL.md`, `QUICKSTART.md`, and `docs/profiles.md` already require `-Harnesses`. The calorie test allowlist in `tests/unit/overlay-calorie-budget.tests.ps1` does **not** include `install-plans.md`, `packs.md`, or `loop-engineering.md`, so the drift is invisible.

### 2. Canonical plans written inside the target

Scripts require plan / canonical-plan / approved-plan / uninstall-receipt / update `OutputDir` paths **outside** the target root (`Assert-PathOutsideRoot`), unless `-AllowTargetReportWrite` is explicitly set.

Relative `.\.tmp\...` is only legal when the current working directory is **not** the target (typically the lizard source checkout). Public front-door copy-paste tells operators to run from the **target** with `-TargetPath "."` and `.\.tmp\...`. That resolves inside the target and is rejected.

Confirmed offenders:

- `QUICKSTART.md` §2 AI prompt: `-TargetPath "<this-repo-path>"` with `.tmp/install-plan.md` / `.tmp/install-plan.json`
- `QUICKSTART.md` §3: run from repository root, `-TargetPath "."`, `.\.tmp\install-plan.*`
- `QUICKSTART.md` §6–7: same pattern for update `OutputDir` and uninstall `CanonicalPlanPath`
- `INSTALL.md` AI update/uninstall prompts: `.tmp/update-plan` and `.tmp/uninstall-plan.json` against `"<this-repo-path>"`
- `docs/update-target.md` 1-liner: `-TargetPath "." -OutputDir .\.tmp\update-plan`
- `UNINSTALL.md` 1-liner: `-TargetPath "."` with `.\.tmp\uninstall-plan.json`

Snippets that use an **absolute** `-TargetPath D:\path\to\project` (or `C:\path\to\your-project`) plus `.\.tmp\...` are valid **only if cwd is the lizard source**. They are still a footgun if an assistant copies them into the target. Prefer one cwd-independent convention.

`scripts/analyze-target.ps1` currently emits preview argv with `.\.tmp\install-plan.md` and `.\.tmp\install-plan.json`. That preview is only safe if the generated command is executed with cwd outside the target (`tests/unit/host.tests.ps1` already does that). Assistants that replay the preview command from the target will hit the same rejection.

### 3. High-risk apply has no operator path

`Get-LizardOperationApprovalPolicy` requires a signed envelope, digest-pinned trust store, challenge, and replay ledger when merged `riskLevel` is `high` (enterprise profile **or** high packs such as `database-backend`, `backend-api`, `security-hardening`, `precision-domain`), and for complete uninstall / force flags.

`QUICKSTART.md` and `INSTALL.md` tell the reader to see `protocols/permissions.md` and `docs/safety-model.md` for signed approval workflows. Those files do **not** describe how to mint Trust Store, Challenge, Envelope, or Replay Ledger.

The only working mint path today is test-only (`tests/TestTrustHelpers.psm1`, `New-LizardSignedEvidenceEnvelope`). Using it as a production control would fake the control. There is no `scripts/` operator entrypoint and no honest public page.

Consequence: any recommended “enterprise + DB/API/security/precision packs” install can preview, then cannot apply if the human follows the docs.

Related holes (same theme, do not expand scope unless already touching the policy):

- `update-target.ps1` currently feeds the policy `RiskLevel 'medium'`, so a high-risk target can be updated without the envelope that install demanded.
- `records-lifecycle.ps1` does not call the policy at all, despite the policy function having a purge/destroy case.

Those two are **not** required to unblock a first install. List them as follow-ups, not as this work package’s definition of done.

## What is not a lizard defect

- Git history of the target still containing old layer files while HEAD is clean. Install/doctor/manifest inspect the current tree. “Never existed in history” is a persona rule, not a lizard contract. Do not add history-rewrite guidance.
- Stopping for explicit profile/harness/pack confirmation. That is INSTALL.md behaving correctly.

## Solution

Keep script fail-closed behavior. Make every public command and every generated preview command executable as written.

Convention for plan artifacts:

- Default operator location: `$HOME/.lizard-agent-layer/.tmp\` (the clone QUICKSTART already uses) **or** the lizard source `.tmp\` when the documented cwd is the lizard checkout and `-TargetPath` is a different absolute path.
- Never document `-TargetPath "."` together with `.\.tmp\` or `.tmp/` plan paths.
- Never document `standard` / `enterprise-fullstack` `install.ps1` without `-Harnesses <one-id>`.

Do **not** add a mandatory signed-apply kit to make high-risk apply possible. High-risk RSA and parroted SHA-256 hex are the wrong default; [0002](0002-human-plan-approval.md) replaces that product decision. This idea only makes documented commands match `INSTALL_HARNESSES_REQUIRED` and `Assert-PathOutsideRoot`.

## Implementation

### WP-A — Docs and tests (do this first)

1. Add `-Harnesses github-copilot` (or the existing single-harness placeholder) to every `install.ps1` snippet in:
   - `docs/install-plans.md`
   - `docs/packs.md`
   - `docs/loop-engineering.md`
2. Rewrite front-door copy-paste so plans stay outside the target:
   - `QUICKSTART.md` §2–3, §6–7
   - `INSTALL.md` AI prompts for update/uninstall
   - `docs/update-target.md` 1-liner
   - `UNINSTALL.md` 1-liner
   - Suggested QUICKSTART shape: `-TargetPath (Resolve-Path .).Path` and `-PlanPath/-CanonicalPlanPath/-OutputDir` under `"$HOME/.lizard-agent-layer/.tmp"`.
3. Change `scripts/analyze-target.ps1` preview argv to absolute paths under the **layer** `.tmp` (not the target, not cwd-relative). Update `tests/unit/host.tests.ps1`, which currently asserts the plan lands in the generated **cwd** `.tmp`.
4. Extend `tests/unit/overlay-calorie-budget.tests.ps1` (or add `tests/unit/public-command-contract.tests.ps1` and list it in `tests/run-focused.ps1`):
   - Allowlist must include `docs/install-plans.md`, `docs/packs.md`, `docs/loop-engineering.md`, `UNINSTALL.md`.
   - Any `install.ps1` command with `-Profile standard` or `-Profile enterprise-fullstack` must contain `-Harnesses`.
   - Any command with `-TargetPath "."` or `-TargetPath "<this-repo-path>"` must **not** use relative `.tmp` / `.\.tmp` for `PlanPath`, `CanonicalPlanPath`, `ApprovedPlanPath`, or `OutputDir`.
5. Changelog: document the contract alignment. Do not claim CI/H-03 evidence that has not run.

### WP-B — withdrawn

Do not implement a mandatory operator kit so that high-risk `-Apply` can demand RSA envelopes. That product stance is replaced by [0002](0002-human-plan-approval.md).

### Follow-ups

Covered by 0002: update-target risk bypass, records-lifecycle policy claims, digest/signed-apply as **opt-in**.

## Premortem

- If docs are fixed but calorie allowlist is not, the next Markdown snippet will regress the same way.
- If analyzer preview stays cwd-relative, AI installers will keep writing plans into the target even after QUICKSTART is fixed.
- Do not weaken `INSTALL_HARNESSES_REQUIRED` or `Assert-PathOutsideRoot` to match the old docs.
- Do not “fix” high-risk apply by forcing SHA parrot or RSA mint in the default path (0002).

## Done when

- A human (and an AI following public Markdown) can preview `standard` + one `-Harnesses` into a **separate** target without rewriting flags or putting plans inside the target.
- Focused tests fail if harness omission or in-target `.tmp` plan paths reappear in the listed public files.
- Apply UX and optional digest/signed-apply are tracked in 0002, not here.
