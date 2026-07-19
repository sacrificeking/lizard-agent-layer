# lizard-agent-layer

Portable, preview-first agent infrastructure for repositories that use Codex, Claude Code, Gemini, Cursor, GitHub Copilot, or generic `AGENTS.md`-compatible tools.

`lizard-agent-layer` keeps reusable agent logic in one source repository and installs a tailored local layer into each target project. The installed layer combines project profile, curated memory, permissions, skills, harness instructions, update metadata, and optional bounded loops without making a single model or IDE the source of truth.

## Highlights

- Multi-harness adapters for Codex, Claude Code, Gemini, Cursor, GitHub Copilot, and generic `AGENTS.md` tools.
- Provider-neutral 10-80-10 staged execution that keeps the active model by default, with optional calibrated automatic routing.
- Profiles for small repositories, normal product development, and high-risk React/Supabase/finance systems.
- Reusable packs for frontend, design systems, Supabase, finance, security, agent runtimes, and loop engineering.
- Preview-first installation and updates with explicit plans, ownership manifests, content hashes, and manual merge guidance.
- Conservative handling of existing project instructions through sidecars instead of silent replacement.
- Canonical path containment, linked-ancestor rejection, transaction journals, rollback, and interrupted-operation recovery.
- Separate documentation quality and executable behavioral-readiness evidence.
- L1 report-only and L2 assisted loops with leases, budgets, attempts, atomic state, hash-chained events, worktree isolation, verifier evidence, and no auto-merge.
- Local CI plus GitHub-hosted Windows, Ubuntu, and macOS gates.
- AI-guided installation and removal through [`INSTALL.md`](INSTALL.md) and [`UNINSTALL.md`](UNINSTALL.md).

## How It Fits Together

```text
lizard-agent-layer source repository
  profiles + packs + skills + protocols + adapters + scripts
                         |
                  preview and review
                         |
                         v
target repository
  .agent/                  shared profile, memory, protocols, skills, manifest
  .agent/routing/          staged policy and private receipts; optional Advanced runtime/inventory
  AGENTS.md                Codex or generic instructions
  CLAUDE.md                Claude Code instructions
  GEMINI.md                Gemini instructions
  .cursor/                 Cursor rules and optional skill mirrors
  .github/                 GitHub Copilot repository instructions
  harness skill mirrors    only where the selected tool supports them
```

Project-local instructions remain authoritative. Adapters translate the shared `.agent/` core into files each harness understands.

## Supported Harnesses

| Harness | Instruction Destination | Skill Mirror |
| --- | --- | --- |
| Codex | `AGENTS.md` | `.agents/skills/` |
| Claude Code | `CLAUDE.md` | `.claude/skills/` |
| Gemini | `GEMINI.md` | `.gemini/skills/` |
| Cursor | `.cursor/rules/lizard-agent-layer.mdc` | `.cursor/skills/` |
| GitHub Copilot | `.github/copilot-instructions.md` | Shared `.agent/skills/` guidance |
| Generic | `AGENTS.md` | None |

When an instruction destination already exists, the installer creates a dedicated sidecar and records a manual merge. It does not overwrite the existing file by default.

## Requirements

- Git `2.31+` recommended.
- PowerShell 7 for portable use on Windows, Linux, and macOS.
- Windows PowerShell 5.1 remains a tested compatibility host.
- Node.js `22+` only for schema validation and repository CI; Node.js 24 LTS is the release baseline.
- `npm ci` once after cloning this source repository.

Target projects do not receive npm dependencies from this repository.

## Recommended Start: Use Your IDE Assistant

Open [`INSTALL.md`](INSTALL.md) and ask your IDE assistant:

> Read `INSTALL.md`, inspect my target repository, ask me the required questions one group at a time, and stop after presenting the installation plan. Do not apply changes until I explicitly approve the plan.

The runbook guides the assistant through target analysis, usage context, profile, harnesses, packs, memory, automation level, plan review, approval, installation, and verification.

## Manual Quick Start

Analyze a target without mutation:

```powershell
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project -Json
```

Generate a reviewable plan:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,github-copilot -Packs frontend-product,security-hardening -WritePlan
```

Apply only after reviewing that exact plan:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,github-copilot -Packs frontend-product,security-hardening -Apply
```

Verify the installed target:

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project -Strict
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

See the complete [Getting Started guide](docs/getting-started.md) for selection help and alternative scenarios.

## Profiles

| Profile | Intended Use | Default Risk |
| --- | --- | --- |
| `minimal` | Small scripts, libraries, and experiments | low |
| `standard` | Normal product repositories and team development | medium |
| `supabase-react-finance` | React/Supabase systems with auth, migrations, finance, or high-impact data | high |

Profiles are starting points. Packs and explicit harness overrides adapt them without copying profile definitions.

## Packs

| Pack | Adds |
| --- | --- |
| `frontend-product` | React, Vite, TypeScript, frontend and dependency discipline |
| `design-system` | UI consistency, accessibility, and design-system review |
| `supabase-react` | Supabase, auth, migrations, Edge Functions, and data quality |
| `finance-app` | Financial data provenance, stale-data checks, and release controls |
| `agent-runtime` | Tool permissions, model routing, fallback, memory, and evaluation boundaries |
| `loop-engineering` | Report-only and assisted loops, verifier, state, budget, and worktrees |
| `security-hardening` | Secrets, permissions, dependencies, CI, and production-risk controls |

## Updates

Preview an update against the current source checkout:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project
```

The update plan reports version relation, profile, requested and expanded packs, harnesses, managed-path differences, ownership conflicts, and migration requirements. Apply only after review:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Apply
```

Locally modified, user-owned, adopted, and integrity-unknown files are preserved unless a separate evidence-based decision is made.

## Removal

Use [`UNINSTALL.md`](UNINSTALL.md) with an IDE assistant. It inventories the install manifest, distinguishes owned and modified content, optionally exports memory and loop state, presents an exact removal plan, requires approval, and verifies that no layer residue remains.

There is intentionally no blanket uninstall command that recursively deletes common instruction directories.

## Safety Model

- Preview is the default for installation, update, loop initialization, worktree creation, recovery, and merge guidance.
- All target and report writes are authorized against explicit roots immediately before mutation.
- Existing linked ancestors are rejected instead of followed.
- Apply operations use per-target locks and write-ahead transaction journals.
- Layer ownership is artifact-specific and hash-bound.
- Default reports are metadata-only and do not copy existing private instructions.
- Push, release, deploy, dependency, CI, secret, migration, and production actions require explicit approval.
- L2 verifier PASS never grants merge permission; a human still decides.

Read [Safety Model](docs/safety-model.md), [Enterprise Usage](docs/enterprise-usage.md), and [Security Policy](SECURITY.md) before organizational rollout.

## Enterprise Use

The MIT license permits commercial use, modification, and redistribution subject to its notice requirements. Enterprise suitability still depends on organizational approval of AI providers, models, IDE extensions, data handling, content exclusions, MCP servers, repository permissions, CI runners, and legal obligations.

The repository contains no intentional telemetry or runtime network client. External data flow occurs only through explicitly invoked package retrieval, Git/GitHub operations, CI, or the selected AI and IDE services.

## Loop Engineering

L1 is the recommended default: inspect, report, update bounded state, and stop. L2 is available for one approved item in an isolated sibling worktree with a distinct verifier and human merge review. L3 is defined conceptually but is not shipped as an autonomous product mode.

See [Loop Engineering](docs/loop-engineering.md) and [L2 Evidence](docs/loop-evidence.md).

## Repository Development

Install the locked validator dependencies and run all gates:

```powershell
npm ci
pwsh -NoProfile -File .\scripts\ci.ps1
```

The canonical runner validates schemas and negative mutations, architecture contracts, focused safety tests, packs, drift, quality, smoke behavior, and every profile/adapter matrix combination.

Dependency and toolchain versions are recorded in [Dependency And Toolchain Snapshot](docs/dependencies.md).

## Documentation

- [Getting Started](docs/getting-started.md)
- [AI-Guided Installation](INSTALL.md)
- [AI-Guided Uninstall](UNINSTALL.md)
- [Enterprise Usage](docs/enterprise-usage.md)
- [Security Policy](SECURITY.md)
- [Architecture](docs/architecture.md)
- [Architecture Decisions](docs/adr/README.md)
- [Profiles](docs/profiles.md)
- [Provider-Neutral Staged Execution](docs/staged-execution.md)
- [Packs](docs/packs.md)
- [Target Analysis](docs/target-analysis.md)
- [Install Plans](docs/install-plans.md)
- [Updates](docs/update-target.md)
- [Transactions And Recovery](docs/transactions.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Adapter Matrix](docs/adapter-matrix.md)
- [Schema Validation](docs/schema-validation.md)
- [Quality And Maturity](docs/quality-registry.md)
- [Dependencies](docs/dependencies.md)
- [Contributing](CONTRIBUTING.md)

## License

[MIT](LICENSE)
