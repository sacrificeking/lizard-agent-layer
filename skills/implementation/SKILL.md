---
name: implementation
description: Default implementation skill for non-trivial code changes, feature work, bug fixes, refactoring, and migrations. Composes staged planning, sibling pattern grounding, risk-tiered premortem, and verification.
---

# Implementation

## When to Use
- Trigger for non-trivial feature implementation, bug fixes, refactoring, or migrations.
- Skip for trivial comment fixes, typo corrections, or read-only questions (use minimal edits without ceremony).

## Success Criteria
1. **Pre-check:** If DECISIONS.md contains `Status: placeholder`, run `project-decision-harvest` before implementing.
2. **Strategy & Grounding:** Follow the 10-80-10 workflow (`staged-execution`). Ground code changes in 1 to 3 existing sibling patterns in this repository. Prefer: existing helper -> stdlib -> platform feature -> installed dependency -> minimal new code. Never add unrequested scaffolding. If greenfield, confirm pattern with user.
3. **Risk-Tiered Premortem:** For medium/high-risk changes (migrations, auth, security, dependencies, breaking contracts, irreversible operations), produce a concise pre-edit table of failure modes rated by `likelihood: L|M|H` and `impact: L|M|H` with mitigations. Stop if any high-likelihood/high-damage (`H/H`) failure mode lacks automated controls. Skip premortem for low-risk changes.
4. **Bounded Execution:** Implement incrementally matching repo conventions; do not perform drive-by renames or unsolicited framework additions.

## Boundaries
- Follow `.agent/protocols/permissions.md` as the authoritative boundary for file, network, and dependency access.
- In `inherit-current` mode, complete all phases with the active harness model without requesting model switches.
- Never encode unredacted secrets, credentials, or customer PII into diffs, receipts, or memory.

## Verification & Evidence
- Run named repository test, typecheck, lint, or build commands matching the diff (never invent toolchains).
- Report visible output and verify actual behavior changes rather than command success alone.
- Scale verification to the diff; do not add or re-run tests after PASS.
- **Stop on repeated FAIL:** If the same named verification command fails twice with an unchanged approach, STOP and report the command and visible output. Do not invent extra tests, expand scope, or work around the failure. After two identical FAILs, a different strategy is allowed once; a third FAIL on the new strategy still stops.

## Output
Produce a structured **Review Packet** on completion:
- **Pattern Cited:** Concrete path to sibling file or `none-user-approved`.
- **Files Changed:** Concise list of modified files with one-sentence rationale each.
- **Verification Summary:** Commands executed, visible results, and skipped checks.
- **Three Diff-Specific Review Questions:** Three concrete questions about this specific diff for a human reviewer.
- **Findings:** Discrete defects introduced in this diff that the author would fix if known (actionable, path-cited). None if clean.
- **Human Callouts:** Informational flags for human reviewers (migrations, dependencies/lockfiles, auth/permissions, breaking contracts, destructive actions). Does not trigger automated fix loops.
- **Verdict:** `looks-good` | `needs-attention`.

## Stop Conditions
- Stop if a new dependency is required without user confirmation or no sibling pattern exists for greenfield work.
- Stop if high-likelihood (`H`), high-damage (`H`) failure modes lack automated controls during premortem.
- Stop after two identical verification FAILs (or three with an alternative strategy).
- Stop when task acceptance criteria are verified or permission boundaries in `permissions.md` are encountered.
