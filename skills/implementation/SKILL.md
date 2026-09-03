---
name: implementation
description: Use for non-trivial implementation, feature work, bug fixes, refactoring, or migrations, composing staged planning, repo-grounded changes, and premortem risk checks.
---

# Implementation

## When to Use
- Trigger for non-trivial feature implementation, bug fixes, refactoring, or migrations.
- Skip for trivial comment fixes, typo corrections, or read-only questions (use minimal edits).

## Success Criteria
1. **Pre-check:** If DECISIONS.md contains `Status: placeholder`, run `project-decision-harvest` before implementing.
2. **Strategy & Grounding:** Follow the 10-80-10 workflow (`staged-execution`). Ground implementation in 1 to 3 existing sibling patterns (`repo-grounded-change`). If greenfield, confirm pattern with user.
3. **Risk-Tiered Premortem:** For medium- or high-risk changes (migrations, security, auth, dependencies, large refactorings), follow the `premortem` output contract (sorting failure modes by `likelihood: L|M|H` and `impact: L|M|H`) before editing. Skip premortem for low-risk changes.
4. **Bounded Execution:** Implement incrementally matching repo conventions; do not perform drive-by renames or unsolicited framework additions.

## Boundaries
- Follow `.agent/protocols/permissions.md` as the authoritative boundary for file, network, and dependency access.
- In `inherit-current` mode, complete all phases with the active harness model without requesting model switches.
- Never encode unredacted secrets, credentials, or customer PII into diffs, receipts, or memory.

## Verification & Evidence
- Run named repository test, typecheck, lint, or build commands (never invent toolchains).
- Report visible output and verify actual behavior changes rather than command success alone.

## Output
Produce a structured **Review Packet** on completion:
- **Pattern Cited:** Concrete path to sibling file or `none-user-approved`.
- **Files Changed:** Concise list of modified files with one-sentence rationale each.
- **Verification Summary:** Commands executed, results, and skipped checks.
- **Three Diff-Specific Review Questions:** Three concrete questions about this specific diff that a human reviewer must be able to answer by reading the changed lines (edge-case behavior, boundary conditions, or skip reasons).

## Stop Conditions
- Stop if a new dependency is required without user confirmation or no sibling pattern exists for greenfield work.
- Stop if high-likelihood (`H`), high-damage (`H`) failure modes lack automated controls during premortem.
- Stop when task acceptance criteria are verified or permission boundaries in `permissions.md` are encountered.
