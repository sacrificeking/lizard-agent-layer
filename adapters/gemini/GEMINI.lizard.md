# Lizard Agent Layer for Gemini

This project uses lizard-agent-layer for portable memory, skills, protocols, and handoff state across models.

## Startup Order

1. Read `.agent/project-profile.json`.
2. Read `.agent/memory/personal/PREFERENCES.md` when present.
3. Read `.agent/memory/semantic/DECISIONS.md` and `.agent/memory/semantic/LESSONS.md` for relevant prior context.
4. Read `.agent/protocols/permissions.md` before destructive, remote, dependency, release, CI, or database actions.
5. Read `.agent/protocols/handoff.md` when continuing another agent's work.
6. Read `.agent/routing/policy.json` and `.agent/protocols/staged-execution.md` before non-trivial or delegated work; keep the active model unless automatic inventory routing is explicitly configured.
7. Load matching skills from `.agent/skills/` or `.gemini/skills/` only when useful.

## Working Rules

- Prefer verified repository context over assumptions.
- Separate facts, inferences, and recommendations.
- Update working memory before handing work to another model.
- Do not store secrets in memory.
- Ask before push, deploy, migration, dependency, or CI changes.
- Route by logical capability roles rather than provider names and use a fresh verification context.
- Treat routing as advisory unless target-local Gemini configuration provides automatic calibrated selection; never request a manual mid-task switch.
- Apply staged execution internally from the user's normal task prompt; do not require routing commands or role selection.
