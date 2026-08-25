# Getting Started

> [!NOTE]
> **⚡ Ultra High-Dense Quick Check:**
> - **Zero-Runtime Dependency:** Target repositories receive an independent `.agent/` structure and never depend on `node_modules` or runtime source layers.
> - **End-to-End Safety:** Analyze target (`analyze-target.ps1`) $\to$ Generate JSON Plan (`install.ps1 -WritePlan`) $\to$ Review SHA-256 $\to$ Apply with transaction lock (`-Apply -HumanApproved`).
> - **Harness Compatibility:** Works seamlessly with Cursor, GitHub Copilot, Claude Code, Gemini, and Codex.

This guide is the operational knowledge base for selecting, installing, verifying, updating, operating, and removing `lizard-agent-layer`.

For the shortest safe path, use [`INSTALL.md`](../INSTALL.md) with an IDE assistant. For removal, use [`UNINSTALL.md`](../UNINSTALL.md). For stable failure codes and interrupted operations, use [Troubleshooting](troubleshooting.md).

## 1. Understand The Installation Model

The source repository contains generic profiles, packs, skills, protocols, adapters, schemas, and scripts. A target repository receives only the selected local layer. The target does not depend on this repository at runtime and does not receive its npm development packages.

Every installed skill carries a reviewed `skill.json` package contract. The generated skill manifest binds its version, metadata hash, dependencies, and maximum permissions; strict Doctor revalidates those declarations. Standalone package lifecycle exercises use the preview-first flow described in [Skill packages](skill-packages.md); profile-installed mirrors remain coordinated through the normal layer update flow.

The installed `.agent/` directory is the shared core. Harness adapters expose that core to Codex, Claude Code, Gemini, Cursor, GitHub Copilot, or generic instruction readers.

Installation is not a model permission grant. Repository permissions, IDE settings, organization AI policy, content exclusion, MCP policy, network access, and human approvals remain authoritative.

## 2. Prerequisites

- Clone or obtain a trusted checkout of `lizard-agent-layer`.
- Use PowerShell 7 where available. Windows PowerShell 5.1 is supported for compatibility.
- Install Git when worktree, verifier, update, or release workflows are required.
- Node.js is unnecessary for target installation. It is required only to validate or develop this source repository.
- Know the absolute path of the target repository.
- Review organization policy before exposing internal source to any AI provider or IDE extension.

## 3. Choose A Usage Context

### Personal

Suitable for private repositories where the user controls providers and permissions. Keep preview, secret handling, and explicit remote approvals enabled.

### Team

Use shared curated memory, documented ownership, required code review, and consistent harness selection. Avoid personal preferences that should not govern other contributors.

### Enterprise

Start with [Enterprise Usage](enterprise-usage.md). Confirm approved AI surfaces, models, data classes, content exclusions, MCP servers, repository roles, branch protection, workflow permissions, and audit ownership. Prefer L1 report-only automation until a bounded L2 workflow has explicit approval and evidence.

## 4. Analyze The Target

Run the read-only analyzer:

```powershell
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project -ApprovedHarnesses codex -Json
```

It reports stack and risk signals, existing instruction files, project shape, recommended profile, harnesses, skills, and packs. It ignores common dependency, build, coverage, cache, and scratch directories.

Treat recommendations as a starting point. A filename is a signal, not proof of business risk or ownership.

## 5. Choose A Profile

### `minimal`

Use for small libraries, scripts, and experiments. It installs light generic guidance plus Git safety and research-audit skills.

### `standard`

Use for normal products and team repositories. It includes Codex, Claude Code, Gemini, and GitHub Copilot by default, plus release, dependency, Git safety, and research workflows.

### `enterprise-fullstack`

Use for high-risk enterprise repositories with databases (Oracle, PostgreSQL, MSSQL, MySQL), backend APIs, frontend UI, or critical precision/financial calculations. It adds strict verification, database engineering, and domain skills; it does not authorize remote migrations or un-reviewed production actions.

## 6. Choose Harnesses

| Harness | Use When | Existing Destination Behavior |
| --- | --- | --- |
| `codex` | Codex reads repository `AGENTS.md` and skills | Creates `AGENTS.md` or a sidecar |
| `claude-code` | Claude Code uses repository instructions and skill mirrors | Creates `CLAUDE.md` or a sidecar |
| `gemini` | Gemini uses repository instructions and skill mirrors | Creates `GEMINI.md` or a sidecar |
| `cursor` | Cursor rules should always apply | Creates a dedicated `.cursor` rule |
| `github-copilot` | GitHub Copilot repository custom instructions are approved | Creates Copilot instructions or a sidecar |
| `generic-agents-md` | A tool reads `AGENTS.md` but has no dedicated adapter | Creates `AGENTS.md` or a sidecar |

Codex and Generic share an instruction destination through deterministic precedence. GitHub Copilot uses its own `.github` destination. Undeclared equal or ancestor/descendant collisions fail before target mutation.

## 7. Choose Packs

Packs add reusable project-shape guidance to a profile. Combine only packs justified by the target:

- `frontend-engineering`: universal UI architecture, state management, bundle discipline, and accessibility across React, Vue, Angular, Svelte, etc.
- `database-backend`: enterprise database engineering, transactional DDLs, safe migrations, and query safety across Oracle, PostgreSQL, MSSQL, MySQL, MongoDB, etc.
- `backend-api`: API contracts, REST, GraphQL, gRPC, serverless/edge functions, DTO validation, and middleware.
- `design-system`: design tokens, accessibility, visual consistency, and UI review.
- `precision-domain`: provenance, freshness, calculations, and high-impact precision/financial presentation.
- `agent-runtime`: model routing, tools, memory, fallback, permissions, and evaluations.
- `loop-engineering`: bounded recurring analysis and assisted worktree workflows.
- `security-hardening`: secrets, auth, permissions, dependencies, CI, and production risk.

Pack values merge deterministically. Explicit `-Harnesses` overrides profile and pack harness defaults.

## 8. Confirm Staged Execution

Built-in profiles use `staged-balanced` with `modelMode: inherit-current`. The active IDE or harness model performs strategy, execution, and verification without asking the user to change a picker. Use Advanced inventory routing only when the runtime can select automatically and the target has calibrated its models. See [Provider-Neutral Staged Execution](staged-execution.md).

## 9. Choose Memory Mode

### `curated`

Recommended. Commit stable preferences, accepted decisions, reusable lessons, and current handoff state. Keep entries short, factual, and reviewed.

### `private-episodic`

Adds a managed episodic seed while keeping the entire episodic directory recursively ignored. Use only when organization policy permits it and retention is understood. Export or move changed/additional episodic content before switching away from this mode.

### `off`

Use when project memory is prohibited or unnecessary. No `.agent/memory` namespace or memory policy is installed, and managed instructions contain no operational memory path. Harness instructions and skills can still be installed through the mode-neutral project-context contract.

Never store credentials, tokens, customer records, regulated data, private incident content, or unreleased vulnerability details in memory.

## 10. Choose Automation Level

- No loop runtime: ordinary IDE assistance with protocols and skills.
- L1 report-only: recurring inspection, state, budget, and reports without source changes.
- L2 assisted: one approved item, isolated worktree, command evidence, distinct verifier, and human merge review.

L2 is not autonomy. It cannot auto-merge, push, release, deploy, change dependencies, edit migrations, or access secrets without separate approval.

## 11. Generate The Installation Plan

Example:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot -Packs frontend-engineering,security-hardening -MemoryMode curated -RoutingPolicy staged-balanced -WritePlan -PlanPath .\.tmp\install-plan.md -CanonicalPlanPath .\.tmp\install-plan.json
```

The plan includes profile, risk, memory, harnesses, packs, skills, planned paths, skipped paths, conflicts, sidecars, and exact preview/apply commands. Preview plus `-WritePlan` writes only the selected report outside the target.

Generate merge suggestions for existing instructions:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot
```

Default suggestions are metadata-only and bind existing instructions by path and SHA-256 without reproducing their content.

## 12. Apply After Review

Use the same selections as the approved plan:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses github-copilot -Packs frontend-engineering,security-hardening -RoutingPolicy staged-balanced -Apply -ApprovedPlanPath .\.tmp\install-plan.json -ApprovedPlanSha256 <independently-reviewed-sha256> -HumanApproved
```

Do not use `-Force` during ordinary initial installation. Existing target instructions receive sidecars and manual merge records.

Apply uses a target lock and write-ahead transaction journal. If an operation is interrupted, do not remove the lock manually; follow [Transactions And Recovery](transactions.md).

## 13. Verify Installation

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project -Strict
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

Review manual merge requirements. A strict doctor pass proves installed identity and current content for managed artifacts. In Advanced mode it also checks automatic-runtime readiness, full installed-harness coverage, fingerprint-matched calibrated candidates, and every policy route/data-class combination. Organizational approval and the truthfulness of external runtime attestation remain target responsibilities.

## 14. GitHub Copilot Setup

Select `github-copilot` only when repository custom instructions are allowed. The adapter creates:

```text
.github/copilot-instructions.md
```

When the target already has this file, the layer creates:

```text
.github/copilot-instructions.lizard-agent-layer.md
```

Review and merge the smallest necessary pointer or policy block. Organization owners should separately configure Copilot features, model access, coding agents, CLI, MCP, public-code matching, content exclusion, and audit policy. Verify the policy on every surface in use.

## 15. Initialize Optional Loops

Installing `loop-engineering` adds skills but does not start a loop. Preview a specific L1 pattern:

```powershell
pwsh -NoProfile -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -WritePlan
```

Apply only after review:

```powershell
pwsh -NoProfile -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -Apply
```

Use `loop-run.ps1` to acquire a bounded run lease and record enforced budgets and events. Use `minimal-fix-assist` only for a separately approved L2 item. See [Loop Engineering](loop-engineering.md).

## 16. Update An Installed Target

After obtaining a newer trusted source checkout, preview:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\update-plan
```

Review version relation, requested packs, expanded packs, harnesses, migrations, manifest differences, and ownership conflicts. Apply conservatively:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -OutputDir .\.tmp\update-plan -Apply -ApprovedPlanPath .\.tmp\update-plan\update-plan.json -ApprovedPlanSha256 <independently-reviewed-sha256> -HumanApproved
```

`-ForceManaged` is not a general overwrite mode. It refreshes only artifacts with unchanged layer-owned provenance and preserves ambiguous or modified files.

## 17. Remove The Layer

Use [`UNINSTALL.md`](../UNINSTALL.md) with an AI assistant. Choose managed-only, complete, or export-then-complete removal. The assistant must inventory manifest ownership, show exact paths, request approval, preserve user-owned content, and verify residue.

There is no generic recursive uninstall command because common directories may contain project-owned files.

## 18. Common Scenarios

### Small private library

Use `minimal`, curated memory, one or two permitted harnesses, no packs unless analysis identifies a real need, and no loops initially.

### Team product repository

Use `standard`, Codex/Claude/Gemini/Copilot as actually licensed, `frontend-engineering` when relevant, curated team memory, required review, and L1 only until signal quality is trusted.

### Enterprise GitHub repository

Complete the enterprise decision checklist, select approved harnesses only, preserve organization-owned Copilot instructions through sidecars, disable memory when policy requires it, keep workflows read-only, and require explicit approval for external tools and agent modes.

### High-risk enterprise full-stack system

Use `enterprise-fullstack` plus applicable database, API, precision, and security packs (`database-backend`, `backend-api`, `precision-domain`, `security-hardening`). Treat auth, migrations, calculations, data provenance, releases, and production operations as human-gated. Perform a fresh, evidence-based verification pass and use an independent verifier when the environment provides one automatically.

## 19. Troubleshooting

- Existing instruction file: use sidecar merge suggestions; do not overwrite.
- Linked path rejection: replace the linked destination with an approved physical directory or choose another target.
- Transaction lock: use `transaction-recover.ps1` preview and human-approved recovery.
- Future manifest schema: update the source layer before touching the target.
- Verifier rejection: correct worktree, branch, command, role, lifecycle, or evidence mismatch; never bypass it.
- Drift after intentional source changes: review exact artifact changes before updating the drift baseline.

See [Troubleshooting And Recovery](troubleshooting.md) for stable codes and detailed procedures.

## 20. Customizing Profiles, Skills & Protocols For Your Team

Organizations and teams can define their own standardized profiles and domain skills:

### Creating a Custom Team Profile
Add a JSON file under `profiles/<your-team-profile>.json`:
```json
{
  "name": "enterprise-backend",
  "description": "Standard backend profile with PostgreSQL, security hardening, and staged execution.",
  "riskLevel": "high",
  "memoryMode": "curated",
  "routingPolicy": "staged-balanced",
  "harnesses": ["cursor", "claude-code", "github-copilot"],
  "skills": ["git-safety", "security-hardening", "staged-execution", "dependency-upgrade"],
  "packs": ["security-hardening"]
}
```

### Adding Reusable Domain Skills
1. Create `skills/<skill-name>/SKILL.md` (instructions with frontmatter `name` and `description`).
2. Create `skills/<skill-name>/skill.json` (versioned metadata schema).
3. Re-run `pwsh -File .\scripts\pack-report.ps1 -Strict` to validate skill metadata.

### Applying Custom Profile to Target Projects
```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath <path-to-project> -Profile enterprise-backend -Apply -HumanApproved
```

## 21. Source Repository Validation

Contributors to `lizard-agent-layer` run:

```powershell
npm ci
pwsh -NoProfile -File .\scripts\ci.ps1
```

Target users do not need this development workflow. Toolchain details are recorded in [Dependencies](dependencies.md).
