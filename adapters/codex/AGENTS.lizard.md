# Lizard Agent Layer

This project uses lizard-agent-layer for portable agent instructions, skills, and curated memory.

## Startup order

1. Read `.agent/project-profile.json`.
2. Read `.agent/memory/personal/PREFERENCES.md` when present.
3. Read `.agent/memory/semantic/DECISIONS.md` and `.agent/memory/semantic/LESSONS.md` for relevant prior decisions.
4. Read `.agent/protocols/permissions.md` before destructive, remote, release, dependency, or database actions.
5. Load Codex skills from `.agents/skills/` only when their triggers match the task.

## Memory discipline

- Keep raw logs private unless the project profile explicitly allows them.
- Add only curated, stable lessons to semantic memory.
- Never store secrets in memory.

## Safety

- Do not push to remote without explicit user approval.
- Do not overwrite project instructions without explicit approval.
- For high-risk profiles, run the profile verification checks before finalizing implementation work.
