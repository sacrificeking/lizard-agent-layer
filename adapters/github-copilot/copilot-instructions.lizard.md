# Lizard Agent Layer for GitHub Copilot

This repository uses `lizard-agent-layer` for shared project context, safety protocols, curated memory, and reusable skills.

## Startup Order

1. Read `.agent/project-profile.json`.
2. Read relevant curated memory under `.agent/memory/`.
3. Read `.agent/protocols/permissions.md` before any write, remote, dependency, CI, release, deployment, or database action.
4. Read `.agent/protocols/secret-handling.md` before handling configuration or credentials.
5. Read `.agent/protocols/handoff.md` when continuing work from another model or IDE.
6. Load only the `.agent/skills/*/SKILL.md` files relevant to the current task.

## Working Rules

- Treat existing project instructions and user changes as authoritative.
- Start with repository evidence and distinguish facts, inferences, and recommendations.
- Never place secrets, credentials, customer data, or private source excerpts in memory or secondary reports.
- Do not push, deploy, migrate, publish, change dependencies, alter CI, or enable external tools without explicit approval.
- Run the project verification commands before claiming completion.
- Update `.agent/memory/working/WORKSPACE.md` before handing work to another model or IDE.
