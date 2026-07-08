# lizard-agent-layer

Portable agent infrastructure for projects that need consistent AI-assisted development across Codex, Claude, Gemini, Cursor, and generic AGENTS.md-compatible tools.

`lizard-agent-layer` is the source of truth for reusable agent logic. Target projects receive a tailored local instance: project profile, curated memory files, safety protocols, handoff protocol, harness adapters, mirrored skills, reviewable install plans, and optional merge patch reports.

## What it provides

- Project profiles for different sizes, stacks, risk levels, harnesses, and model roles.
- Codex, Claude Code, Gemini, Cursor, and generic adapters.
- Codex-friendly skills under `.agents/skills/` and harness-specific mirrors where useful.
- Local project memory under `.agent/memory/`.
- Permission, memory, secret, handoff, and release protocols.
- Preview-first installers that avoid clobbering target files.
- Optional install plan reports with merge suggestions for existing instruction files.
- Standalone merge suggestion reports with patch and copy-block artifacts.
- Target analyzer for profile, harness, and skill recommendations.
- Adapter matrix tests for every profile/harness combination.
- Local CI runner plus GitHub Actions workflow for validate, quality, smoke, and matrix gates.
- Quality registry with scoring, risk labels, maturity levels, drift detection, and Markdown/JSON reports.
- Doctor, validation, upgrade, manifest-sync, scoring, and smoke-test scripts.

## Profiles

- `minimal`: small repositories, light generic guidance, few skills.
- `standard`: normal product repositories with Codex, Claude, Gemini, release, and git safety.
- `supabase-react-finance`: high-risk React/Vite/Supabase finance applications with multi-model handoff.

## Quick start

Analyze a target first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project
```

Write a reviewable install plan without touching the target project:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -WritePlan
```

Generate concrete merge patches for existing instruction files:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard
```

Preview the recommended or chosen profile:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard
```

Override harnesses if needed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,cursor
```

Apply after reviewing the plan and merge patches:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Apply
```

Audit a target project:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project
```

Run a local drift report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\drift-check.ps1
```

Run a local quality report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\score-layer.ps1
```

Run local CI for this repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1
```

Validate individual gates:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\matrix.ps1
```

## Safety stance

- Generic logic lives here.
- Project decisions and curated lessons live in the target project.
- Raw episodic logs stay private unless a project explicitly opts in.
- Preview mode remains read-only for target projects, even when writing reports outside the target.
- Existing target files are skipped by default.
- Existing harness instruction files get sidecar merge files instead of silent overwrites.
- Install manifests, plan reports, and merge reports preserve manual merge suggestions.
- High-risk projects get stricter gates than small utility repos.

## Documentation

- [Architecture](docs/architecture.md)
- [Getting started](docs/getting-started.md)
- [Profiles](docs/profiles.md)
- [Install plans](docs/install-plans.md)
- [Merge suggestions](docs/merge-suggestions.md)
- [Target analysis](docs/target-analysis.md)
- [Adapter matrix](docs/adapter-matrix.md)
- [CI](docs/ci.md)
- [Drift intelligence](docs/drift-intelligence.md)
- [Safety model](docs/safety-model.md)
- [Skill authoring](docs/skill-authoring.md)
- [Skill maturity](docs/skill-maturity.md)
- [Roadmap](docs/roadmap.md)



