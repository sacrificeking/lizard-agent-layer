---
name: release
description: Controlled release workflow with verification, changelog, versioning, tagging, and final push gate. Use when preparing releases, version bumps, changelogs, publish steps, tags, or ship/go-live workflows.
---

# Release Workflow

## Core Release Invariant

A release candidate MUST NOT be tagged or published unless all required release checks for the exact candidate commit SHA have completed successfully. Unverified or pending commits are strictly blocked from release promotion.

## Standard Release Procedure

1. **Inspect Working Tree**: Verify working tree is clean with no unintended changes or dirty state.
2. **Determine Semantic Version**: Determine exact version bump (`patch`, `minor`, `major`) adhering to SemVer 2.0.0.
3. **Run Pre-Release Verification**:
   - Run unit and adversarial test suites (`tests/adversarial/...`, `tests/unit/...`, `tests/integration/...`).
   - Run end-to-end smoke verification (`tests/smoke.ps1`).
   - Run repository drift checks (`scripts/check-repository-drift.ps1`).
   - Run release readiness validation (`scripts/release-readiness.ps1`).
4. **Update Version and Schemas**: Update `VERSION`, `package.json`, and ensure schemas and manifests match.
5. **Update Release Notes / Changelog**: Format user-facing release notes cleanly, neutrally, and without internal tracker codes.
6. **Commit & Push Release Candidate**: Push the candidate commit to origin.
7. **Verify CI Status**: Verify all CI jobs for the exact commit SHA pass (Windows PowerShell 5.1, PowerShell 7 on Windows, Linux, and macOS).
8. **Obtain Explicit Approval**: Stop before tagging or publishing until the user explicitly approves.
9. **Tag & Publish**: Create annotated tag and publish GitHub release with exact SHA provenance and checksums.

## High-Risk Additions

- Verify signed approval contracts and replay ledger protection.
- Verify safe rollback non-clobber invariants.
- Verify schema validator bindings across all registered document schemas.
