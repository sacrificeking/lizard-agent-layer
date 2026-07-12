# AI-Guided Uninstall

Use this file with an AI assistant to remove a `lizard-agent-layer` installation from a target repository. This is a review-driven procedure, not blanket permission to delete `.agent`, `.agents`, `.github`, or any other directory.

Suggested user prompt:

> Read `UNINSTALL.md`, inspect the target installation and its manifests, and prepare a complete uninstall plan. Preserve user-owned content and stop before deleting anything until I explicitly approve the exact plan.

## Rules For The Assistant

- Begin with read-only inspection and Git status.
- Never delete by directory name alone. Use manifest ownership, hashes, sidecar identity, and repository evidence.
- Never remove a pre-existing user instruction file merely because it mentions `lizard-agent-layer`.
- Never follow symlinks, junctions, mounts, or reparse points while removing files.
- Do not use recursive deletion until every descendant is classified and the user approves the exact root.
- Preserve unrelated changes and stop if the worktree is already dirty in affected paths.
- Keep uninstall reports outside the target repository.
- Do not commit, push, release, or alter remote services.

## Step 1: Confirm Target And Desired Scope

Ask for the absolute target repository path and one of these outcomes:

- `managed-only`: remove unchanged layer-owned artifacts; preserve modified and user-owned content.
- `complete`: also remove local layer memory, update history, loop state, and modified layer-owned artifacts after explicit review.
- `export-then-complete`: export selected memory and loop state outside the target, verify the export, then perform complete removal.

`complete` never means deleting unrelated project files or organization-owned instructions.

## Step 2: Establish A Recovery Point

Inspect:

```powershell
git -C <absolute-target-path> status --short
git -C <absolute-target-path> rev-parse --show-toplevel
```

Recommend a clean commit, local backup, or approved worktree before deletion. Do not create a commit without permission. If affected paths contain unrelated uncommitted work, stop and ask how to preserve it.

## Step 3: Inventory Installation Evidence

Read when present:

- `.agent/lizard-agent-layer.install.json`
- `.agent/lizard-agent-layer.update-history.jsonl`
- `.agent/loops/lizard-agent-layer.loop-install.json`
- every artifact listed in the install manifest
- harness sidecars and mirror destinations recorded by adapters

Validate the manifest shape before trusting paths. Reject absolute paths, upward traversal, target-root equality, and linked ancestors. Record each artifact as:

- unchanged layer-owned;
- modified layer-owned;
- adopted;
- user-owned;
- missing;
- integrity unknown.

If no valid manifest exists, perform a conservative discovery pass and label every candidate unverified. Do not delete unverified content without file-by-file approval.

## Step 4: Find Manual Integration Residue

Inspect likely instruction files without copying their complete content into reports:

- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `.cursor/rules/*.mdc`
- `.github/copilot-instructions.md`

Identify exact lizard pointer blocks or references. Compare against generated sidecars where possible. Propose minimal line-level removals separately from generated-file deletion. If a manual merge cannot be distinguished safely from user-authored policy, preserve it and report the residue.

## Step 5: Optional Export

For `export-then-complete`, ask which of these to retain:

- curated preferences, decisions, lessons, and workspace handoff;
- loop state, events, budgets, and verifier evidence;
- install and update manifests for audit.

Export only to the approved path outside the target. Hash the exported files and verify they can be read before proposing source deletion. Never export secrets or raw customer data.

## Step 6: Present The Exact Removal Plan

Present a table with one row per path:

| Path | Evidence | Current State | Proposed Action | Recovery |
| --- | --- | --- | --- | --- |

Separate:

1. generated files safe to remove;
2. modified files requiring explicit purge approval;
3. manual instruction edits;
4. directories removable only after they become empty;
5. preserved user-owned or ambiguous content;
6. expected residue, if any.

Do not present `.agent/`, `.agents/`, `.claude/`, `.gemini/`, `.cursor/`, or `.github/` as a single deletion root unless every descendant is proven layer-owned and approved.

## Step 7: Approval Gate

Ask the user to approve the exact path table and any manual line edits. For `complete`, obtain a second explicit confirmation for memory, loop state, update history, and modified layer-owned artifacts.

Execute only the approved entries. Remove files before directories and remove directories only when empty. Re-check path containment immediately before each deletion.

## Step 8: Verify Complete Removal

After deletion:

1. Re-run Git status.
2. Confirm every approved manifest artifact is absent.
3. Confirm installation, update, and loop manifests are absent.
4. Search target-local instructions and configuration for `lizard-agent-layer` references.
5. Confirm harness sidecars and layer-created skill mirrors are absent.
6. Confirm preserved user-owned files still exist and retain their hashes.
7. Confirm no empty layer-created directories remain.
8. Confirm no transaction lock or transaction store remains.

Report removed paths, preserved paths, manual references removed, unresolved residue, export location and hashes, and final Git status. Claim complete removal only when every check passes and unresolved residue is empty.

## Recovery

If a deletion fails or the observed filesystem differs from the approved plan, stop immediately. Restore from the clean commit, backup, or approved worktree. Do not continue with broader deletion patterns and do not remove transaction evidence needed for recovery.
