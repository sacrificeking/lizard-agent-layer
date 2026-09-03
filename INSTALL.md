# AI-Guided Installation & Lifecycle Guide

> [!NOTE]
> **⚡ Ultra High-Dense Quick Check:**
> - **Preview-First Mandate:** Never run `-Apply` directly; always generate and inspect a canonical JSON plan first.
> - **Zero-Clobber Guarantee:** Existing `AGENTS.md`, `CLAUDE.md`, or `.github/` instructions are protected with sidecars (`.lizard-agent-layer.md`).
> - **Profiles:** `minimal` (low risk), `standard` (medium risk product), `enterprise-fullstack` (high risk DB/API/Frontend).
> - **Memory Modes:** `curated` (default, team decisions), `private-episodic` (local only), `off` (100% memory-free).
> - **Lifecycle Operations:** Install (`install.ps1`), Update (`update-target.ps1`), Health Check (`doctor.ps1`), Uninstall (`uninstall.ps1`).

Use this file when installing, updating, or removing `lizard-agent-layer` with an AI assistant in Codex, Claude Code, Gemini, Cursor, GitHub Copilot, or a compatible IDE.

Suggested user prompt for initial setup & migration:

> Read `INSTALL.md`, inspect my target repository, check if an existing agent setup is present (`.cursorrules`, `CLAUDE.md`, `.github/copilot-instructions.md`, etc.), plan the migration of project-specific rules into `.agent/memory/`, ask me the required questions one group at a time, and stop after presenting the installation plan. Do not apply changes until I explicitly approve the plan.

## Rules For The Assistant

- Treat this file as an operating procedure, not permission to modify the target.
- Never read or display secret values. Detect only the presence of sensitive paths or configuration names.
- Do not install dependencies, edit CI, access a network, push, commit, or change remote services as part of setup.
- Use repository evidence to recommend options, but let the user decide.
- Run analysis and installation preview before any target mutation.
- Show the exact target path, selected options, planned command, generated paths, conflicts, and manual merge work.
- Require an explicit approval that refers to the final plan before using `-Apply`.
- Stop on unsafe paths, linked destination ancestors, ownership ambiguity, unsupported manifests, or unexpected existing files.

## Step 1: Confirm Scope

Ask:

1. What is the absolute path of the target repository?
2. Is this personal, team, or enterprise use?
3. May the assistant write local repository files after plan approval?
4. Are network access, dependency changes, CI changes, pushes, releases, deployments, or database changes prohibited? Default every unanswered capability to prohibited.

Resolve the path and confirm it is the intended repository root. Do not use the `lizard-agent-layer` source repository itself as a target unless the user explicitly requests a self-installation test.

## Step 2: Analyze Without Mutation

Run:

```powershell
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath <absolute-target-path> -ApprovedHarnesses codex -Json
```

Summarize detected stack, size, risk signals, existing instruction files, recommended profile, packs, skills, and harnesses. Distinguish detected facts from recommendations.

### Legacy Agent Setup Migration (if applicable)

If existing agent instruction files are detected (e.g., `.cursorrules`, `.cursor/rules/`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.clinerules`):
1. **Extract Custom Rules:** Parse and extract project-specific rules into the appropriate `.agent/memory/` categories:
   - **Coding Style & Conventions** $\to$ `.agent/memory/personal/PREFERENCES.md`
   - **Architecture & Technology Decisions** $\to$ `.agent/memory/semantic/DECISIONS.md`
   - **Lessons Learned & Gotchas** $\to$ `.agent/memory/semantic/LESSONS.md`
2. **Present in Preview Plan:** Include the extracted memory items in the installation plan for user review.
3. **Consolidate Wiring:** Ensure the newly installed Lizard adapters (`.cursor/rules/lizard-agent-layer.mdc`, `.github/copilot-instructions.md`, etc.) become the authoritative instructions, eliminating prompt conflicts.

## Step 3: Ask For Installation Choices

Ask the user to confirm or change each group.

### Profile

- `minimal`: small repositories with light guidance.
- `standard`: normal product repositories and the recommended default.
- `enterprise-fullstack`: high-risk repositories with databases, backend APIs, frontend UI, or critical precision/security requirements.

### Harnesses

- `codex`
- `claude-code`
- `gemini`
- `cursor`
- `github-copilot`
- `generic-agents-md`

Select only tools the organization allows. GitHub Copilot uses `.github/copilot-instructions.md`. Existing instruction files must receive sidecars and manual merge guidance rather than silent replacement.

### Packs

- `frontend-engineering`
- `database-backend`
- `backend-api`
- `design-system`
- `precision-domain`
- `agent-runtime`
- `loop-engineering`
- `security-hardening`

Explain why every recommended pack applies. Do not add a pack merely because it exists.

### Memory

- `curated`: recommended; stable preferences, decisions, lessons, and working handoff.
- `private-episodic`: adds a managed episodic seed under a recursively ignored local directory; export or move changed/additional content before switching away.
- `off`: creates no `.agent/memory` namespace, installs no memory policy, and rejects operational managed-memory references or writes.

Never place credentials, customer records, regulated data, private incidents, or unreleased vulnerability details in memory.

### Automation

- No loops: instruction, skills, and memory layer only.
- L1 report-only: bounded analysis and state updates; recommended enterprise maximum by default.
- L2 assisted: one human-approved item in an isolated worktree with separate verifier evidence and human merge review.

L2 does not authorize auto-merge, push, release, deployment, dependency changes, migrations, or secret access.

## Step 4: Present The Decision Record

Before running the installer, present:

| Decision | Selected Value | Reason |
| --- | --- | --- |
| Target |  |  |
| Usage context |  |  |
| Profile |  |  |
| Risk |  |  |
| Harnesses |  |  |
| Packs |  |  |
| Routing policy |  |  |
| Model mode | `inherit-current` | Do not enable inventory routing without an attesting automatic runtime, actual-model reporting, and fingerprint-matched calibration. |
| Memory mode |  |  |
| Automation |  |  |
| Prohibited capabilities |  |  |

Ask the user to correct this record. Do not infer approval from silence.

## Step 5: Generate A Reviewable Plan

Build the command with the confirmed values:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath <absolute-target-path> -Profile <profile> -Harnesses <comma-separated-harnesses> -Packs <comma-separated-packs> -MemoryMode <curated|private-episodic|off> -RoutingPolicy <routing-policy> -ModelMode inherit-current -WritePlan -PlanPath .\.tmp\install-plan.md -CanonicalPlanPath .\.tmp\install-plan.json
```

Omit `-Packs` when none were selected. Review the console output and plan report. If existing instruction files require integration, generate metadata-only merge suggestions:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath <absolute-target-path> -Profile <profile> -Harnesses <comma-separated-harnesses>
```

Present created, skipped, conflicting, sidecar, and manual-merge paths. Confirm that preview did not mutate the target.

## Step 6: Approval Gate

Ask:

> Do you approve this exact installation plan (`APPROVE PLAN <plan_id>`) and authorize the local target writes shown above?

Under ADR 0024, default installations use summary mode: the operator approves the Plan Card and apply verifies the canonical plan, internal digest, and expiry without requiring manual SHA-256 typing. (For regulated or high-assurance workflows, opt-in digest mode is available via `-PlanApprovalMode digest`).

Only an explicit approval permits:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath <absolute-target-path> -Profile <profile> -Harnesses <comma-separated-harnesses> -Packs <comma-separated-packs> -MemoryMode <curated|private-episodic|off> -RoutingPolicy <routing-policy> -ModelMode inherit-current -Apply -ApprovedPlanPath .\.tmp\install-plan.json -HumanApproved
```

Do not add `-Force` or `-ForceManaged` during initial installation.

## Step 7: Verify

Run:

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -TargetPath <absolute-target-path> -Strict
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath <absolute-target-path> -Strict
```

If loop engineering was selected, initialize a specific loop only after a separate preview and approval. Do not initialize L2 merely because the pack was installed.

Conclude with the installed version, manifest path, selected profile, packs, harnesses, manual merges still required, verification results, and the command for a future update preview.

## Developer Quick Reference & CLI Cheat Sheet

For experienced developers who prefer running direct commands without the interactive AI prompt:

### Standard Local Installation (VS Code / Copilot or Cursor)
```powershell
# 1. Preview installation (safe, dry-run)
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath "C:\path\to\your-project" -Profile standard -Harnesses github-copilot -WritePlan -PlanPath .\.tmp\install-plan.md -CanonicalPlanPath .\.tmp\install-plan.json

# 2. Apply installation (Summary mode default)
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath "C:\path\to\your-project" -Profile standard -Harnesses github-copilot -Apply -ApprovedPlanPath .\.tmp\install-plan.json -HumanApproved

# 3. Verify health
pwsh -NoProfile -File .\scripts\doctor.ps1 -TargetPath "C:\path\to\your-project" -Strict
```

> **Note:** Replace `-Harnesses github-copilot` with `cursor`, `claude-code`, `gemini`, or `codex` if that is your team's approved primary harness.

### Enterprise Full-Stack (Database / API / Frontend / Security)
```powershell
# 1. Preview installation
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath "C:\path\to\your-project" -Profile enterprise-fullstack -Harnesses github-copilot -Packs frontend-engineering,database-backend,backend-api,security-hardening -WritePlan -PlanPath .\.tmp\install-plan.md -CanonicalPlanPath .\.tmp\install-plan.json
```
> **Note:** By default, all profiles use summary mode approval (or opt-in `-PlanApprovalMode digest`). If your organization requires cryptographic signed approval, use `scripts/new-approval.ps1` to mint approval materials. On Windows without PowerShell 7 (`pwsh`), use `scripts\lizard.cmd` or `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`.

### Future Updates & Modifications

#### 📋 Copy-Paste Update Prompt for AI Assistant:
```text
Read `docs/update-target.md` in lizard-agent-layer. Run a preview update against this target repository using `scripts/update-target.ps1 -TargetPath "<this-repo-path>" -OutputDir "$HOME/.lizard-agent-layer/.tmp/update-plan"`. Verify that all local memory files and project source code are preserved, show me the plan diff, and wait for my approval before applying.
```

#### 💻 Terminal Commands for Updating:
```powershell
# 1. Preview update against latest layer source
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath "C:\path\to\your-project" -OutputDir "$HOME/.lizard-agent-layer/.tmp/update-plan"

# 2. Apply approved update
pwsh -NoProfile -File .\scripts\update-target.ps1 -TargetPath "C:\path\to\your-project" -OutputDir "$HOME/.lizard-agent-layer/.tmp/update-plan" -Apply -ApprovedPlanPath "$HOME/.lizard-agent-layer/.tmp/update-plan/update-plan.json" -ApprovedPlanSha256 <sha256-from-preview> -HumanApproved
```

### Clean Uninstallation

#### 📋 Copy-Paste Uninstall Prompt for AI Assistant:
```text
Read `UNINSTALL.md` in lizard-agent-layer. Run a preview uninstallation plan using `scripts/uninstall.ps1 -TargetPath "<this-repo-path>" -Scope managed-only -CanonicalPlanPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json"`. Confirm that only layer-owned files will be removed, show me the plan, and wait for my approval before executing the deletion.
```

#### 💻 Terminal Commands for Uninstalling:
```powershell
# 1. Preview uninstall plan (safe, dry-run)
pwsh -NoProfile -File .\scripts\uninstall.ps1 -TargetPath "C:\path\to\your-project" -Scope managed-only -CanonicalPlanPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json"

# 2. Apply verified uninstall
$planSha = (Get-FileHash "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json" -Algorithm SHA256).Hash.ToLowerInvariant()
pwsh -NoProfile -File .\scripts\uninstall.ps1 -TargetPath "C:\path\to\your-project" -Scope managed-only -Apply -ApprovedPlanPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json" -ApprovedPlanSha256 $planSha -HumanApproved
```

### Diagnostic Health Checks
```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -TargetPath "C:\path\to\your-project" -Strict
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath "C:\path\to\your-project" -Strict
```

## Stop Conditions

Stop and ask the user when:

- the target path is unclear or outside the intended repository;
- a destination contains a symlink, junction, mount, or reparse point;
- a manifest is newer than this layer can read;
- existing instructions conflict with generated guidance;
- the organization has not approved an AI provider, model, extension, MCP server, or data category;
- installation would require dependency, CI, remote, secret, migration, or production changes.
