# Architecture

`lizard-agent-layer` separates reusable agent infrastructure from project-local knowledge.

## Layers

1. Core layer
   - installers, upgrade logic, validation, manifest generation
2. Profile layer
   - project size, stack, risk level, memory mode, selected skills
3. Adapter layer
   - Codex, Claude Code, Cursor, Gemini, or generic AGENTS.md wiring
4. Project layer
   - target-local memory, decisions, lessons, and permissions

## Target project output

A target project may receive:

```text
.agent/
  project-profile.json
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
  skills/
    _index.md
    _manifest.jsonl
    <skill>/SKILL.md

.agents/
  skills/
    <skill>/SKILL.md

AGENTS.md or AGENTS.lizard-agent-layer.md
```

## Memory stance

Use curated memory by default:

- Commit stable preferences, decisions, and accepted lessons.
- Keep raw episodic logs private and gitignored unless explicitly enabled.
- Do not store secrets, credentials, raw customer data, or private research dumps.

## Upgrade stance

The layer owns only files it generated. Upgrades should:

- preview changes first
- preserve project-local edits
- avoid replacing target instructions without explicit force
- produce a clear summary of created, skipped, and merge-needed files
