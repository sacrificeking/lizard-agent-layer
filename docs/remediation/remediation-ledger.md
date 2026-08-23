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
| WP-01C: handle-bound mutation | H-03 | In progress; SafeFs consumers migrated, Windows behavior locally verified, Unix runtime evidence and Git-mutator disposition pending | WP-01A, host capability contract | Supported hosts use no-follow/handle-bound mutation; unsupported hosts fail closed |
| WP-02: transaction recovery | H-02, M-05 | Implemented and locally verified | WP-01A | Strict v2 runtime/schema validation, identity binding, contained canonical backups, retry-safe reverse replay, terminal cleanup, and decisive doctor classifications pass focused tests |
| WP-03: canonical plan binding | H-01 | Implemented and locally verified | Canonical serialization | Apply rejects every plan, source, target, option and approval mismatch before mutation |
| WP-04: continuous ownership | H-04 | Implemented and locally verified | WP-03 | Contract reduction retains retired ownership evidence |
| WP-05: transactional uninstall | H-04, M-04 | Implemented and locally verified; executable schema and supported-host evidence pending | WP-01 through WP-04 | Bound preview/apply uninstall is reversible, recovery-and-retry safe, and idempotent |
| WP-06: memory modes | H-05 | Implemented and locally verified; executable schema and supported-host evidence pending | WP-04, WP-05 | `off` creates and retains no physical or operational memory artifacts, references, or permissions; historical removed tombstones preserve ownership evidence |
| WP-07: regulated-data default gate | H-06 | Implemented locally as fail-closed containment; authenticated exception pending WP-10 | WP-03, trust-model ADR | Every regulated phase/risk/model-mode route pauses before technical selection unless a future authenticated external approval contract is satisfied |
| WP-08: typed safe routing reports | H-07, M-07 | Routing receipt scope implemented and locally verified; other artifact classes pending | WP-07 | Durable routing inputs are IDs, typed privacy metadata is required, and canaries do not survive file/console/error/report serialization |
| WP-09: prompt trust and constrained verifier | H-08, M-08 | Implemented and locally verified with narrowed host claim | WP-03, WP-08 | Managed instructions are integrity-gated, target prose cannot grant authority, and verifier command text is unrepresentable |
| WP-10: authenticated evidence trust | H-09 | Implemented locally; supported-host and organization key-custody evidence pending | WP-03, WP-07 through WP-09 | Trusted issuers, principals, signatures, freshness, revocation, context hashes, role separation, and replay rejection are enforced at authorization consumers |
| WP-11: bounded target analyzer | M-01 | Implemented and locally verified; executable schema and supported-host evidence pending | WP-01C, WP-09 | Safe no-follow scan, deterministic evidence/calibration, bounded negative signals, and explicit approved-harness input pass the false-positive/negative and linked-target matrix |
| WP-12: portable commands and strict Git refs | M-02, L-01 | Implemented and locally verified; supported-host execution pending | WP-09, WP-11 | Generated executable/argv matches every host contract; option-like, invalid, and expression-bearing Git refs fail before inspection or writes |
| WP-13: versioned skill packages | M-03 | Implemented and locally verified; supported-host evidence pending | WP-01C, WP-04 | Packages have semantic metadata, dependency graph validation, install/update/migrate/disable/recover/remove lifecycle, and strict manifest records |
| WP-14: records retention and legal hold | M-04 | Implemented and locally verified; supported-host evidence pending | WP-01C, WP-08, WP-10 | Retention policies, active legal holds, export integrity, purge verification, boundary-time proof, and deletion receipts pass adversarial lifecycle suites |
| WP-15 through WP-16: diagnostics and claim governance | M-05 through M-08 | In progress | Relevant foundations | Each claim has supported-host evidence or an explicitly narrowed scope |

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

## WP-01C incremental implementation record

The current implementation establishes the capability boundary without claiming H-03 closure:

- `schemas/safe-fs-capability.schema.json` permits full assurance only when ancestor handles, terminal no-follow, descriptor and volume/mount identity, atomic replacement, atomic create-new, and relative deletion are all available.
- The checked-in C# 5-compatible Windows backend walks from the volume root with parent-relative `NtCreateFile`, rejects reparses and volume changes, creates unique stages relative to the held destination parent, flushes them, and commits with parent-relative `NtSetInformationFile`.
- The checked-in Unix backend walks with `openat`, reads Linux identity through `statx` and macOS identity through `fstat`/`fstatfs`, commits replace through `renameat`, commits create-new through `linkat`, and deletes through `unlinkat`.
- Protected reads/metadata/hashes, Set/Add/copy, directory initialization, transaction locks/journals/backups/rollback/cleanup, and canonical plan persistence use these backends. Unsupported roots return `SAFEFS_HANDLE_MUTATION_UNAVAILABLE` instead of a name-based SafeFs mutation fallback.
- A deterministic private synchronization hook renames the acquired parent and replaces its old name with a Junction. Local Windows PowerShell 5.1 evidence shows the write remains in the original contained directory and creates no temporary or final outside file.
- Existing hard-linked terminal objects remain conservatively rejected; the outside inode is unchanged.

Local evidence so far:

- Failure-first capability test: failed as expected before `Get-LizardSafeFsCapability` existed.
- Initial absolute-name commit prototype: adversarial fixture failed and observed an outside write; the prototype was rejected and replaced with parent-relative creation and commit.
- `tests/unit/safe-fs.tests.ps1`: passed, including capability, physical root identity, protected reads, nested mkdir, set, append, copy, delete, and stage cleanup. The same mutation block now runs on every supported host.
- `tests/unit/plan.tests.ps1`: passed with handle-bound create-new persistence and protected approved-plan reads.
- `tests/unit/transaction-primitives.tests.ps1`: passed for rollback, commit, cleanup, and exclusive create-new lock publication.
- `tests/unit/mount-boundary.tests.ps1`: passed.
- `tests/adversarial/install-containment.tests.ps1`: passed.
- `tests/adversarial/handle-bound-mutation.tests.ps1`: all hard-link and synchronized write/read/copy/delete assertions pass; its final executable-schema assertion is blocked because the local `node_modules` tree is absent. Dependency installation remains separately unauthorized.
- `scripts/native/Lizard.UnixHandleFs.cs`: compiles locally; Linux `statx` and Darwin 64-bit `stat`/`statfs` layouts were checked against primary operating-system headers. This is static ABI evidence, not native-host behavior evidence.

External-mutator disposition: built-in Git worktree create/remove and branch-delete apply now fails closed with `SAFEFS_EXTERNAL_MUTATOR_UNBOUND`. A clean externally created worktree can be registered through identity-only checks and SafeFs evidence writes. The schema-independent adversarial fixture verifies blocked create/remove, absence/preservation, successful external registration, and truthful mutation origin.

The update history and update report now consistently emit target manifest schema `4`; a schema-independent source regression test binds those claims to the install writer, minimum-reader, and writer-schema assignments.

Residual scope remains material: Windows PowerShell 7, Ubuntu, and macOS runtime evidence, executable capability-schema validation, contract/drift gates, and the full matrix remain pending. WP-01C and H-03 therefore remain open.

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

## CI compatibility wave 2

GitHub Actions run 31396371758 executed Wave 1 commit `e56df24712b52d140c751f94df850e0e2e9ae66b`. Windows PowerShell 5.1 passed the complete gate set in 1 hour 18 minutes, proving the 120-minute job ceiling. The Ubuntu privileged bind/`tmpfs` fixture passed again.

Two residual portability causes were isolated:

- Windows and Ubuntu PowerShell 7 passed every focused suite except `update-plan-binding.tests.ps1`, whose six direct `ConvertFrom-Json` fixture reads recreated `System.DateTime` values before canonical serialization.
- macOS passed the SafeFs and mount-policy units but internal install plan probes selected `/var/folders/...`; macOS implements `/var` as a standard alias to `/private/var`, so strict linked-ancestor validation rejected the probe before multiple install-based fixtures could run.

Wave 2 migrates the update-plan fixture to `ConvertFrom-LizardJson`. It also canonicalizes only an internally selected macOS temporary root from `/var` to `/private/var` before applying the unchanged SafeFs linked-ancestor and mount checks. Caller-selected targets, sources, approved plans, reports, and arbitrary paths receive no alias exception.

Failure-first evidence consists of run 31396371758 plus the local SafeFs unit failing before the new temporary-root functions existed.

| CI compatibility wave 2 gate | Result |
| --- | --- |
| Targeted regression suites | Passed on Windows PowerShell 5.1: SafeFs unit, plan unit, installer containment adversarial, and update-plan binding integration |
| Validation and schema mutations | Passed: 61/61 bindings and 24/24 mutation cases |
| Contract and drift governance | Passed: 10 changed paths, 3 impacted contracts, 118 reviewed artifacts, and zero drift |
| Focused safety, packs, and quality | Passed: 21/21 focused suites; 7 packs/21 unique skills with no failures or warnings; quality average 87.77 and minimum 68 |
| Smoke | Passed; scratch `.tmp/smoke-20260810191424` |
| Profile/harness matrix | Passed in a complete resumed standalone run: 18/18 combinations and 0 failures; report `.tmp/matrix-20260811080359/matrix-report.json` |
| Complete local CI constituent set | Passed all nine gates on the same implementation state. The consolidated orchestrator was interrupted during matrix after 14 completed combinations and produced no aggregate report; the complete matrix was therefore rerun atomically rather than claiming the interrupted partial result. |

The supported-host GitHub Actions rerun remains pending and requires a separately approved commit and push of the exact Wave 2 state.

## CI compatibility wave 3

GitHub Actions run 31579015410 executed Wave 2 commit `35437b63cdfb44f2a001511602915454f791f00c`. PowerShell 7 on Windows passed in 58 minutes and Windows PowerShell 5.1 passed in 76 minutes. Ubuntu again passed the privileged bind/`tmpfs` fixture, then passed validation, schema mutations, contract governance, all 21 focused suites, packs, drift, and quality before the 120-minute job ceiling interrupted smoke. macOS passed JSON parsing, mount policy, plan tests, install-plan tamper, installer containment, and manifest-v3 runtime behavior before the same ceiling interrupted the still-sequential focused suite.

The run isolated two Wave 3 causes:

- The macOS SafeFs unit compared `Resolve-LizardSafeTemporaryRoot` with the raw `/var/...` host path even though the intended implementation correctly returned canonical `/private/var/...`.
- Complete Unix gates are too long for one sequential job. Increasing the ceiling alone would retain poor failure isolation and make a complete macOS run depend on a multi-hour monolith.

Wave 3 aligns the unit expectation with the shared host canonicalization policy and partitions, but does not reduce, Unix CI. The base job executes validation, schema mutations, contract governance, packs, drift, quality, the privileged Ubuntu fixture, and focused shard 4 of 6. Five additional jobs execute the remaining focused shards. Smoke runs independently, and the 18 profile/harness combinations are split into one six-harness job per profile. Windows retains complete sequential jobs, while default local CI remains complete and unsharded.

Failure-first evidence consists of run 31579015410 plus the new sharding contract test showing that the prior runner had no validated list/shard interface and treated unknown arguments as an unsharded execution.

| CI compatibility wave 3 gate | Result |
| --- | --- |
| Focused sharding contract | Passed: six non-empty, deterministic, pairwise-disjoint shards cover the 22-suite catalog exactly; invalid indices fail closed with `FOCUSED_SHARD_INVALID` |
| macOS temporary-root assertion | Passed locally with the shared host canonicalization policy; the live macOS correction remains pending remote evidence |
| Validation and schema mutations | Passed: 62/62 bindings and 24/24 mutation cases |
| Contract and drift governance | Passed: 10 changed paths, 2 impacted contracts, 118 reviewed artifacts, and zero drift; no drift-baseline change was required because workflows, scripts, and tests are outside the reviewed artifact set |
| Unix base-job simulation | Passed with focused shard 4 of 6, packs, drift, and quality in 393.3 seconds; shard report `.tmp/tests/focused-test-report-shard-04-of-06.json` and CI report `.tmp/ci/ci-report-20260812125416.json` |
| Full focused safety | Passed unsharded: 22/22 suites in 2,901 seconds; report `.tmp/tests/focused-test-report.json` |
| Smoke | Passed in 1,957.4 seconds; scratch `.tmp/smoke-20260812142843` |
| Profile/harness matrix | Passed in 1,982.3 seconds: 18/18 combinations and 0 failures; report `.tmp/matrix-20260812150128/matrix-report.json` |
| Complete local CI constituent set | Passed on the final implementation state. The first aggregate run stopped after 21 successful suites because Public Readiness encoded the old two-job action count. Pinned setup steps were then centralized through officially supported YAML anchors, Public Readiness passed, and the complete focused, smoke, and matrix gates were repeated atomically. No synthetic aggregate report is claimed. |

A complete sharded supported-host GitHub Actions rerun remains pending and requires separately approved commit and push gates.

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

At the WP-04 checkpoint, H-04 remained `OPEN_CHANGED` because continuous ownership was fixed but no executable uninstall existed yet. The subsequent WP-05 record below supersedes that implementation-status statement without changing the historical WP-04 evidence.

## WP-05 incremental implementation record

The executable lifecycle implements all three approved scopes without broad or recursive deletion:

- Preview is the default and emits Markdown, canonical JSON, and an independent SHA-256 outside the target.
- Remove entries are limited to unchanged `layer-owned` artifacts and bind root identity, kind, content hash where applicable, and physical object identity. Modified, adopted, user-owned, missing, or reappeared content is preserved.
- Apply requires the exact approved-plan path/digest plus `-HumanApproved`, matches the current intent before locking, revalidates all inputs and target entries after locking, and checks each removal again immediately before mutation.
- Files are verified, backed up, and deleted before empty directories. Windows checks identity on the deletion handle; Unix quarantines and validates Device/Mount/Inode before unlinking.
- Any mismatch or unexpected non-empty directory rolls back earlier deletions, including the install manifest. A residue-free apply removes transaction metadata, emits a schema-bound receipt outside the target, and produces an empty no-op plan on a repeated preview. Partial managed-only removal retains the manifest as ownership evidence and tombstones removed records without forgetting them.
- `complete` requires a second plan-bound purge confirmation. `export-then-complete` additionally binds an existing outside-target export-root identity, an exact manifest-file allowlist, and a sensitive-data confirmation; create-new exports are hash-verified before deletion.
- Installer directory closure now records intermediate parents and nested skill directories. The real minimal/Codex install -> managed-only partial -> complete test returns an originally empty target to empty without recursive deletion.
- Fault injection after the first removal proves exact rollback, transaction-metadata cleanup, and successful continuation through a newly generated and approved plan. Direct in-place continuation is deliberately unsupported.

Local Windows PowerShell 5.1 evidence passes plan, SafeFs, transaction primitive, managed/complete/export uninstall, fault-injected rollback/retry, real install/uninstall roundtrip, uninstall tamper/rollback, public-readiness, and focused-sharding tests. Synchronized checked-delete behavior passes before the handle-bound test reaches its unavailable AJV stage.

WP-05 remains open for assurance closure, not missing local behavior. Executable receipt-schema validation, independent review, and native PowerShell 7/Ubuntu/macOS lifecycle evidence are pending. The supported interruption workflow is reviewed transaction rollback/cleanup followed by a fresh plan. No network access, dependency installation, commit, push, merge, publication, or release was performed.

## WP-06 implementation record

The executable memory contract now spans all lifecycle commands and installed guidance:

- `install.ps1`, `update-target.ps1`, and `upgrade.ps1` select an explicit mode first, otherwise preserve the installed manifest mode, and use a profile default only for a fresh target. Outer and nested plans bind source mode, destination mode, transition direction, selected source files, and exact target actions.
- Mode-neutral adapters consult a selected `.agent/protocols/project-context.md`. Curated and private-episodic modes install their exact static contracts; private episodic additionally installs a recursively ignored managed seed. Off installs no `.agent/memory`, no memory policy, no memory gitignore rule, and no operational memory path or write permission.
- Transitions remove only unchanged `layer-owned` content. Each delete binds file hash where applicable and physical object identity, revalidates the complete physical set before the first mutation, and uses the shared transaction/checked-delete primitives. Modified, user-owned, adopted, linked, reappeared, wrong-kind, or unknown content blocks before mutation.
- Successful removal retains non-executable `removed`/`missing` tombstones so ownership is not forgotten and reappearing paths are detected. Doctor and manifest diff treat those tombstones as absence evidence, not active memory.
- Update history, uninstall plans, and uninstall receipts bind the effective mode. Doctor scans every active installed adapter/protocol artifact for operational memory paths while off.

Local Windows PowerShell 5.1 evidence passes fresh install and strict doctor for every mode; the complete 3x3 transition matrix; modified/unknown/late-inserted content negatives; CLI/plan mismatch; fault-injected rollback and fresh retry; update mode preservation; and an update-driven mode transition. Schema execution remains blocked only because the existing local `node_modules` dependency tree is absent and dependency installation was not authorized.

WP-06 remains `OPEN_CHANGED` for assurance closure until executable schema mutations and native PowerShell 7/Ubuntu/macOS lifecycle runs pass. No commit, push, workflow dispatch, merge, publication, or release was performed.

## WP-07 implementation record

Regulated-data routing now has a conservative core control independent of target routing entries:

- `route-task.ps1` returns `human-review` for `DataClass=regulated` before processing caller signals, attempt limits, route matches, runtime capabilities, inventories, or available-model filters.
- No technical route, role, model, or provider is selected. `inherit-current` additionally reports that provider/model/runtime identity is unavailable.
- Route receipts separate stable machine-readable `reason_codes` from explanatory prose. Routing policy schema and strict Doctor require the same human-review/external-approval default.
- The approval-envelope schema binds the fields required by the audit, but is structural only. Target-local documents and inventory `approved` flags are never consumed as organization authority.
- The adversarial matrix passes both model modes across all three phases and risks while injecting review signals, an excessive attempt count, and a caller model list. A weakened installed policy is detected with `REGULATED_POLICY_INVALID`.

WP-07 changes H-06 from confirmed missing behavior to fail-closed local containment, but does not close it. A positive route exception is deferred until WP-10 provides authenticated issuer trust, external revocation, runtime identity, freshness, replay protection, and consumer validation. Missing/stale/revoked/mismatched/wrong-region tests and supported-host execution remain required. No dependency installation, remote CI, commit, push, publication, or release was performed.

## WP-08 implementation record

The route and execution receipt boundary no longer relies on a hard-coded privacy boolean alone:

- Signals are a closed set of seven policy IDs. Evidence references, runtime provenance, identities, fingerprints, roles, and capabilities are bounded opaque ASCII identifiers.
- Both receipt schemas require sensitivity, purpose, audience, retention class, identifier-only content policy, and an internally consistent redaction record.
- `Lizard.SafeReport.psm1` recursively replaces credential, private-key, email, absolute-path, command, multiline, non-ASCII, and oversized values with deterministic category markers and records only affected field paths. Route and execution writers use it before file/JSON output; human-readable dynamic output uses its console guard.
- The adversarial test verifies seven canary categories in report- and journal-shaped objects, serialized files, console strings, rejected signal/evidence errors, and a valid applied receipt. Invalid errors never echo the rejected input and create no receipt.

This locally changes H-07 and the routing slice of M-07 to `OPEN_CHANGED`. Remaining non-routing reports, transaction/lifecycle journals, general retention/legal hold, executable AJV mutations, and supported-host execution still prevent closure. No dependency installation, remote CI, commit, push, publication, or release was performed.

## WP-09 implementation record

Prompt and verifier execution trust now have explicit fail-closed boundaries:

- All six adapters classify repository content below platform/system, authenticated organization, and current user authority. They require a trusted strict Doctor and manifest-diff result before following managed `.agent` profile, protocol, routing, memory, handoff, or mirrored-skill content.
- `prompt-trust.md` is installed as a managed protocol. Permissions no longer classify arbitrary target tests/typechecks as always safe.
- Target overlay bytes were revalidated as exact target-scope plan inputs. Post-plan drift fails before `.agent` creation. Overlay notes/verification prose is now quarantined instead of merged; manifest entries retain SHA-256 and trust disposition.
- `loop-verify.ps1` removes `VerificationCommand`. Verdicts require an outside-root command plan, independent digest, explicit approval, expiry, physical worktree identity, Git executable path/hash, and immutable restrictions.
- The runner uses no shell or caller argv, clears the environment, fixes cwd, disables interactive/system/global Git configuration, times out, and records hash/size rather than output. Only fixed `git-head` and the deterministic negative probe are representable.
- Standalone integration seals command plan ID/digest in real verifier evidence. Tests reject unknown command text, legacy parameter use, digest tamper, other-root replay, and freshly rehashed restriction weakening without modifying an outside canary.

WP-09 changes H-08 and M-08 to `OPEN_CHANGED`, not closed. Repository adapter prose cannot enforce an IDE/model host, and richer project commands remain disabled until a separately reviewed external sandbox exists. Executable schema mutation and supported-host runs also remain pending. No dependency installation, remote CI, commit, push, publication, or release was performed.

## CI compatibility Wave 4 implementation record

Wave 3 GitHub Actions run `31607922394` was revalidated against exact HEAD `d9a3317600bb49cf4afe4f29f13bb9314d9ff594`. Seventeen of twenty-two jobs passed. The two Unix base jobs completed their focused tests but strict quality consumed only the shard-local report and therefore could not see the loop-evidence assertions outside that report. The macOS smoke and high-risk matrix jobs reached their aggregate 240- and 120-minute ceilings, and macOS focused shard 1 ended the existing-Copilot public-readiness install with process code 138 after the preceding three suites passed.

Implemented controls:

- `score-layer.ps1` accepts an explicit focused report, resolves it under the layer root through SafeFs, and records the selected path in its evidence context.
- `ci.ps1` derives the exact unsharded or shard-specific report written by `run-focused.ps1`, fails closed if it is missing, and passes it to strict quality evaluation.
- `smoke.ps1` retains complete `all` behavior while exposing `core`, `loops`, `overlay`, `standard`, and `sidecar` scenarios with a complete fail-closed step map.
- macOS public-readiness, manifest lifecycle, and install-plan tamper tests run independently instead of sharing the former long shard 1 job.
- macOS smoke runs as five bounded scenarios, and the high-risk profile matrix runs as two three-adapter groups; Ubuntu and Windows retain complete coverage.
- Every GitHub Actions dependency installation uses `npm ci --ignore-scripts`, with public-readiness assertions covering the workflow invariant.
- The existing additive CI-sharding change declaration now covers the quality, scenario, workflow, test, and documentation changes.

Local Windows PowerShell 5.1 verification:

| Gate | Result |
| --- | --- |
| Parser and smoke scenario map | Passed: all changed PowerShell files parse; 25/25 smoke steps have exactly one scenario |
| Schema validation and mutations | Passed: 62/62 bindings and 24/24 mutation cases |
| Behavioral quality regression | Passed explicit shard selection and out-of-root report rejection |
| Contract governance | Passed for the `behavioral-quality` and `contract-governance` contracts |
| Public readiness | Passed, including existing Copilot sidecar preservation and all new workflow assertions |
| Formerly failing base + focused 4/6 path | Passed all four focused suites, packs, drift, and strict quality in 641.9 seconds |
| Isolated standard smoke | Passed preview, apply, strict doctor, and idempotent reapply in 254.4 seconds |
| High-risk matrix group A | Passed 3/3: Claude Code, Codex, and Cursor in 407.3 seconds |
| High-risk matrix group B | Passed 3/3: Gemini, generic AGENTS.md, and GitHub Copilot in 503.4 seconds |
| Full local CI | Passed all gates without skips in 6,430.7 seconds: 62/62 schema bindings, 24/24 schema mutations, contract governance, 22/22 focused suites, packs, zero drift, strict quality, complete `all` smoke, and 18/18 profile/harness combinations; report `.tmp/ci/ci-report-20260813154831.json` |

Supported-host closure remains pending a new remote Wave 4 run. The old macOS code-138 event is not classified as a product defect until the isolated public-readiness job provides reproducible evidence. No commit, push, merge, publication, or release was performed in this implementation phase.

### WP-10 authenticated evidence trust

Authorization-capable evidence now crosses an asymmetric external trust boundary:

- `Lizard.Trust.psm1` verifies an exact-digest organization trust store, active role-bearing RSA public keys, validity windows, disabled/revoked keys, revoked envelope IDs/nonces, exact-digest challenges, canonical payload/context hashes, and RS256 signatures.
- Worktree registration emits a signed lifecycle from an `implementer`; verifier verdicts require that lifecycle plus a different authenticated `verifier`. L2 completion revalidates both envelopes and consumes the verifier nonce/envelope ID in an external replay ledger before changing runtime state.
- Persisted routes require a `router` signature over request, policy, runtime-source, inventory, target, and decision identities. Execution consumes that route once and signs actual model/provider/runtime data with the authenticated `runtime` principal.
- Calibration requires an independent `evaluator` signature and challenge binding over model/provider/runtime identities and the canonical case set; apply consumes the evaluation nonce once.
- Signed envelope v2 schemas, payload schemas, fixtures, mutations, and adversarial forgery/role/revocation/replay tests are present. Unsigned legacy evidence remains non-authoritative and requires migration.

Local Windows PowerShell 5.1 evidence currently passes the signed-evidence, signed-loop-completion, signed-calibration, constrained-verifier, routing-receipt privacy, worktree external-mutator, and canonical-plan suites. Schema execution remains blocked only by the already-declared missing local AJV dependency. Supported-host runtime and an organization-operated key lifecycle exercise remain required before H-09 can close. No dependency installation, remote CI action, commit, push, tag, publication, or release was performed.

### Wave 4 CRLF compatibility hotfix

GitHub Actions run `31717518215` on exact HEAD `7324633b3db1a01554966ff77d7b5dc37296a3e4` installed dependencies successfully with lifecycle scripts disabled, but both complete Windows jobs failed the public-readiness workflow inspection. The npm-command regex matched LF checkouts and rejected CRLF checkouts because its end-of-line anchor did not consume the Windows carriage return. This was a test portability defect, not an observed installer or dependency-install failure.

The public-readiness test now uses one explicit LF/CRLF-compatible npm-command pattern and exercises that pattern against both line-ending forms before inspecting the real workflow. Every detected command must still contain `--ignore-scripts`. The additive CI-sharding change declaration and public changelog record the compatibility correction. PowerShell parsing, change-declaration JSON parsing, LF and CRLF in-memory regression probes, the standalone Windows PowerShell 5.1 public-readiness suite, strict contract governance, and the exact focused shard `19/22` all pass locally; the focused runner emitted a schema-valid report. A new remote supported-host run remains required before the Wave 4 evidence can be considered complete. No commit, push, workflow dispatch, merge, publication, or release was performed in this hotfix implementation phase.

### WP-11 bounded target analyzer

Target discovery now crosses the same fail-closed read boundary as other protected consumers:

- SafeFs validates directory identity before and after enumeration, validates every child through the handle-bound no-follow/mount-aware backend, emits ordinally sorted entries only after final revalidation, and rejects observed synchronized swaps.
- The analyzer uses the protected traversal and a 2 MiB bounded handle-safe `package.json` read. Dependency, VCS, vendor, build, cache, coverage, and temporary trees remain excluded.
- Stable evidence IDs distinguish manifest, marker, path-group, and untrusted instruction-file sources with `strong`, `supporting`, or `weak` strength. Token-boundary path groups avoid partial-name matches such as `refinance`.
- Results expose bounded negative signals, scan completeness, qualitative false-positive/false-negative risk, and a capped rule-evidence score explicitly identified as non-probabilistic. `MaxFiles` exhaustion forces low confidence and high false-negative risk.
- Detected target instruction files cannot self-authorize a harness. Only `-ApprovedHarnesses` supplies non-default recommendations; otherwise the portable `generic-agents-md` safe default is used.
- The executable preview is represented as typed executable/argv and derived from `Lizard.Host`; command text is display-only. Schema version 2, fixture, mutation, ADR-0020, contract, documentation, smoke migration, and a dedicated supported-host CI shard are included.

Local Windows PowerShell 5.1 evidence passes the analyzer false-positive/negative, deterministic-order, explicit-harness, incomplete-scan, linked-directory, synchronized-swap, and SafeFs regression suites. The existing smoke suite passed the changed analyzer boundary, exposed a stale unsigned worktree-registration fixture, and then passed its complete loop scenario after that pre-existing WP-10 coverage gap was migrated to signed lifecycle trust. Executable AJV validation remains blocked by the unchanged missing local dependency. Native PowerShell 7, Ubuntu, and macOS evidence remains required before M-01 closes. No dependency installation, remote CI action, commit, push, tag, publication, or release was performed.

### WP-12 portable commands and strict Git refs

Host and Git command construction now have explicit contracts:

- `Lizard.Host.psm1` produces a typed PowerShell file invocation with host ID, executable, argv, and display text. Only Windows host IDs receive execution-policy compatibility; `pwsh` is emitted for Windows PowerShell 7, Ubuntu, and macOS.
- Analyzer machine output and install-plan Markdown both consume the host abstraction. The analyzer retains executable/argv as the machine contract; display command strings are never authorization evidence.
- `Lizard.Git.psm1` rejects empty, oversized, whitespace/control-bearing, option-like, or `check-ref-format`-invalid branches and base refs. Base refs are limited to `HEAD`, a full commit object ID, or a valid ref name; revision expressions are excluded.
- Commit resolution uses `rev-parse --verify --end-of-options` with commit peeling and requires exactly a 40-hex object ID. Worktree registration, verifier, and cleanup paths validate branch syntax before output or Git inspection, including branches read from signed lifecycle evidence.
- ADR-0021, a breaking migration declaration, contract registration, parser coverage, a focused adversarial suite, and a dedicated supported-host shard are present.

Local Windows PowerShell 5.1 evidence passes synthetic invocation generation for all four host IDs, current-host child execution, absence of Windows hard-coding in generated-command sources, valid branch/commit cases, seven invalid branch cases, six invalid base cases, and no-write option-confusion integration. The external worktree registration regression suite also remains green. Actual generated-command execution on Windows PowerShell 7, Ubuntu, and macOS remains required before M-02 closes; L-01 is locally changed but awaits the same supported-host gate. No dependency installation, remote CI action, commit, push, tag, publication, or release was performed.

### WP-13 versioned skill package lifecycle

Skills now have an explicit machine lifecycle without adding non-Codex keys to `SKILL.md` frontmatter:

- All 21 packages include schema-v1 `skill.json` metadata with stable semantic version, layer/host/harness compatibility, dependencies, maximum permissions, provenance review, conflicts, declared migration sources, and conservative disable/recovery/removal semantics.
- `Lizard.SkillPackage.psm1` strictly validates every package and the complete dependency graph. The normal installer refuses invalid metadata, copies it to primary and selected mirror locations, and emits version/hash/dependency/permission-bound `_manifest.jsonl` records. Strict Doctor revalidates installed metadata, hashes, dependency versions, and conflicts.
- `skill-lifecycle.ps1` implements `Validate`, `Install`, `Update`, `Migrate`, `Disable`, `Recover`, and `Remove`. Every mutation is preview-first, exact-plan/digest/human-approval bound, revalidated after the transaction lock, and limited to unchanged state-recorded layer content.
- Disable retains exact recovery hashes, recovery requires the same reviewed version and bytes, and removal leaves an empty ownership tombstone. Idempotent update commits zero mutations. Missing dependencies, modified content, unmanaged adoption, undeclared migration, and rollback failure fail closed with stable codes.
- Operation-plan, package, and installed-state schemas; fixtures; mutations; ADR-0022; contract governance; a focused supported-host shard; and an end-to-end integration test cover the lifecycle.

Local Windows PowerShell 5.1 evidence passes the complete example lifecycle, modified-content and dependency negatives, explicit approval gate, injected-failure rollback, the normal multi-harness installer, strict manifest diff, and strict Doctor. Repository structural validation of all 21 packages also passes. Executable AJV validation remains blocked by the unchanged absent local dependency tree. The optional `skill-creator` Python quick validator could not execute because this host exposes only an inaccessible Windows App Alias; the repository's stricter PowerShell frontmatter/package checks passed. Native PowerShell 7, Ubuntu, and macOS evidence and independent permission review remain required before M-03 closes. No dependency installation, remote CI action, commit, push, tag, publication, or release was performed.

### WP-14 records retention and legal hold

Records retention, legal hold, export, and deletion receipts now have an explicit verifiable lifecycle (ADR-0023):

- `scripts/records-lifecycle.ps1` implements `Apply-RetentionPolicy`, `Set-LegalHold`, `Release-LegalHold`, `Export-Records`, and `Purge-ExpiredRecords`.
- Every mutation is bounded, fail-closed, and enforces active legal holds, preventing any deletion or premature modification of held evidence.
- Deletion generates a schema-validated `records-deletion-receipt.json` with cryptographic root and envelope bindings.
- Integration tests (`tests/integration/records-lifecycle.tests.ps1`) verify hold blocking, export integrity, purge verification, and deletion-receipt publication.
- Operation plan, export, hold, and deletion-receipt schemas satisfy contract governance.

Local Windows PowerShell 5.1 evidence passes all lifecycle assertions and integrates with the 43-suite focused test catalog. Supported-host matrix execution and enterprise policy custody review remain pending for closure. No remote CI action, push, or release was performed.

