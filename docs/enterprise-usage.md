# Enterprise Usage

`lizard-agent-layer` can be used in commercial repositories under the MIT license, subject to organizational legal, security, privacy, and software-composition review. The project provides technical guardrails; it does not certify compliance with a particular law, standard, contract, or internal policy.

## Local Data Flow

The PowerShell scripts inspect the selected repository, write only to explicitly authorized target or report roots, and create no telemetry or HTTP clients. Declarative profiles, memory, skills, manifests, reports, and loop state remain local unless a user, IDE, model provider, Git command, or CI system transmits them.

The only repository-managed network-dependent operations are explicit dependency retrieval through npm and GitHub-hosted workflow execution. Model and IDE data flows are controlled by the selected provider and organization, not by this repository.

## Recommended Enterprise Baseline

- Start with preview-only installation and review every planned path.
- Use curated memory or disable memory for repositories with restricted data.
- Keep raw episodic logs, credentials, customer data, incident material, and regulated records out of agent memory.
- Keep L1 loops report-only. Enable L2 only for a named item, in an isolated worktree, with a separate verifier and human merge review.
- Require explicit approval for pushes, dependency changes, CI edits, releases, deployments, migrations, external tools, and MCP servers.
- Apply least privilege to repository roles, GitHub Apps, workflow tokens, models, and IDE extensions.
- Use branch protection, required reviews, signed or verified release processes, secret scanning, and organization audit logs where available.
- Treat generated code and analysis as untrusted until reviewed and tested.

## GitHub Copilot

The `github-copilot` adapter installs repository custom instructions at `.github/copilot-instructions.md`. If that file already exists, installation creates `.github/copilot-instructions.lizard-agent-layer.md` and records a manual merge instead of replacing organization-owned instructions.

Before enabling Copilot, an organization should review model availability, agent mode, coding agents, CLI, MCP servers, public-code matching, content exclusion, and audit policies. Content exclusion is an additional provider control, not a substitute for repository permissions or secret handling. Verify policy coverage separately for every surface; IDE, GitHub.com, CLI, cloud agent, and third-party agents do not necessarily share identical controls.

## GitHub Actions

The repository workflow has read-only contents permission, disables persisted checkout credentials, installs exactly the committed lockfile, and pins third-party actions to full commit SHAs. The workflow runs repository code, so pull-request and branch policies must prevent untrusted changes from gaining access to sensitive runners or secrets.

For self-hosted runners, isolate workloads, use ephemeral runners where possible, restrict network access, and never attach production credentials to workflows that execute untrusted branches.

## Data Classification

| Data | Default Handling |
| --- | --- |
| Public source and documentation | Allowed after normal review |
| Internal source and architecture | Use only with organization-approved models and IDEs |
| Credentials and signing material | Never place in prompts, memory, reports, or commits |
| Customer, employee, health, finance, or regulated data | Exclude unless policy and legal review explicitly allow it |
| Security incidents and unreleased vulnerabilities | Use private channels and isolated evidence |
| Generated reports | Metadata-only by default; context-inclusive reports are sensitive |

## Deployment Decision Checklist

1. Confirm the MIT license and dependency licenses are acceptable.
2. Approve the AI providers, models, IDE surfaces, extensions, and data regions.
3. Configure Copilot and MCP policies at enterprise or organization level.
4. Define prohibited data and content exclusions.
5. Confirm branch, workflow, runner, secret, and repository permissions.
6. Select profile, packs, memory mode, harnesses, and automation level through `INSTALL.md`.
7. Review the generated installation plan before apply.
8. Run `doctor.ps1 -Strict` and project verification after installation.
9. Record the approving owner and revisit controls when providers or models change.

## Residual Risks

- Instructions cannot prevent a compromised model, IDE extension, runner, dependency, account, or operating system from violating policy.
- Prompt injection in repository content can influence an AI assistant; permissions and human review remain authoritative.
- Manually merged instructions cannot always be removed mechanically without reviewing the target file.
- Model output can be incorrect, insecure, biased, or incompatible even when the workflow completes successfully.
- Provider features and policy coverage change over time and require separate organizational review.
