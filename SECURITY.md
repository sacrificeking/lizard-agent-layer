# Security Policy

## Supported Versions

Security fixes are maintained for the latest public major release. Pre-release development snapshots are not supported.

## Reporting A Vulnerability

Use GitHub private vulnerability reporting when it is enabled for this repository. Otherwise, contact the repository maintainers through an approved private organizational channel. Do not open a public issue containing exploit details, secrets, private repository content, or customer data.

Include the affected version, operating system, PowerShell edition, reproduction steps, impact, and any proposed mitigation. Remove credentials and confidential source code from the report.

## Response Expectations

Maintainers should acknowledge a complete report, reproduce it in an isolated fixture, classify impact, prepare a regression test, and coordinate disclosure before publishing technical details. No response-time or remediation-time service-level agreement is implied by this open-source project.

## Security Boundaries

`lizard-agent-layer` is local repository tooling. It does not provide an authorization system for GitHub, GitHub Copilot, IDE extensions, models, MCP servers, CI runners, or operating-system accounts. Organizations remain responsible for identity, access, data classification, model policy, content exclusion, network controls, branch protection, and audit logging.

The repository does not intentionally send telemetry or project content over the network. Network access occurs only when an operator explicitly invokes package installation, GitHub-hosted CI, Git operations against a remote, or an external AI/tool integration.
