# Architecture

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
    memory-policy.md
    release-gates.md
    secret-handling.md
    handoff.md
  skills/
    _index.md
    _manifest.jsonl
    <skill>/SKILL.md

AGENTS.md or AGENTS.lizard-agent-layer.md       # Codex/generic
CLAUDE.md or CLAUDE.lizard-agent-layer.md       # Claude Code
GEMINI.md or GEMINI.lizard-agent-layer.md       # Gemini
.cursor/rules/lizard-agent-layer.mdc            # Cursor

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

## Durable contracts

Architecture decisions live under [`docs/adr/`](adr/README.md). Machine-readable contract ownership lives in `registry/contracts.json`; contract-sensitive changes require a matching declaration under `changes/`. See [Compatibility](compatibility.md), [Deprecation policy](deprecation-policy.md), and [Troubleshooting](troubleshooting.md).
