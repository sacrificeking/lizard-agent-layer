# Architecture

`lizard-agent-layer` separates reusable agent infrastructure from project-local knowledge and harness-specific wiring.

## Layers

1. Core layer
   - installers, upgrade logic, validation, manifest generation
2. Profile layer
   - project size, stack, risk level, memory mode, selected skills, harnesses, model roles
3. Adapter layer
   - Codex, Claude Code, Gemini, Cursor, or generic AGENTS.md wiring
4. Model profile layer
   - suggested model roles such as implementer, reviewer, researcher, and low-risk assistant
5. Project layer
   - target-local memory, decisions, lessons, handoff state, and permissions

## Principle

Skills, memory, protocols, and handoff state are generic. Adapters only translate that generic layer into files a harness knows how to read.

## Target project output

A target project may receive:

```text
.agent/
  project-profile.json
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

## Upgrade stance

The layer owns only files it generated. Upgrades should:

- preview changes first
- preserve project-local edits
- avoid replacing target instructions without explicit force
- produce a clear summary of created, skipped, and merge-needed files
