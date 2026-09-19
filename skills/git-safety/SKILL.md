---
name: git-safety
description: Safe git mutation workflow for staging, commits, branches, merges, rebases, tags, pushes, and remote repository changes. Use when mutating git state or history.
---

# Git Safety

## Rules

- Inspect `git status` before staging or committing.
- Stage specific files, not broad unrelated changes.
- Do not push without explicit user approval.
- Do not force push protected branches.
- Do not rewrite history unless the user clearly asks for it.
- Preserve unrelated local changes.

## Verification

- Summarize staged files before commit.
- Summarize commit hash and message after commit.
- Before push, restate the remote and branch.
