# Architecture

> [!NOTE]
> **⚡ Ultra High-Dense Quick Check:**
> - **Separation of Concerns:** Reusable governance logic is decoupled from project-local memory (`.agent/memory/`) and IDE harness translation (`adapters/`).
> - **Universal Default:** Provider-neutral staged execution keeps the active harness model by default.
> - **Visual Map:** See [Visual Architecture Blueprint](visual-architecture.md) for full ASCII topology and flowcharts.

`lizard-agent-layer` separates reusable agent infrastructure from project-local knowledge and harness-specific wiring.

## Layers

1. Core layer
   - installers, upgrade logic, validation, manifest generation
2. Profile layer
   - project size, stack, risk level, memory mode, selected skills, harnesses, model roles
3. Adapter layer
   - Codex, Claude Code, Gemini, Cursor, or generic AGENTS.md wiring
4. Legacy model profile compatibility layer
   - deprecated concrete role mappings retained only for existing custom profiles
5. Staged execution layer
   - provider-neutral strategy, execution, verification, escalation, and receipt contracts; active-model default
6. Project layer
   - target-local memory, decisions, lessons, handoff state, and permissions

## Principle

Skills, memory, protocols, and handoff state are generic. Adapters only translate that generic layer into files a harness knows how to read.

## Target project output

A target project may receive:

```text
.agent/
  project-profile.json
  routing/
    policy.json
    receipts/                    # private runtime metadata
    inventory.json               # optional, target-owned Advanced mode
    runtime.json                 # optional, automatic executor capability
    calibration/                 # optional, metadata-only promotion audit
  lizard-agent-layer.install.json
  .gitignore
  memory/
    personal/PREFERENCES.md
    semantic/DECISIONS.md
    semantic/LESSONS.md
    working/WORKSPACE.md
  protocols/
    permissions.md
    prompt-trust.md
    staged-execution.md
    context-hygiene.md
    secret-handling.md
    memory-policy.md
    project-context.md
    release-gates.md
    handoff.md
  skills/
    _index.md
    _manifest.jsonl
    <skill>/SKILL.md
    <skill>/skill.json

AGENTS.md or AGENTS.lizard-agent-layer.md       # Codex/generic
CLAUDE.md or CLAUDE.lizard-agent-layer.md       # Claude Code
GEMINI.md or GEMINI.lizard-agent-layer.md       # Gemini
.cursor/rules/lizard-agent-layer.mdc            # Cursor
.github/copilot-instructions.md                 # GitHub Copilot

.agents/skills/<skill>/SKILL.md                 # Codex mirror
.claude/skills/<skill>/SKILL.md                 # Claude mirror
.gemini/skills/<skill>/SKILL.md                 # Gemini mirror
.cursor/skills/<skill>/SKILL.md                 # Cursor mirror
```

## Memory stance

Use curated memory by default:

- Commit stable preferences, decisions, and accepted lessons.
- Keep raw episodic logs private and gitignored unless explicitly enabled.
- Do not store secrets, credentials, raw customer data, or private research dumps.

## Multi-model handoff

Every harness should read the same `.agent/` core. Before a task moves between models, the active agent updates `.agent/memory/working/WORKSPACE.md` using `.agent/protocols/handoff.md`.

Staged execution uses logical responsibilities rather than provider names. The portable default keeps the active harness model. Automatic model routing requires a target runtime capability, fingerprint-matched calibrated inventory, and separate execution attestation. See [Provider-Neutral Staged Execution](staged-execution.md).

## Upgrade stance

The layer owns only files it generated. Upgrades should:

- preview changes first
- preserve project-local edits
- avoid replacing target instructions without explicit force
- produce a clear summary of created, skipped, and merge-needed files

## What this layer does not claim

The installed overlay tells the **model** what to read and when to stop. The **installer** contains filesystem and plan mutations. The **IDE and organization** still own which bytes reach the provider and whether `doctor.ps1` actually ran.

These gaps are **intentional**. Closing them inside this repository would be a second product, a false control, or both.

| Not in this layer | Why it stays out |
| --- | --- |
| Forcing Copilot/Cursor to load only the 80-line always-on set | The host concatenates context. Calorie CI measures overlay files, not the provider prompt. Tenant content exclusion and instruction scope are organization controls. |
| A runtime cap that blocks a third skill file | Skills are Markdown. A quota needs a vendor skill loader (harness OS). Adapters state “at most two matching skills”; they cannot enforce it. |
| Running `doctor.ps1` from the chat session | The adapter **asks** for a current strict doctor + manifest-diff. The host does not execute that. Auto-doctor from the agent would be a new privileged runner and would weaken [ADR 0018](adr/0018-prompt-trust-and-constrained-verification.md). Champions run doctor after install/update. |
| L2 verifier executing `mvn test` / `npm test` | Target scripts are untrusted executable code ([ADR 0018](adr/0018-prompt-trust-and-constrained-verification.md)). Loop PASS is identity + plan + definition-of-done **packets**, not a substitute for the team’s test suite. |
| Deleting catalog slogan skills (`frontend-engineering`, …) | Defaults do not install them. `-Packs` is the honest opt-in. Removing the catalog forces every stack into `DECISIONS.md` or a fork. |
| An `expert` profile, DLP/PII engine, or Spec-Kit-style slash OS | Same overlay for novices and experienced users. Paste-stop is protocol judgment, not a scanner. SDD CLIs are adjacent products. |
| Replacing PowerShell with Node for install | Containment scripts are the platform. Target apps do not take that dependency. Champions need PowerShell 7.5+. |

Unix handle-bound SafeFs **runtime** evidence (H-03) is validated through the multi-host CI matrix across Windows, Ubuntu, and macOS. See [Compatibility](compatibility.md). Organization residual risk: [Enterprise usage](enterprise-usage.md).

## Durable contracts

Architecture decisions live under [`docs/adr/`](adr/README.md). Machine-readable contract ownership lives in `registry/contracts.json`; contract-sensitive changes require a matching declaration under `changes/`. See [Compatibility](compatibility.md), [Deprecation policy](deprecation-policy.md), and [Troubleshooting](troubleshooting.md).
