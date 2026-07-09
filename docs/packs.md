# Packs

Packs are reusable bundle manifests for common project shapes. A profile sets the base posture; packs add stack-specific skills, harnesses, verification notes, model preferences, risk level, project size, and install-plan context.

Use packs when a project needs more precision than `minimal`, `standard`, or `supabase-react-finance` alone. Multiple packs can be combined in one install command.

## Available Packs

| Pack | Use For | Risk | Main Additions |
| --- | --- | --- | --- |
| `frontend-product` | React, Vite, TypeScript product frontends | medium | Frontend, design, dependency, git safety, research audit |
| `design-system` | DESIGN.md, UI consistency, accessibility-sensitive work | medium | Design-system and frontend review discipline |
| `supabase-react` | React plus Supabase database, auth, edge functions, generated types | high | Supabase, edge functions, data quality, security hardening |
| `finance-app` | Finance, crypto, DeFi, stocks, market data, DCA, portfolio workflows | high | Data provenance, stale-data checks, release and dependency discipline |
| `agent-runtime` | Applications that run agents, model routing, tools, memory, evals | high | Runtime-agent boundaries, fallback, permission and evaluation checks |
| `loop-engineering` | Report-only and assisted agent workflows, update watches, release readiness loops | medium | Loop triage, verifier, state sync, constraints, worktree isolation, cost and CI triage skills |
| `security-hardening` | Secrets, auth, permissions, CI, dependencies, production risk | high | Security hardening, git safety, dependency upgrade, research audit |

## Usage

Preview a profile with one pack:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs frontend-product
```

Preview a high-risk Supabase finance app with multiple packs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile supabase-react-finance -Packs frontend-product,supabase-react,finance-app,security-hardening -WritePlan
```

The installer merges pack values into the selected profile before it plans or applies:

- `stack`, `skills`, and `verification` are merged without duplicates.
- `riskLevel` and `projectSize` are raised to the highest selected value.
- `harnesses` from packs are added unless `-Harnesses` is explicitly provided.
- `modelProfiles` are overlaid by pack-specific recommendations.
- `notes` are appended to the installed `.agent/project-profile.json`.
- `packs` are recorded in the install manifest and plan report.

## Analyzer Integration

`scripts/analyze-target.ps1` emits `recommendedPacks` and appends `-Packs ...` to the preview command when signals match known bundles.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project -Json
```

Treat analyzer recommendations as a high-quality starting point. Add or remove packs when the repository has unusual constraints.

## Validation

Run the pack gate directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\pack-report.ps1 -Strict
```

Run the full local CI gate:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ci.ps1
```

`validate.ps1` verifies pack shape and references. `pack-report.ps1 -Strict` checks pack coverage, missing skills, invalid harnesses, invalid model profiles, and suspiciously empty bundle fields.

## Authoring Rules

- Keep pack names lowercase hyphen-case and match the filename.
- Prefer packs for reusable project shapes, not one-off repository quirks.
- Add only skills and harnesses that should apply together most of the time.
- Keep verification steps concrete enough to guide an agent but generic enough to adapt per repository.
- Use high risk when incorrect behavior could affect secrets, auth, production data, user money, or runtime agent permissions.
- Keep loop packs report-only by default. Promote to L2 only for human-approved assisted worktree fixes with verifier reports and no auto-merge.

## Target Pack Overlays

Target projects can define local packs without changing this repository:

```text
.lizard-agent-layer/
  packs/
    project-overlay.json
```

Install an overlay pack by name:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs project-overlay
```

Overlay packs can extend built-in packs:

```json
{
  "name": "project-overlay",
  "extends": "finance-app",
  "description": "Project-specific finance additions.",
  "riskLevel": "high",
  "projectSize": "large",
  "skills": ["frontend-react"],
  "harnesses": ["codex"],
  "verification": ["verify project-specific finance workflows"]
}
```

The installer expands base packs first, records `requested_packs`, records expanded `packs`, and writes `pack_sources` into the install manifest.
