# lizard-agent-layer

Portable agent infrastructure for projects that need consistent AI-assisted development without copying a whole agent stack into every repository.

`lizard-agent-layer` is the source of truth for reusable agent logic. Target projects receive a tailored local instance: project profile, curated memory files, safety protocols, and Codex-readable skills.

## What it provides

- Project profiles for different sizes, stacks, and risk levels.
- Codex-friendly skills under `.agents/skills/`.
- Local project memory under `.agent/memory/`.
- Permission, memory, secret, and release protocols.
- Preview-first installers that avoid clobbering target files.
- Doctor, validation, and smoke-test scripts.

## Profiles

- `minimal`: small repositories, light guidance, few skills.
- `standard`: normal product repositories with release and git safety.
- `supabase-react-finance`: high-risk React/Vite/Supabase finance applications.

## Quick start

Preview first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard
```

Apply after reviewing the plan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Apply
```

Audit a target project:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project
```

Validate this repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
```

## Safety stance

- Generic logic lives here.
- Project decisions and curated lessons live in the target project.
- Raw episodic logs stay private unless a project explicitly opts in.
- Existing target files are skipped by default.
- Existing `AGENTS.md` is not overwritten; a sidecar merge file is generated.
- High-risk projects get stricter gates than small utility repos.

## Documentation

- [Architecture](docs/architecture.md)
- [Getting started](docs/getting-started.md)
- [Profiles](docs/profiles.md)
- [Safety model](docs/safety-model.md)
- [Skill authoring](docs/skill-authoring.md)
- [Roadmap](docs/roadmap.md)
