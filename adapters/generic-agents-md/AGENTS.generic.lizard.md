# Lizard Agent Layer

This project uses lizard-agent-layer for shared agent memory, skills, safety protocols, and handoff state.

## Read First

1. `.agent/project-profile.json`
2. `.agent/memory/personal/PREFERENCES.md`
3. `.agent/memory/semantic/DECISIONS.md`
4. `.agent/memory/semantic/LESSONS.md`
5. `.agent/protocols/permissions.md`
6. `.agent/protocols/handoff.md`
7. Relevant `.agent/skills/*/SKILL.md` files

## Rules

- Do not push, deploy, migrate, install dependencies, change CI, or expose secrets without explicit approval.
- Keep project-local memory curated and secret-free.
- Update `.agent/memory/working/WORKSPACE.md` before handing off to another agent.
