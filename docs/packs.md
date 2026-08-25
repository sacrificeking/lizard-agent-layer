# Packs

> [!NOTE]
> **⚡ Ultra High-Dense Quick Check:**
> - **Modular Extensions:** Packs overlay profiles with specialized skills and verification steps without changing profile definitions.
> - **100% Generic:** Stack-agnostic packs (`database-backend`, `frontend-engineering`, `backend-api`, `precision-domain`) adapt dynamically to your repository's technology choices.
> - **Overlay Support:** Target repositories can declare local overlays (`.lizard-agent-layer/packs/`) extending built-in packs.

Packs are reusable bundle manifests for common project shapes. A profile sets the base posture; packs add stack-specific skills, harnesses, verification notes, model preferences, risk level, project size, and install-plan context.

Use packs when a project needs more precision than `minimal`, `standard`, or `enterprise-fullstack` alone. Multiple packs can be combined in one install command.

## Available Packs

| Pack | Use For | Risk | Main Additions |
| --- | --- | --- | --- |
| `frontend-engineering` | Universal frontend UI engineering across React, Angular, Vue, Svelte, Next.js, and Nuxt | medium | Frontend UI architecture, design contracts, dependency discipline, git safety, research audit |
| `database-backend` | Enterprise database engineering across Oracle, PostgreSQL, MSSQL, MySQL, MongoDB | high | Database migrations, transactional DDL, query safety, data quality, security hardening, release |
| `backend-api` | Backend API services across Node/Nest, Java/Spring, Python/FastAPI, Go, .NET, Serverless | high | API contracts, DTO validation, middleware, error envelopes, security hardening, dependency discipline |
| `design-system` | DESIGN.md, design tokens, UI consistency, accessibility-sensitive work | medium | Design-system and frontend engineering review discipline |
| `precision-domain` | High-stakes precision calculations, financial/scientific data provenance, stale-data checks | high | Data provenance, precision calculation assertions, release and dependency discipline |
| `agent-runtime` | Applications that run agents, model routing, tools, memory, evals | high | Runtime-agent boundaries, fallback, permission and evaluation checks |
| `loop-engineering` | Report-only and assisted agent workflows, update watches, release readiness loops | medium | Loop triage, verifier, state sync, constraints, worktree isolation, cost and CI triage skills |
| `security-hardening` | Secrets, auth, permissions, CI, dependencies, production risk | high | Security hardening, git safety, dependency upgrade, research audit |

## Usage

Preview a profile with one pack:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs frontend-engineering
```

Preview an enterprise fullstack app with multiple packs:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile enterprise-fullstack -Packs frontend-engineering,database-backend,backend-api,security-hardening -WritePlan
```

The installer merges pack values into the selected profile before it plans or applies:

- `stack`, `skills`, and `verification` are merged without duplicates.
- `riskLevel` and `projectSize` are raised to the highest selected value.
- `harnesses` from packs are added unless `-Harnesses` is explicitly provided.
- Legacy `modelProfiles` may be overlaid by custom packs, but are deprecated and built-in packs do not inject concrete models. Advanced routing uses a target-local automatic runtime plus fingerprint-matched calibrated inventory data.
- `notes` are appended to the installed `.agent/project-profile.json`.
- `packs` are recorded in the install manifest and plan report.

## Analyzer Integration

`scripts/analyze-target.ps1` emits `recommendedPacks` and appends `-Packs ...` to the preview command when signals match known bundles.

```powershell
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project -ApprovedHarnesses codex -Json
```

Treat analyzer recommendations as an evidence-labelled starting point. Review weak path-group evidence, scan completeness, and qualitative error risk; add or remove packs when repository context contradicts the rules.

## Validation

Run the pack gate directly:

```powershell
pwsh -NoProfile -File .\scripts\pack-report.ps1 -Strict
```

Run the full local CI gate:

```powershell
pwsh -NoProfile -File .\scripts\ci.ps1
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
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Packs project-overlay
```

Overlay packs can extend built-in packs:

```json
{
  "name": "project-overlay",
  "extends": "precision-domain",
  "description": "Project-specific calculation additions.",
  "riskLevel": "high",
  "projectSize": "large",
  "skills": ["frontend-engineering"],
  "harnesses": ["codex"],
  "verification": ["verify project-specific calculation workflows"]
}
```

The installer expands base packs first, records `requested_packs`, records expanded `packs`, and writes `pack_sources` into the install manifest.
