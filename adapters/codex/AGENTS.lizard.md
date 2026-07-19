# Lizard Agent Layer

This project uses lizard-agent-layer for portable agent instructions, skills, and curated memory.

## Startup order

1. Read `.agent/project-profile.json`.
2. Read `.agent/memory/personal/PREFERENCES.md` when present.
3. Read `.agent/memory/semantic/DECISIONS.md` and `.agent/memory/semantic/LESSONS.md` for relevant prior decisions.
4. Read `.agent/protocols/permissions.md` before destructive, remote, release, dependency, or database actions.
5. Read `.agent/routing/policy.json` and `.agent/protocols/staged-execution.md` before non-trivial or delegated work; keep the active model unless automatic inventory routing is explicitly configured.
6. Load Codex skills from `.agents/skills/` only when their triggers match the task.

## Staged execution

- Use strategy, execution, and a fresh verification pass as separate stages.
- Apply those stages internally from the user's normal task prompt; do not require routing commands or role selection.
- In `inherit-current` mode, use the active Codex model for every stage without requesting a picker change.
- Treat logical roles as responsibilities; concrete model IDs are target-local inventory data only in Advanced mode.
- Delegate only bounded independent tasks, honor the policy fan-out limit, and do not allow nested delegation when the policy sets it to zero.
- In `inventory-routing` mode, fail closed unless model selection is automatic and calibrated; never turn it into a manual mid-task switch.

## Memory discipline

- Keep raw logs private unless the project profile explicitly allows them.
- Add only curated, stable lessons to semantic memory.
- Never store secrets in memory.

## Safety

- Do not push to remote without explicit user approval.
- Do not overwrite project instructions without explicit approval.
- For high-risk profiles, run the profile verification checks before finalizing implementation work.
