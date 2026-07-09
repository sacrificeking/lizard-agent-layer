---
name: worktree-isolation
description: Use when an L2 assisted loop needs to create or verify an isolated git worktree before any approved write happens.
---
# worktree-isolation

Use this skill whenever a loop moves from L1 report-only into L2 assisted fix mode. The goal is to protect the user's main worktree and make every assisted change reviewable and disposable.

## When To Use

- A human approved a specific L2 assisted item.
- A loop needs a branch and worktree for a smallest-scope fix.
- The main worktree has unrelated changes that must be preserved.
- A verifier needs an isolated path to inspect before a merge decision.

## Rules

- Read `.agent/loops/worktree-policy.md` before proposing or creating a worktree.
- Do not modify the main worktree for an L2 assisted fix.
- Do not reuse an existing branch or worktree path unless a human explicitly approves reuse.
- Name branches narrowly, for example `lizard/l2/<item-id>`.
- Keep the worktree path outside the main source tree or inside a clearly gitignored scratch area.
- Record branch, worktree path, base revision, main status summary, rollback plan, and verifier requirement.

## Checks

- Verify the target is a git repository before creating a worktree.
- Check that the worktree path does not already exist.
- Check that the branch does not already exist.
- Audit main worktree status and report it before any assisted action.
- Validate that `human_approval_before_worktree_apply` is satisfied before `git worktree add`.

## Safety

- Auto-merge is forbidden.
- Do not push, tag, release, deploy, or delete worktrees from this skill.
- Preserve unrelated local work and never clean, reset, stash, or checkout user changes.
- Stop if approval, branch, path, verifier, or rollback information is missing.

## Output Format

```markdown
## Worktree Isolation Check

Status: PASS|HUMAN-GATE|STOP
Approved item: <id>
Branch: <branch>
Worktree path: <path>
Main worktree status: clean|dirty|unknown
Branch exists: yes|no
Path exists: yes|no
Human approval recorded: yes|no
Auto-merge: forbidden
Allowed next action: preview|create-worktree|pause|human-gate
Evidence: <commands or files checked>
```

## Example

If the branch already exists, output `STOP` and ask whether to reuse, rename, or discard the existing assisted worktree. Do not overwrite it.
