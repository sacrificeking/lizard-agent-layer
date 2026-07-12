# Getting Started

This guide is the operational knowledge base for selecting, installing, verifying, updating, operating, and removing `lizard-agent-layer`.

For the shortest safe path, use [`INSTALL.md`](../INSTALL.md) with an IDE assistant. For removal, use [`UNINSTALL.md`](../UNINSTALL.md). For stable failure codes and interrupted operations, use [Troubleshooting](troubleshooting.md).

## 1. Understand The Installation Model

The source repository contains generic profiles, packs, skills, protocols, adapters, schemas, and scripts. A target repository receives only the selected local layer. The target does not depend on this repository at runtime and does not receive its npm development packages.

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
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project -Json
```

It reports stack and risk signals, existing instruction files, project shape, recommended profile, harnesses, skills, and packs. It ignores common dependency, build, coverage, cache, and scratch directories.

Treat recommendations as a starting point. A filename is a signal, not proof of business risk or ownership.

## 5. Choose A Profile

### `minimal`

Use for small libraries, scripts, and experiments. It installs light generic guidance plus Git safety and research-audit skills.

### `standard`

Use for normal products and team repositories. It includes Codex, Claude Code, Gemini, and GitHub Copilot by default, plus release, dependency, Git safety, and research workflows.

### `supabase-react-finance`

Use when mistakes could affect authentication, database migrations, financial interpretation, user money, or production data. It adds stricter verification and domain skills; it does not authorize remote migrations or production actions.

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

- `frontend-product`: React, Vite, TypeScript, and frontend delivery.
- `design-system`: design tokens, accessibility, visual consistency, and UI review.
- `supabase-react`: database, auth, Edge Functions, generated types, and migrations.
- `finance-app`: provenance, freshness, calculations, and high-impact financial presentation.
- `agent-runtime`: model routing, tools, memory, fallback, permissions, and evaluations.
- `loop-engineering`: bounded recurring analysis and assisted worktree workflows.
- `security-hardening`: secrets, auth, permissions, dependencies, CI, and production risk.

Pack values merge deterministically. Explicit `-Harnesses` overrides profile and pack harness defaults.

## 8. Choose Memory Mode

### `curated`

Recommended. Commit stable preferences, accepted decisions, reusable lessons, and current handoff state. Keep entries short, factual, and reviewed.

### `private-episodic`

Allows local raw history while keeping it ignored. Use only when organization policy permits it and retention is understood.

### `off`

Use when project memory is prohibited or unnecessary. Harness instructions and skills can still be installed.

Never store credentials, tokens, customer records, regulated data, private incident content, or unreleased vulnerability details in memory.

## 9. Choose Automation Level

- No loop runtime: ordinary IDE assistance with protocols and skills.
- L1 report-only: recurring inspection, state, budget, and reports without source changes.
- L2 assisted: one approved item, isolated worktree, command evidence, distinct verifier, and human merge review.

L2 is not autonomy. It cannot auto-merge, push, release, deploy, change dependencies, edit migrations, or access secrets without separate approval.

## 10. Generate The Installation Plan

Example:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,github-copilot -Packs frontend-product,security-hardening -WritePlan
```

The plan includes profile, risk, memory, harnesses, packs, skills, planned paths, skipped paths, conflicts, sidecars, and exact preview/apply commands. Preview plus `-WritePlan` writes only the selected report outside the target.

Generate merge suggestions for existing instructions:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,github-copilot
```

Default suggestions are metadata-only and bind existing instructions by path and SHA-256 without reproducing their content.

## 11. Apply After Review

Use the same selections as the approved plan:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,github-copilot -Packs frontend-product,security-hardening -Apply
```

Do not use `-Force` during ordinary initial installation. Existing target instructions receive sidecars and manual merge records.

Apply uses a target lock and write-ahead transaction journal. If an operation is interrupted, do not remove the lock manually; follow [Transactions And Recovery](transactions.md).

## 12. Verify Installation

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project -Strict
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

Review manual merge requirements. A strict doctor pass proves installed identity and current content for managed artifacts; it does not prove that an organization has approved the selected model or IDE.

## 13. GitHub Copilot Setup

Select `github-copilot` only when repository custom instructions are allowed. The adapter creates:

```text
.github/copilot-instructions.md
```

When the target already has this file, the layer creates:

```text
.github/copilot-instructions.lizard-agent-layer.md
```

Review and merge the smallest necessary pointer or policy block. Organization owners should separately configure Copilot features, model access, coding agents, CLI, MCP, public-code matching, content exclusion, and audit policy. Verify the policy on every surface in use.

## 14. Initialize Optional Loops

Installing `loop-engineering` adds skills but does not start a loop. Preview a specific L1 pattern:

```powershell
pwsh -NoProfile -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -WritePlan
```

Apply only after review:

```powershell
pwsh -NoProfile -File .\scripts\loop-init.ps1 -TargetPath D:\path\to\project -Pattern daily-triage -Apply
```

Use `loop-run.ps1` to acquire a bounded run lease and record enforced budgets and events. Use `minimal-fix-assist` only for a separately approved L2 item. See [Loop Engineering](loop-engineering.md).

## 15. Update An Installed Target

After obtaining a newer trusted source checkout, preview:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project
```

Review version relation, requested packs, expanded packs, harnesses, migrations, manifest differences, and ownership conflicts. Apply conservatively:

```powershell
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath D:\path\to\project -Apply
```

`-ForceManaged` is not a general overwrite mode. It refreshes only artifacts with unchanged layer-owned provenance and preserves ambiguous or modified files.

## 16. Remove The Layer

Use [`UNINSTALL.md`](../UNINSTALL.md) with an AI assistant. Choose managed-only, complete, or export-then-complete removal. The assistant must inventory manifest ownership, show exact paths, request approval, preserve user-owned content, and verify residue.

There is no generic recursive uninstall command because common directories may contain project-owned files.

## 17. Common Scenarios

### Small private library

Use `minimal`, curated memory, one or two permitted harnesses, no packs unless analysis identifies a real need, and no loops initially.

### Team product repository

Use `standard`, Codex/Claude/Gemini/Copilot as actually licensed, `frontend-product` when relevant, curated team memory, required review, and L1 only until signal quality is trusted.

### Enterprise GitHub repository

Complete the enterprise decision checklist, select approved harnesses only, preserve organization-owned Copilot instructions through sidecars, disable memory when policy requires it, keep workflows read-only, and require explicit approval for external tools and agent modes.

### High-risk Supabase or finance system

Use `supabase-react-finance` plus applicable security, Supabase, finance, and frontend packs. Treat auth, migrations, calculations, data provenance, releases, and production operations as human-gated. Use a strong independent verifier.

## 18. Troubleshooting

- Existing instruction file: use sidecar merge suggestions; do not overwrite.
- Linked path rejection: replace the linked destination with an approved physical directory or choose another target.
- Transaction lock: use `transaction-recover.ps1` preview and human-approved recovery.
- Future manifest schema: update the source layer before touching the target.
- Verifier rejection: correct worktree, branch, command, role, lifecycle, or evidence mismatch; never bypass it.
- Drift after intentional source changes: review exact artifact changes before updating the drift baseline.

See [Troubleshooting And Recovery](troubleshooting.md) for stable codes and detailed procedures.

## 19. Source Repository Validation

Contributors to `lizard-agent-layer` run:

```powershell
npm ci
pwsh -NoProfile -File .\scripts\ci.ps1
```

Target users do not need this development workflow. Toolchain details are recorded in [Dependencies](dependencies.md).
