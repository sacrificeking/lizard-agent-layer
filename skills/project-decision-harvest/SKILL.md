---
name: project-decision-harvest
description: Use when discovering repository conventions, when DECISIONS.md contains the placeholder marker, or before initial non-trivial implementation.
---

# Project Decision Harvest

## When to Use
- Trigger when DECISIONS.md contains the `Status: placeholder` marker.
- Trigger when the user explicitly asks to harvest or document project conventions, architecture decisions, or operator corrections.
- On a non-trivial implementation task, if the placeholder marker is present: harvest conventions and stop (do not implement in the same turn).

## Success Criteria
- Inspect repository configuration, build files, module structure, and existing conventions (e.g. `package.json`, `pom.xml`, `*.csproj`, README files, logging setup).
- When harvesting operator corrections, classify each learning into the appropriate storage bucket before proposing changes.
- Propose 3 to 5 concrete items grounded in this repository.
- Every proposed item must cite a concrete path in this repository or be explicitly marked `unverified`.

## Classification Buckets
Classify each harvested item into exactly one bucket:
1. `decision` (`.agent/memory/semantic/DECISIONS.md`): Architectural choices, tech stack selections, framework conventions, or domain terminology.
2. `lesson` (`.agent/memory/semantic/LESSONS.md`): Recurring repository quirks, build/test workarounds, or documented failed approaches.
3. `preference` (`.agent/memory/personal/PREFERENCES.md`): Operator personal styles, commit message formats, explanation depth, or editor preferences.
4. `local-skill` (`.agent/skills-local/<name>/SKILL.md`): Multi-step repeatable coding procedures specific to this codebase (propose stub with When / Stop only).
5. `permissions-gate`: High-risk or prohibited actions. Cite existing line in `.agent/protocols/permissions.md`; do not draft new permissions or memory writes.
6. `nowhere`: One-off typo fixes, unverified guesses, secret/credential-adjacent data, or stale state. Propose no persistent writes.

## Boundaries
- Do not invent generic "clean architecture" or framework slogans.
- Never write or update memory files or local skills without explicit human review and line-by-line confirmation.
- Never include credentials, customer data, or production dumps in harvested items.
- Never duplicate standing protocols from `permissions.md` into semantic memory.

## Verification & Evidence
- Verify that every cited repository path exists in the current workspace.
- Verify that conventions accurately reflect the current codebase.

## Output
- Present a proposal list with:
  1. `id`: Short identifier (e.g. `build-tool`, `test-runner`, `logging-policy`).
  2. `bucket`: `decision` | `lesson` | `preference` | `local-skill` | `permissions-gate` | `nowhere`.
  3. `destination`: Target file path or `none`.
  4. `statement`: Concise one-sentence summary of the accepted practice or lesson.
  5. `path`: Concrete repository file path proving this pattern (or `unverified`).
  6. `rationale`: Why this belongs in the assigned bucket.
- Ask the operator to confirm, edit, or reject each proposed item before saving.

## Stop Conditions
- Stop immediately after presenting the proposal list. Do not write any files or proceed to code implementation until the operator approves the items.
