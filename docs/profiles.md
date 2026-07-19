# Profiles

Profiles describe how much agent infrastructure a target project should receive.

## minimal

For small scripts, libraries, or experiments. Installs generic instructions by default plus git safety and research audit skills.

## standard

For normal product repositories. Installs Codex, Claude Code, Gemini, and GitHub Copilot adapters by default, plus release, dependency upgrade, git safety, and research audit workflows.

## supabase-react-finance

For high-risk React/Vite/Supabase finance applications. Installs Codex, Claude Code, Gemini, and GitHub Copilot adapters by default, plus frontend, design system, Supabase, edge functions, data quality, release, git safety, dependency, and research audit skills.

## Harness override

Use `-Harnesses` with `scripts/install.ps1` to override profile defaults:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,github-copilot,cursor
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
