# lizard-agent-layer worktree policy

This file defines the default worktree rules for L2 assisted loops.

## Default Posture

- L2 assisted loops may prepare a change only after explicit human approval.
- All writes happen in an isolated git worktree, not in the user's main worktree.
- Auto-merge is forbidden.
- Push, release, deploy, dependency, migration, secret, auth, finance-critical, and production changes require separate human approval.
- The verifier must be separate from the implementer role whenever the host supports role separation.

## Worktree Requirements

- Branch name must be explicit and scoped to one approved item.
- Worktree path must be outside the main source tree or inside an explicitly gitignored scratch area.
- Main worktree status must be reported before creating the assisted worktree.
- Existing branches or worktree paths must not be overwritten.
- Rollback is removing the assisted worktree and branch after human review; do not automate removal without approval.

## Completion Requirements

- `assisted-fix-plan.md` records scope, files, verification, rollback, and gates.
- `loop-verifier-report.md` records verifier, status, evidence, and residual risk.
- A human decides whether to merge, discard, or request another assisted attempt.
