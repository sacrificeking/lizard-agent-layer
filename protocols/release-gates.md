# Release Gates

Before release-worthy changes:

1. Inspect git status.
2. Separate unrelated work.
3. Run the profile verification commands.
4. Review changelog or draft release notes.
5. Confirm version bump strategy.
6. Ask for explicit approval before pushing commits or tags.

For a contract-sensitive release, also run:

```powershell
pwsh -NoProfile -File .\scripts\contract-check.ps1 -BaseRef <release-base> -Strict
```

Confirm every impacted contract links an accepted ADR, migration disposition, compatibility note, changelog entry, and executable regression fixture. Follow `docs/troubleshooting.md` for unresolved locks, journals, manifests, worktrees, or verifier evidence.

Loop-runtime changes must pass duplicate-run, budget, attempt, rollback, stale-lease recovery, event-tamper, and L2 verifier-rejection fixtures. Generated runtime state, lease, events, and reports must satisfy their executable schemas.

High-risk projects should also verify migrations, external API boundaries, and UI contract compliance.
