# Release Gates

## Mandatory Release Integrity Policy

A release candidate MUST NOT be tagged, published, or promoted unless all required release checks for the exact candidate commit SHA have completed successfully. Queued, pending, skipped, cancelled, timed-out, missing, or failed required checks are release blockers.

## Standard Release Procedure

Before release-worthy changes:

1. Inspect git status and working tree hygiene.
2. Separate unrelated work.
3. Run complete verification suites across all supported host environments (Windows PowerShell 5.1, PowerShell 7 on Windows, Linux, and macOS).
4. Run repository drift checks (`scripts/check-repository-drift.ps1`) and release readiness (`scripts/release-readiness.ps1`).
5. Review changelog and draft user-facing release notes (clean, neutral, and without internal tracker codes).
6. Confirm version bump strategy across `VERSION`, `package.json`, and schemas.
7. Ask for explicit approval before pushing commits or tags.

For a contract-sensitive release, also run:

```powershell
pwsh -NoProfile -File .\scripts\contract-check.ps1 -BaseRef <release-base> -Strict
```

Confirm every impacted contract links an accepted ADR, migration disposition, compatibility note, changelog entry, and executable regression fixture. Follow `docs/troubleshooting.md` for unresolved locks, journals, manifests, worktrees, or verifier evidence.

Loop-runtime changes must pass duplicate-run, budget, attempt, rollback, stale-lease recovery, event-tamper, and L2 verifier-rejection fixtures. Generated runtime state, lease, events, and reports must satisfy their executable schemas.

High-risk projects should also verify migrations, external API boundaries, and UI contract compliance.
