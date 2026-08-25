---
name: repo-grounded-change
description: Use for non-trivial implementation, diff review, or refactoring to ensure changes follow existing sibling patterns and produce a 3-question review packet.
---

# Repo-Grounded Change & Review Packet

## When to Use
- Trigger for non-trivial feature implementation, bug fixes, refactoring, or migrations.
- Skip for trivial comment fixes, typo corrections, or read-only questions.

## Success Criteria
1. **Pre-check:** If DECISIONS.md contains `Status: placeholder`, stop and run `project-decision-harvest` before implementing.
2. **Sibling Pattern Grounding:** Identify 1 to 3 sibling files in the same language and module. Quote their paths as the structural pattern. If greenfield (no siblings exist), ask the user before introducing new directory or module patterns.
3. **Repository Verification Check:** Name concrete verification commands defined in this repo (from `package.json`, `pom.xml`, `Makefile`, etc.). Never invent toolchains.
4. **Minimal Diff:** Keep changes focused on the requested goal matching existing conventions.

## Boundaries
- Do not perform drive-by renames, unsolicited refactoring, or framework additions.
- Follow `.agent/protocols/permissions.md` for dependency additions or destructive operations.
- Never persist or commit unredacted secrets or customer data.

## Verification & Evidence
- Run named project test or lint checks and report visible command output.
- Record any skipped checks and explain why.

## Output
Produce a structured **Review Packet** on completion:
- **Pattern Cited:** Concrete path to sibling file or `none-user-approved`.
- **Files Changed:** Concise list of modified files with one-sentence rationale each.
- **Verification Summary:** Commands executed, results, and skipped checks.
- **Three Diff-Specific Review Questions:** Three concrete questions about **this specific diff** that a human reviewer must be able to answer by reading the changed lines (e.g. edge-case behavior, boundary conditions, or skip reasons). Do not repeat static generic category labels as the questions themselves.

## Stop Conditions
- Stop if a new dependency is required without user confirmation.
- Stop if no sibling pattern exists and greenfield approval is needed.
- Stop when permission boundaries in `permissions.md` are encountered.
