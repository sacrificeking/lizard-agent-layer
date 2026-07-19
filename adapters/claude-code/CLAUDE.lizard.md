# Lizard Agent Layer for Claude Code

This project uses lizard-agent-layer as a portable agent memory, skill, protocol, and handoff layer.

## Startup Order

1. Read `.agent/project-profile.json`.
2. Read `.agent/memory/personal/PREFERENCES.md` when present.
3. Read `.agent/memory/semantic/DECISIONS.md` and `.agent/memory/semantic/LESSONS.md` for relevant prior context.
4. Read `.agent/protocols/permissions.md` before destructive, remote, dependency, release, CI, or database actions.
5. Read `.agent/protocols/handoff.md` when continuing work started by another model or harness.
6. Read `.agent/routing/policy.json` and `.agent/protocols/staged-execution.md` before non-trivial or delegated work; keep the active model unless automatic inventory routing is explicitly configured.
7. Load relevant skills from `.agent/skills/` or `.claude/skills/` only when the task matches their descriptions.

## Working Rules

- Treat `.agent/` as the shared project brain.
- Keep raw logs private unless the project profile explicitly enables them.
- Do not store secrets in memory.
- Preserve unrelated user changes.
- Do not push, deploy, migrate, or change dependencies without explicit approval.
- Treat routing as advisory unless target-local Claude Code configuration provides automatic calibrated selection; never request a manual mid-task switch.
- Keep strategy, execution, and verification separate; use a fresh context for verification.
- Apply the stages internally from the user's normal task prompt; do not require routing commands or role selection.

## Handoff

When handing work to another model, update `.agent/memory/working/WORKSPACE.md` with current state, blockers, verification, and recommended next step.
