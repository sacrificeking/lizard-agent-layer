---
name: premortem
description: Use before executing medium/high-risk implementation, database, security, or release plans to identify concrete failure modes and repo-bound mitigations.
---

# Plan Premortem with Repo-Bound Mitigations

## When to Use
- Trigger before executing medium- or high-risk plans (e.g. database schema changes, authentication/security updates, CI changes, dependency changes, or large refactorings).
- Skip for trivial typo fixes, localized bug fixes, or read-only questions.

## Success Criteria
1. **Failure Frame:** Adopt the perspective: *"This plan has already failed in production in this repository."*
2. **Concrete Failure Modes:** List genuine failure modes in past-tense statements without sugarcoating.
3. **Repository Grounding & Ratings:** Every identified failure mode must bind to a concrete repository path (e.g. `src/auth.ts`, `migrations/`, `pom.xml`) or an explicit `gap:` identifier, and include explicit ratings: `likelihood: L|M|H` and `impact: L|M|H`.
4. **Non-Triviality:** A high-risk plan with zero identified failure modes fails the premortem contract.

## Boundaries
- Premortem is risk judgment; it does not replace verifier evidence or waive `permissions.md`.
- Never encode unredacted secrets, credentials, or customer PII into failure mode descriptions.

## Verification & Evidence
- Verify that every cited repository path exists in the current workspace.
- Verify that proposed pre-execution checks correspond to actual build, test, or doctor commands.

## Output
Produce a synthesis-first summary derived directly from the L/M/H labeled failure modes:
- **Most Likely Failure Mode:** The failure mode with the highest operational probability (highest likelihood `H`).
- **Most Dangerous Failure Mode:** The failure mode that would cause the highest blast radius or data loss (highest impact `H`).
- **Hidden Assumption:** An unstated premise that this plan relies on.
- **Plan Modification:** One concrete adjustment made to the plan before execution.
- **Pre-Execution Verification Gates:** 3 to 5 real checks to run before declaring readiness (e.g. dry-run plan inspection, strict doctor check, targeted unit test suite).

## Stop Conditions
- Stop plan execution immediately if a high-likelihood (`likelihood: H`), high-damage (`impact: H`) failure mode is found with neither an existing automated control nor an accepted mitigation step.
