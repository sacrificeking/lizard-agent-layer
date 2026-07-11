# L2 Lifecycle And Verifier Evidence

L2 assisted work uses one hashed lifecycle contract from creation through verification and cleanup. Auto-merge remains forbidden.

## Create

`loop-worktree.ps1 -Apply -HumanApproved` writes `loop-worktree-lifecycle.json` beside its report. The envelope binds an operation ID to the target root, Git common directory, sibling worktree root, branch, base SHA, observed HEAD, and no-auto-merge policy.

Target-equal and target-contained worktree paths are rejected before Git runs. If post-create identity validation fails, the newly created worktree and branch are removed immediately.

## Verify

Pass the lifecycle file to `loop-verify.ps1`. A verdict other than `NEEDS_REVIEW` also requires:

- distinct `-Implementer` and `-Verifier` identities;
- at least one `-VerificationCommand`;
- zero command exits for `PASS` or `WARN`;
- optional worktree-relative `-EvidenceFile` values for explicit file hashes.

The evidence envelope records lifecycle hash, reviewed HEAD, dirty state, tracked diff hash, untracked file hashes, final Git-state hash, command exit codes, command-output hashes, evidence-file hashes, and reviewer identity. Raw command output is not copied into the packet.

Example:

```powershell
pwsh -NoProfile -File .\scripts\loop-verify.ps1 `
  -TargetPath <project> `
  -LifecyclePath <reports>\loop-worktree-lifecycle.json `
  -Implementer implementation-agent `
  -Verifier independent-reviewer `
  -Status PASS `
  -VerificationCommand "npm test" `
  -EvidenceFile "test-results.json" `
  -Apply
```

`loop-audit.ps1` validates the evidence envelope hash and recomputes current worktree state while the worktree exists. A changed worktree invalidates the prior verdict.

## Cleanup

New worktrees require the same `-LifecyclePath` for cleanup apply. The cleanup command rechecks target, common directory, worktree root, and branch before removal. `-AllowLegacyUnbound` exists only for intentionally reviewed worktrees created before lifecycle contracts were introduced.
