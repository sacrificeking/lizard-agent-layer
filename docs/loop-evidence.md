# L2 Lifecycle And Verifier Evidence

L2 assisted work uses one hashed lifecycle contract from creation through verification and cleanup. Auto-merge remains forbidden.

## Preview and register

`loop-worktree.ps1` previews the intended branch and sibling path. Built-in apply fails closed with `SAFEFS_EXTERNAL_MUTATOR_UNBOUND` because an external Git process cannot consume the SafeFs parent-handle boundary. After a human creates the reviewed worktree directly with Git, `loop-worktree.ps1 -RegisterExisting -Apply -HumanApproved` verifies that it is clean, at the approved base SHA and branch, and attached to the same Git common directory. It then writes `loop-worktree-lifecycle.json` beside its report without mutating the repository or worktree.

The envelope binds an operation ID to the target root, Git common directory, sibling worktree root, branch, base SHA, observed HEAD, `mutation_origin=external-registered`, and the no-auto-merge policy. Target-equal and target-contained worktree paths are rejected before registration.

## Verify

Pass the lifecycle file to `loop-verify.ps1`. A verdict other than `NEEDS_REVIEW` also requires:

- distinct `-Implementer` and `-Verifier` identities;
- an exact constrained verification plan outside the target/worktree, its independently reviewed SHA-256, and explicit approval;
- zero command exits for `PASS` or `WARN`;
- optional worktree-relative `-EvidenceFile` values for explicit file hashes.

The evidence envelope records lifecycle hash, reviewed HEAD, dirty state, tracked diff hash, untracked file hashes, final Git-state hash, command exit codes, command-output hashes, evidence-file hashes, and reviewer identity. Raw command output is not copied into the packet.

Example:

```powershell
pwsh -NoProfile -File .\scripts\new-verification-plan.ps1 `
  -WorktreePath D:\path\to\worktree `
  -CommandId git-head `
  -OutputPath D:\path\to\reports\verification-plan.json `
  -WritePlan

pwsh -NoProfile -File .\scripts\loop-verify.ps1 `
  -TargetPath <project> `
  -LifecyclePath <reports>\loop-worktree-lifecycle.json `
  -Implementer implementation-agent `
  -Verifier independent-reviewer `
  -Status PASS `
  -VerificationPlanPath D:\path\to\reports\verification-plan.json `
  -VerificationPlanSha256 <independently-reviewed-sha256> `
  -HumanApprovedVerificationPlan `
  -EvidenceFile "test-results.json" `
  -Apply
```

The built-in constrained runner deliberately supports only fixed non-network command IDs and never accepts executable/argv prose. Rich project tests must be run by a separately trusted operator or future external sandbox; their existence in a target profile or package script does not authorize execution.

## Authenticated evidence inputs

`CREATED` worktree lifecycle and verifier verdict evidence now use signed envelope schema version 2. The lifecycle signer must have the externally trusted `implementer` role; a verdict signer must have `verifier`, and the principals must differ. `loop-verify.ps1`, `loop-audit.ps1`, `loop-worktree-cleanup.ps1`, and L2 completion verify the exact-digest trust store and challenge, signature, payload/context hashes, role, validity, revocation state, and principal relationship before consuming the evidence.

Trust stores, challenges, private JWKs, and replay ledgers must remain outside both target and worktree roots. L2 completion additionally requires `-ReplayLedgerPath` and consumes the verifier envelope ID and nonce before changing loop state. A failed state mutation requires a new challenge; this is the deliberate fail-closed outcome of crossing two independent state domains.

The structural examples under `tests/schema/fixtures/` are not trusted keys or approvals. Organizations must issue challenges and publish trust/revocation state through a separately controlled process.

`loop-audit.ps1` validates the evidence envelope hash and recomputes current worktree state while the worktree exists. A changed worktree invalidates the prior verdict.

## Cleanup

Cleanup preview rechecks target, common directory, worktree root, branch, dirty state, and lifecycle identity. Built-in cleanup apply fails closed with `SAFEFS_EXTERNAL_MUTATOR_UNBOUND`; reviewed `git worktree remove` and branch deletion must be performed externally. `-AllowLegacyUnbound` affects legacy preview validation only and never enables built-in Git mutation.
