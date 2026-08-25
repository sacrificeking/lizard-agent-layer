---
name: project-decision-harvest
description: Use when discovering repository conventions, when DECISIONS.md contains the placeholder marker, or before initial non-trivial implementation.
---

# Project Decision Harvest

## When to Use
- Trigger when DECISIONS.md contains the `Status: placeholder` marker.
- Trigger when the user explicitly asks to harvest or document project conventions and architecture decisions.
- On a non-trivial implementation task, if the placeholder marker is present: harvest conventions and stop (do not implement in the same turn).

## Success Criteria
- Inspect repository configuration, build files, and module structure (e.g. `package.json`, `pom.xml`, `*.csproj`, README files, logging setup).
- Propose 3 to 5 concrete architectural decisions grounded in this repository.
- Every proposed decision must cite a concrete path in this repository or be explicitly marked `unverified`.

## Boundaries
- Do not invent generic "clean architecture" or framework slogans.
- Never write or update DECISIONS.md without explicit human review and line-by-line confirmation.
- Never include credentials, customer data, or production dumps in harvested decisions.

## Verification & Evidence
- Verify that every cited repository path exists in the current workspace.
- Verify that conventions accurately reflect the current codebase.

## Output
- Present a proposal list with:
  1. `id`: Short identifier (e.g. `build-tool`, `test-runner`, `logging-policy`).
  2. `decision`: Concise one-sentence statement of the accepted practice.
  3. `path`: Concrete repository file path proving this pattern.
  4. `rationale`: Why this is an established repo decision.
- Ask the operator to confirm, edit, or reject each proposed decision before saving.

## Stop Conditions
- Stop immediately after presenting the proposal list. Do not proceed to code implementation until the operator approves the decisions.
