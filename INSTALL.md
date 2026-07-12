# AI-Guided Installation

Use this file when installing `lizard-agent-layer` into another repository with an AI assistant in Codex, Claude Code, Gemini, Cursor, GitHub Copilot, or a compatible IDE.

Suggested user prompt:

> Read `INSTALL.md`, inspect my target repository, ask me the required questions one group at a time, and stop after presenting the installation plan. Do not apply changes until I explicitly approve the plan.

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
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath <absolute-target-path> -Json
```

Summarize detected stack, size, risk signals, existing instruction files, recommended profile, packs, skills, and harnesses. Distinguish detected facts from recommendations.

## Step 3: Ask For Installation Choices

Ask the user to confirm or change each group.

### Profile

- `minimal`: small repositories with light guidance.
- `standard`: normal product repositories and the recommended default.
- `supabase-react-finance`: high-risk React, Supabase, finance, auth, or migration-heavy repositories.

### Harnesses

- `codex`
- `claude-code`
- `gemini`
- `cursor`
- `github-copilot`
- `generic-agents-md`

Select only tools the organization allows. GitHub Copilot uses `.github/copilot-instructions.md`. Existing instruction files must receive sidecars and manual merge guidance rather than silent replacement.

### Packs

- `frontend-product`
- `design-system`
- `supabase-react`
- `finance-app`
- `agent-runtime`
- `loop-engineering`
- `security-hardening`

Explain why every recommended pack applies. Do not add a pack merely because it exists.

### Memory

- `curated`: recommended; stable preferences, decisions, lessons, and working handoff.
- `private-episodic`: permits local raw history but keeps it ignored and private.
- `off`: for repositories where project memory is not permitted.

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
| Memory mode |  |  |
| Automation |  |  |
| Prohibited capabilities |  |  |

Ask the user to correct this record. Do not infer approval from silence.

## Step 5: Generate A Reviewable Plan

Build the command with the confirmed values:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath <absolute-target-path> -Profile <profile> -Harnesses <comma-separated-harnesses> -Packs <comma-separated-packs> -WritePlan
```

Omit `-Packs` when none were selected. Review the console output and plan report. If existing instruction files require integration, generate metadata-only merge suggestions:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath <absolute-target-path> -Profile <profile> -Harnesses <comma-separated-harnesses>
```

Present created, skipped, conflicting, sidecar, and manual-merge paths. Confirm that preview did not mutate the target.

## Step 6: Approval Gate

Ask:

> Do you approve this exact installation plan and authorize the local target writes shown above?

Only an explicit approval permits:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -TargetPath <absolute-target-path> -Profile <profile> -Harnesses <comma-separated-harnesses> -Packs <comma-separated-packs> -Apply
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

## Stop Conditions

Stop and ask the user when:

- the target path is unclear or outside the intended repository;
- a destination contains a symlink, junction, mount, or reparse point;
- a manifest is newer than this layer can read;
- existing instructions conflict with generated guidance;
- the organization has not approved an AI provider, model, extension, MCP server, or data category;
- installation would require dependency, CI, remote, secret, migration, or production changes.
