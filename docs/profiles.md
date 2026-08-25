# Profiles

> [!NOTE]
> **⚡ Ultra High-Dense Quick Check:**
> - `minimal`: Low risk; light overlay for scripts, libraries, and small tools.
> - `standard`: Medium risk (recommended default); team overlay; requires explicit `-Harnesses`.
> - `enterprise-fullstack`: High risk label; **same six core skills as `standard`**. Domain stacks come from `-Packs`, not from the profile skill list.

Profiles describe how much agent infrastructure a target project should receive.

## minimal

For small scripts, libraries, or experiments. Default skills: `git-safety`, `research-audit`, `staged-execution`. Default harness is `generic-agents-md` unless `-Harnesses` is passed.

## standard

For normal product repositories. Requires explicit `-Harnesses` at install time (fails closed without it). Default skills (matching, not always-on): `git-safety`, `staged-execution`, `research-audit`, `project-decision-harvest`, `repo-grounded-change`, `premortem`. Release, dependency-upgrade, and domain packs are **not** included unless you pass `-Packs` or extra skills.

## enterprise-fullstack

For high-risk fullstack repositories (databases, APIs, UI, precision). Requires explicit `-Harnesses`. **Skill list matches `standard`.** Oracle/PostgreSQL/MSSQL, frontend frameworks, and API stacks are **not** implied by the profile name. Add them with `-Packs` (for example `database-backend`, `frontend-engineering`, `backend-api`, `security-hardening`, `precision-domain`). Risk level is `high`; that does not install slogan skills.


## Harness override

Use `-Harnesses` with `scripts/install.ps1` to override profile defaults:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot
```

Available adapters:

- `codex`
- `claude-code`
- `gemini`
- `cursor`
- `github-copilot`
- `generic-agents-md`

## Legacy model profiles

`modelProfiles` is deprecated. Existing custom profiles and the old source catalog remain readable for compatibility, but every catalog entry is marked deprecated and no built-in profile or example binds it. The catalog is not a statement about current model availability or quality. New configurations should use logical staged roles and, only when a real automatic executor exists, target-local `modelInventory` plus `modelRuntime`.

Legacy/custom profiles may still map model roles:

- `implementation`: primary editing model
- `review`: independent reviewer
- `research`: broad research and synthesis model
- `lowRiskAssistant`: optional local or smaller model for low-risk tasks
- `strategist`: architecture, decomposition, constraints, and success criteria
- `deepExecutor`: complex debugging and cross-cutting reasoning
- `standardExecutor`: normal implementation and test iteration
- `bulkExecutor`: low-risk mechanical or repetitive work
- `researchExecutor`: research and large-context synthesis
- `verifier`: independent comparison against the approved plan
- `fallback`: explicit final fallback binding

Built-in profiles do not bind concrete models. They set `modelMode` to `inherit-current` and use staged roles only as responsibilities. Target-local `inventory-routing` can map these roles from calibrated evidence without hard-coded provider names. See [Provider-Neutral Staged Execution](staged-execution.md).
