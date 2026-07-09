# lizard-agent-layer

Portable agent infrastructure for projects that need consistent AI-assisted development across Codex, Claude, Gemini, Cursor, and generic AGENTS.md-compatible tools.

`lizard-agent-layer` is the source of truth for reusable agent logic. Target projects receive a tailored local instance: project profile, curated memory files, safety protocols, handoff protocol, harness adapters, mirrored skills, reviewable install plans, and optional merge patch reports.

## What it provides

- Project profiles for different sizes, stacks, risk levels, harnesses, and model roles.
- Curated packs for frontend products, Supabase React apps, finance workflows, agent runtimes, design systems, security hardening, and loop engineering.
- Codex, Claude Code, Gemini, Cursor, and generic adapters.
- Codex-friendly skills under `.agents/skills/` and harness-specific mirrors where useful.
- Local project memory under `.agent/memory/`.
- Permission, memory, secret, handoff, and release protocols.
- Preview-first installers that avoid clobbering target files.
- Optional install plan reports with merge suggestions for existing instruction files.
- Plan-first target updates with version comparison, manifest diff, apply mode, force-managed refresh, and update history.
- L1/report-only and L2 assisted loop engineering runtime with patterns, state, budget, run-log, constraints, worktree isolation, verifier reports, audit, sync, and cost tooling.
- Standalone merge suggestion reports with patch and copy-block artifacts.
- Target analyzer for profile, harness, skill, pack, monorepo, non-Node, and risk recommendations.
- Adapter matrix tests for every profile/harness combination.
- Local CI runner plus GitHub Actions workflow for validate, packs, drift, quality, smoke, and matrix gates.
- Quality registry with scoring, risk labels, maturity levels, drift detection, and Markdown/JSON reports.
- Doctor, validation, upgrade, manifest-sync, manifest diff, update-target, scoring, and smoke-test scripts.

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs frontend-product -WritePlan
```

Write a profile-only plan when packs are not needed:

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

Run a local pack report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\pack-report.ps1 -Strict
```

Run a local drift report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\drift-check.ps1
```

Run an installed-target manifest diff:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

Generate a reviewable update plan for an installed target:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project
```

Apply the reviewed update conservatively:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Apply
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
- [Packs](docs/packs.md)
- [Install plans](docs/install-plans.md)
- [Merge suggestions](docs/merge-suggestions.md)
- [Manifest diff](docs/manifest-diff.md)
- [Update targets](docs/update-target.md)
- [Loop engineering](docs/loop-engineering.md)
- [Target analysis](docs/target-analysis.md)
- [Adapter matrix](docs/adapter-matrix.md)
- [CI](docs/ci.md)
- [Drift intelligence](docs/drift-intelligence.md)
- [Safety model](docs/safety-model.md)
- [Skill authoring](docs/skill-authoring.md)
- [Skill maturity](docs/skill-maturity.md)
- [Roadmap](docs/roadmap.md)
