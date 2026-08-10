# Remediation Ledger

This ledger tracks remediation of the findings in the [2026-08-01 Codex/VS Code static audit](../audits/codex-vscode-static-audit-2026-08-01.md).

## Locked baseline

- Baseline branch: `main`
- Baseline commit: `1797097d8a1c5ab5444ac82e83786ac1ccc841f6`
- Current remediation branch: `remediation/wp01b-mount-boundaries`
- Baseline production-code drift: none
- Initial worktree exception: the audit report was present as an untracked file
- Local verification host: Windows PowerShell 5.1 on Windows 10
- Network access and dependency installation: not authorized and not used

## Work-package state

| Work package | Findings | State | Dependencies | Exit condition |
| --- | --- | --- | --- | --- |
| Wave 0: baseline and ledgers | All | Implemented | None | HEAD, instructions, worktree and classifications are recorded |
| WP-01A: safe read/hash foundation | H-03 | Implemented and locally verified | Wave 0 | Contained reads succeed; linked terminal objects and ancestors fail with stable `SAFEFS_*` codes; loop evidence uses the shared primitives |
| WP-01B: mount/device boundaries | H-03 | Implemented; Ubuntu privileged and macOS runtime evidence passed; complete host matrix pending CI compatibility rerun | WP-01A, Unix fixtures | Unix mount and bind-mount escapes fail closed |
| WP-01C: handle-bound mutation | H-03 | Not started | WP-01A, host capability contract | Supported hosts use no-follow/handle-bound mutation; unsupported hosts fail closed or state the reduced guarantee |
| WP-02: transaction recovery | H-02, M-05 | Implemented and locally verified | WP-01A | Strict v2 runtime/schema validation, identity binding, contained canonical backups, retry-safe reverse replay, terminal cleanup, and decisive doctor classifications pass focused tests |
| WP-03: canonical plan binding | H-01 | Implemented and locally verified | Canonical serialization | Apply rejects every plan, source, target, option and approval mismatch before mutation |
| WP-04: continuous ownership | H-04 | Implemented and locally verified | WP-03 | Contract reduction retains retired ownership evidence |
| WP-05: transactional uninstall | H-04, M-04 | Not started | WP-01 through WP-04 | Bound preview/apply uninstall is reversible, resumable and idempotent |
| WP-06: memory modes | H-05 | Not started | WP-04, WP-05 | `off` creates and retains no memory artifacts or references |
| WP-07 through WP-10: governance, privacy, prompt trust and evidence trust | H-06 through H-09, M-07, M-08 | Not started | Trust-model ADR, WP-03, WP-08 foundations | Host and artifact trust claims have executable negative evidence and explicit external boundaries |
| WP-11 through WP-16: analyzer, portability, skills, diagnostics, CI and claim governance | M-01 through M-08, L-01 | Not started | Relevant P0 foundations | Each claim has supported-host evidence or an explicitly narrowed scope |

## WP-01A implementation record

Approved file boundary:

- `scripts/Lizard.SafeFs.psm1`
- `scripts/Lizard.LoopEvidence.psm1`
- `scripts/loop-verify.ps1`
- `tests/unit/safe-fs.tests.ps1`
- `tests/adversarial/loop-evidence.tests.ps1`
- `docs/safety-model.md`
- `docs/compatibility.md`
- `docs/remediation/remediation-ledger.md`
- `docs/remediation/claim-ledger.md`
- `changes/safe-read-hash-foundation.json` (separately approved contract-governance scope extension)

Implemented controls:

- Protected existing-file resolution under an explicit authorized root.
- Linked terminal-object and linked-ancestor rejection.
- Stable missing-file, wrong-type, reparse-point and changed-during-read error codes.
- Safe metadata, SHA-256 and content primitives.
- Pre/post read metadata comparison to detect observable changes during a read.
- Protected hashing for Git-reported untracked files.
- Protected verifier evidence metadata and hashing.

Residual limitations:

- The operations remain name-based and cannot eliminate every synchronized ancestor-swap race.
- WP-01A alone did not detect Unix mount and bind-mount boundaries; WP-01B now adds that enforcement while retaining the name-based race limitation.
- Pre/post length and timestamp comparison is a detection measure, not an authenticated file identity.
- Current evidence is local Windows PowerShell 5.1 evidence; Unix and PowerShell 7 evidence remain pending.

## Verification record

| Gate | Result |
| --- | --- |
| Failure-first safe-filesystem unit test | Failed as expected because `Get-SafeFileMetadata` did not exist |
| Safe-filesystem unit test after implementation | Passed |
| Adversarial linked-evidence and loop-evidence suite | Passed |
| Focused safety suites | Passed in the final consolidated CI run; all 14 constituent suites also passed during failure isolation |
| Schema validation and mutation suite | Passed: 52/52 bindings and 20/20 mutation cases |
| Contract governance | Passed with `changes/safe-read-hash-foundation.json`; ADR-0002 and ADR-0008 are linked with backward-compatible migration and additive compatibility dispositions |
| Final schema validation and mutation suite | Passed: 53/53 bindings and 20/20 mutation cases after adding the declaration |
| Full local CI | Passed in 1,225 seconds: validation, schema mutations, contract governance, focused safety, packs, drift, quality, smoke, and 18/18 profile/harness matrix combinations |

No commit, push, merge, publication or release is authorized by this ledger.

## WP-01B implementation record

Implemented controls:

- Safe filesystem resolution now compares fresh Unix mount identity for the authorized root and every destination component before access or mutation.
- Linux strictly parses `/proc/self/mountinfo`; a nested mount-ID transition on the same device fails with `SAFEFS_MOUNT_BOUNDARY`, while a device transition fails with `SAFEFS_DEVICE_BOUNDARY`.
- macOS combines mounted-root enumeration with `stat` device identity and applies the same nested-boundary policy.
- Missing, empty, malformed, or incomplete Unix mount identity fails closed with `SAFEFS_MOUNT_IDENTITY_UNAVAILABLE`; Windows retains its existing reparse-point path and performs no mount command.
- The authorized root may itself be a mountpoint, but a nested mount below it is rejected.
- A privileged, explicitly enabled Ubuntu fixture creates an isolated bind mount and `tmpfs`, proves that resolution and mutation reject both boundaries, verifies that the outside canary is untouched, and requires successful unmount cleanup.
- The existing Ubuntu matrix job runs the fixture immediately after checkout, before dependency setup or the longer CI gates, and first requires non-interactive `sudo`.
- ADR 0012 and `changes/unix-mount-boundaries.json` declare the current-namespace trust boundary and intentional Unix compatibility break.

## WP-01B verification record

| Gate | Result |
| --- | --- |
| Failure-first mount-boundary unit test | Failed as expected before implementation because `Lizard.MountBoundary.psm1` did not exist |
| Synthetic Linux/macOS mount policy | Passed locally on Windows PowerShell 5.1, including escaped mountinfo paths, longest boundary-aware matching, same-device bind rejection, cross-device rejection, mounted authorized roots, and unavailable/malformed identity failures |
| Existing SafeFs and installer containment regression suites | Passed locally |
| Privileged mount fixture on the local Windows host | Skipped as not applicable; no privilege or mount operation was attempted |
| Validation and schema mutations | Passed: 59/59 bindings and 24/24 mutation cases |
| Contract, drift, documentation, and public-readiness gates | Passed; 4 impacted contracts are declared, 118 drift artifacts have zero drift, ADR recovery passes, and public readiness passes |
| Focused safety suites | Passed: 20/20 suites in 2,619.2 seconds; report `.tmp/tests/focused-test-report.json`. An earlier attempt was interrupted during loop runtime and produced no current report, so both loop suites were rerun individually before the complete successful rerun |
| Pack and quality gates | Passed: 7 packs/21 unique skills with no failures or warnings; quality average 87.77 and minimum 68 |
| Standalone smoke | Passed in 1,493 seconds, including validation, approved apply, idempotence, upgrade, nested update, transaction, ownership conflict, sidecar preservation, and doctor; scratch `.tmp/smoke-20260809131718` |
| Standalone profile/harness matrix | Passed in 1,357.2 seconds: 18/18 combinations, 0 failures; report `.tmp/matrix-20260809134216/matrix-report.json` |
| Complete local CI constituent set | Passed all nine constituent gates on the same implementation state: validation, schema mutations, contract governance, focused safety, packs, strict drift, quality, smoke, and matrix |
| Actual Ubuntu bind-mount and `tmpfs` fixture | Passed in GitHub Actions run 31319333532 at commit `c7ff2020af82c673670ae8a01a657b726100432a`; non-interactive `sudo`, real bind mount, real `tmpfs`, rejection, canary, and cleanup checks succeeded |
| macOS runtime mount enumeration | Passed the SafeFs and mount-boundary policy suites on the live macOS runner in GitHub Actions run 31319333532 |

WP-01B is implemented but does not close H-03. GitHub Actions run 31319333532 established the narrow Ubuntu privileged-fixture and macOS runtime claims, then exposed a separate cross-runtime JSON type incompatibility in the PowerShell 7 jobs. The Windows PowerShell 5.1 job reached the former 35-minute ceiling during the final focused suite without a recorded test failure. A complete supported-host rerun remains pending, and the validation-to-mutation race remains WP-01C scope.

## CI compatibility wave 1

Remote baseline:

- Manual workflow run 31319333532 executed the exact pushed commit `c7ff2020af82c673670ae8a01a657b726100432a` on Windows PowerShell 5.1 and PowerShell 7 on Windows, Ubuntu, and macOS.
- All PowerShell 7 jobs reproduced the same root cause: `ConvertFrom-Json` converted schema-declared ISO-8601 strings to `System.DateTime`, causing canonical-plan, transaction-journal, and loop-evidence validation to fail.
- The PowerShell 5.1 job passed validation, mutations, governance, and every focused suite through loop runtime, then was cancelled by the workflow's 35-minute job ceiling during loop evidence; no test failure preceded cancellation.

Implemented correction:

- `Lizard.Json.psm1` centralizes security-sensitive JSON parsing and preserves timestamps as strings through `ConvertFrom-Json -DateKind String` on PowerShell 7.5+.
- Windows PowerShell 5.1 retains its native string behavior. PowerShell Core versions without the explicit date policy fail closed with `LIZARD_JSON_DATE_POLICY_UNSUPPORTED`.
- Canonical plans, transaction journals and locks, loop runtime JSON/JSONL, and loop evidence use the shared parser. Focused fixtures use the same contract when inspecting those artifacts.
- A failure-first JSON unit test locks top-level and nested timestamp strings byte-for-byte while retaining integer, Boolean, and null types.
- The workflow ceiling is 120 minutes for both job families so the complete suite reports its result.
- Contract governance declares the PowerShell Core 7.5+ operational migration and breaking fail-closed behavior. A complete remote rerun remains required before any supported-host closure claim.

Local verification on Windows PowerShell 5.1 passed the new JSON unit, canonical-plan unit and tamper suites, transaction suite, loop-runtime suite, loop-evidence suite, and 60/60 validation bindings.

| CI compatibility wave gate | Result |
| --- | --- |
| Failure-first JSON unit | Failed as expected before `Lizard.Json.psm1` existed; passed after implementation |
| Schema validation and mutations | Passed: 60/60 bindings and 24/24 mutation cases |
| Contract governance | Passed: 20 changed paths, 7 impacted contracts, and a breaking PowerShell Core 7.5+ migration declaration |
| Focused safety | Passed: 21/21 suites in 3,193.674 seconds; report `.tmp/tests/focused-test-report.json` |
| Packs, drift, and quality | Passed: 7 packs/21 unique skills with no failures or warnings; 118 reviewed artifacts with zero drift; quality average 87.77 and minimum 68 |
| Smoke | Passed in 2,319.7 seconds; scratch `.tmp/smoke-20260810065907` |
| Profile/harness matrix | Passed: 18/18 combinations in 1,597.2 seconds; report `.tmp/matrix-20260810073756/matrix-report.json` |
| Complete local CI constituent set | Passed all nine gates on the same implementation state. The original orchestrator process was interrupted after quality and before smoke; atomic reports prove the first seven gates, and only smoke plus matrix were resumed. No synthetic aggregate CI report is claimed. |

No commit, push, remote rerun, merge, publication, or release was performed for this wave. The next evidence gate is a GitHub Actions rerun on the exact committed and pushed remediation SHA.

## WP-02 implementation record

Implemented controls:

- Strict lock and journal v2 shape and semantic validation with bounded protected reads.
- Operation, target-root, owner, name, and timestamp binding across lock and journal.
- Chronological, contiguous mutation storage with canonical per-sequence backup names.
- Reverse-order recovery that persists every completed step, skips an already rolled-back suffix, and stops at the first failure.
- Dedicated cleanup for committed or fully rolled-back terminal journals.
- Doctor classifications for active, recovery-required, cleanup-required, invalid, missing, and orphan transaction evidence.
- Executable schema validation plus hostile unknown-field, JSON-type, identity-mismatch, traversal, sequence, missing/hash-mismatched backup, repeated-path interruption/retry, committed-cleanup, and explicit v1 fail-closed tests.

Compatibility and residuals:

- Journal v1 interrupted operations fail closed and require manual evidence-led recovery; clean targets require no migration.
- Target-local journals and unkeyed hashes are not authenticated against a writer who can alter the target; H-09 remains open.
- Name-based copy and restore retain the synchronized race limitations tracked by H-03/WP-01C.
- Transaction-related M-05 diagnostics are implemented, while report-residue lifecycle coverage remains pending.

WP-02 focused verification passed locally on Windows PowerShell 5.1. Full consolidated CI for this work package is recorded after its final gate run.

## WP-02 verification record

| Gate | Result |
| --- | --- |
| Failure-first journal-v2 assertion | Failed as expected before v2 writer support |
| Strict schema and repository validation | Passed: 54/54 schema bindings |
| Contract governance | Passed: transaction, schema-runtime, and ownership/manifest contracts linked to ADR-0006, ADR-0005, and ADR-0003 |
| Focused safety suites | Passed in the final consolidated run, covering hostile journal fields/types, identity mismatch, traversal, invalid sequence, missing/hash-mismatched backup, v1 fail-closed behavior, repeated-path interrupted retry, terminal cleanup, and doctor classifications |
| Pack report | Passed: 7 packs, 21 unique skills, no failures or warnings |
| Quality gate | Passed: average documentation score 87.77, minimum artifact score 68, no critical findings |
| Smoke gate | Passed; the sequential gate runner advanced to matrix |
| Profile/harness matrix | Passed: 18/18 combinations |
| Drift gate | Passed: baseline records 117 reviewed artifacts including `schemas/transaction-journal.schema.json`; zero added, changed, or removed artifacts |
| Full local CI | Passed all nine gates in 2,739.737 seconds; report `.tmp/ci/ci-report-20260801123114.json` |

The first complete CI command stopped at the intentional schema drift. The user subsequently approved the exact `registry/drift-baseline.json` scope extension. The final consolidated CI run passed every gate in 2,739.737 seconds: validation, 20/20 schema mutations, contract governance, all focused safety suites, packs, strict drift, quality, smoke, and the 18/18 profile/harness matrix. No commit, push, merge, publication, or release was performed.

## WP-03 implementation record

Implemented controls:

- Canonical schema-v1 JSON plans with ordinal key ordering, invariant encoding, strict UTF-8, expiry, immutable writes, and convenience digest sidecars.
- Independent apply authorization through `-ApprovedPlanPath`, `-ApprovedPlanSha256`, and `-HumanApproved`; sidecars are never trusted automatically.
- Binding of roots, effective options, the actual source Git HEAD, all executed layer inputs, target preconditions/actions/ownership/intended hashes, force/report behavior, and update's exact nested install plan.
- Validation before target lock acquisition and critical revalidation after lock acquisition but before the first mutation.
- Applied plan identity in install manifests and both outer/nested plan identities in update history.
- Intentional breaking migration declaration and ADR 0010; existing targets need no data rewrite, while legacy Markdown plans cannot authorize apply.

Local verification on Windows PowerShell 5.1 passes canonical-plan unit tests, 56/56 schema bindings, 22/22 schema mutations, contract governance, install tamper, positive install/update binding, containment, downgrade/version, manifest-v3, transaction, routing, public-readiness, full smoke, and the complete profile/harness matrix.

## WP-03 verification record

| Gate | Result |
| --- | --- |
| Failure-first approval-binding check | Failed as expected before implementation because an unbound apply was accepted |
| Canonical-plan unit and adversarial tests | Passed serialization, strict UTF-8/shape/expiry, immutable write, digest mismatch, Git-HEAD drift, action/ownership/intended-hash tamper, option drift, source-input drift, target drift, missing-approval cases, nested-plan drift, and relative-path canonicalization |
| Schema validation and mutations | Passed: 56/56 schema bindings and 22/22 mutation cases |
| Contract governance | Passed with `changes/exact-plan-approval-binding.json`, ADR 0010, and the declared breaking apply migration |
| Focused safety suites | Passed: 18/18 suites in 1,691.080 seconds during the final CI run; report `.tmp/tests/focused-test-report.json` |
| Pack, drift, and quality gates | Passed: 7 packs/21 skills with no warnings; 118 drift artifacts with zero drift; quality average 87.77 and minimum 68 |
| Standalone smoke | Passed in 1,274 seconds, including relative `-LayerRoot`, full preview/apply, idempotence, nested update, transaction, overlay, cursor, and sidecar-preservation flow under `.tmp/smoke-20260802072626` |
| Standalone profile/harness matrix | Passed in 1,151.4 seconds: 18/18 combinations, 0 failures; report `.tmp/matrix-20260802074751/matrix-report.json` |
| Full local CI | Passed all nine gates in 4,133.115 seconds; report `.tmp/ci/ci-report-20260802091602.json`; CI focused safety passed in 1,691.080 seconds, smoke in 1,279.529 seconds, and matrix in 1,154.871 seconds |

The full CI run repeated every constituent gate without skips: validation, schema mutations, contract governance, focused safety, packs, strict drift, quality, smoke, and the 18/18 profile/harness matrix. No network access, dependency installation, commit, push, merge, publication, or release was performed.

Residual limitations:

- Authenticated approver identity is not established by a local digest and remains H-09 scope.
- Logical target-root identity and name-based revalidation retain the physical containment limitations tracked by H-03.
- PowerShell 7 and Unix supported-host verification remain pending; H-01 therefore remains `OPEN_CHANGED`, not closed.
- Protected revalidation currently repeats broad source and target hashing; the controls fail closed but add material local gate latency, so bounded hash-cache/performance work remains an optimization item and must preserve post-lock freshness guarantees.

## WP-04 implementation record

Implemented controls:

- Manifest schema v4 gives every artifact an explicit `active`, `retired-present`, `retired-missing`, or future `removed` lifecycle.
- Contract reduction carries every deselected v3/v4 artifact record forward with its ownership, source identity, installed hash, adapter identity, aliases, and mirror group instead of discarding it.
- Retired paths are preserve-only canonical plan targets, and the exact sorted retired path/lifecycle set is bound into install options and nested update approval plans.
- Install and update never delete retired content. Present content is rehashed and classified; missing content retains the last installed identity; reselected artifacts return to active without overwriting local modifications.
- Schema-v4 readers fail closed on missing or invalid lifecycle fields, duplicate identities, path/lifecycle disagreement, wrong filesystem object kinds, and retired-content hash drift.
- Schema-v3 records migrate as active during the next exact-plan-approved apply. Schema-v4 manifests require lifecycle-aware readers, preventing older tools from interpreting retired records as active required artifacts.
- ADR 0011 and `changes/continuous-artifact-lifecycle.json` declare the migration and intentional reader compatibility break. `removed` remains reserved for WP-05 transactional uninstall.

Local Windows PowerShell 5.1 verification covers contract reduction, locally modified retirement, repeated contraction, physical disappearance, reactivation, missing/invalid lifecycle values, wrong-kind paths, reappeared removed paths, strict doctor/manifest-diff behavior, v2/v3 migration, canonical plan binding, and all supported profile/harness combinations.

## WP-04 verification record

| Gate | Result |
| --- | --- |
| Failure-first lifecycle assertion | Failed as expected before implementation because the writer emitted schema v3 and discarded deselected records |
| Lifecycle integration suite | Passed after final fail-closed hardening in 358.2 seconds, including `active → retired-present → retired-missing → active`, local modification preservation, plan exposure/binding, idempotence, missing lifecycle, wrong-kind, and reappeared-path negatives |
| Schema validation and mutations | Passed: 58/58 schema bindings and 24/24 mutation cases |
| Contract governance | Passed with `changes/continuous-artifact-lifecycle.json`, ADR 0011, and the declared v3→v4 migration/reader compatibility break |
| Focused safety suites | Passed: 19/19 suites on the final source state; report `.tmp/tests/focused-test-report.json`. The CI-reported duration includes a system suspend and is not a performance measurement |
| Pack, drift, and quality gates | Passed: 7 packs/21 skills with no warnings; 118 drift artifacts with zero drift; quality average 87.77 and minimum 68 |
| Standalone smoke | Passed in 1,510 seconds, including preview/apply/idempotence, nested update, transaction, overlay, cursor, and sidecar preservation under `.tmp/smoke-20260808190504` |
| Standalone profile/harness matrix | Passed in 1,377 seconds: 18/18 combinations, 0 failures; report `.tmp/matrix-20260808193753/matrix-report.json` |
| Full local CI | Passed all nine gates without skips; report `.tmp/ci/ci-report-20260809093416.json`. All 19 focused suites and all 18 matrix combinations passed; the reported wall duration includes two system suspensions and is not a performance measurement |

H-04 remains `OPEN_CHANGED`, not closed: WP-04 fixes continuous ownership across contract reduction, while the executable plan-bound, transactional, reversible, resumable, and idempotent uninstall required by WP-05 does not yet exist. No network access, dependency installation, commit, push, merge, publication, or release was performed.
