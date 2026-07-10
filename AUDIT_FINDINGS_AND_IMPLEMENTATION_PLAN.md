# Audit Findings and Implementation Plan

Repository: `lizard-agent-layer`
Audit date: 2026-07-10
Audited branch: `master`
Audited commit: `807de11d2780aa2b45f4f8e1d716c954ebd2dcec`
Audited version: `1.4.1`
Official audit score: `59.0/100` (raw consensus: `59.7/100`)
Maturity: `Developing`
Release verdict: `Not release-ready`

This document extracts the consolidated findings and dependency-aware implementation plan from the dual-specialist repository audit. It is intentionally implementation-focused and should be updated as findings are resolved.

## Priority Summary

| Priority | Findings | Release implication |
|---|---|---|
| P0 | F-001 | Must be fixed before the next release |
| P1 | F-002 through F-008 | Core correctness, preservation, update, portability, or loop-assurance work |
| P2 | F-009 through F-014 | Material quality, testing, portability, and developer-experience work |
| P3 | F-015 | Architecture-governance improvement |

Finding counts:

- Critical: 1
- High: 7
- Medium: 6
- Low: 1

## Implementation Progress

### Package 1 — Safe filesystem foundation

- **Status:** Implemented locally on 2026-07-10
- **Scope:** A1, F-001, and the preview-output correction from F-011
- **Evidence:** `scripts/Lizard.SafeFs.psm1`, `tests/unit/safe-fs.tests.ps1`, `tests/adversarial/install-containment.tests.ps1`, and `.tmp/tests/focused-test-report.json`
- **Passing gates:** structural validation, focused unit/adversarial tests, and the complete existing smoke suite
- **Remaining validation:** execute the same symbolic-link fixtures on Ubuntu and macOS in package 4; Windows junction fixtures already pass
- **Release note:** This removes the P0 write-escape behavior locally, but the repository remains not release-ready until the dependent P1 ownership, integrity, transaction, version, worktree, and verifier findings are resolved.

## Findings Register

### F-001 — Linked directories can redirect writes outside the target

- **Category:** Installer, Update, Manifest, and Merge Safety; Filesystem Safety
- **Priority:** P0
- **Severity:** Critical
- **Status:** Implemented locally; Windows regression gates passing, three-OS execution pending
- **Confidence:** High
- **Evidence:** `scripts/install.ps1:226-233`, `scripts/install.ps1:391-459`, `scripts/install.ps1:560-608`. Two independent fixtures reproduced writes through a target-controlled junction outside `TargetRoot`.
- **Impact:** Files may be created or replaced outside the project selected by the operator. Force modes can increase the potential impact.
- **Root cause:** Textual relative-path validation is treated as equivalent to resolved filesystem containment. Existing ancestors are not inspected for symlinks, junctions, mount points, or other reparse behavior immediately before mutation.
- **Failure scenario:** A target contains `.agent`, `.agents`, or a harness destination as a link to another writable directory. A normal apply operation follows it.
- **Recommended fix:** Introduce a shared safe-filesystem module. Resolve the nearest existing ancestor of every destination, reject reparse points by default, verify that the canonical destination remains within its authorized root, and repeat the check immediately before every write.
- **Affected files:** All write-capable scripts, especially `install.ps1`, `update-target.ps1`, `sync-manifest.ps1`, loop init/sync/verify scripts, and report writers.
- **Positive tests:** Ordinary nested target paths, missing destination parents, spaces, and valid sibling report directories continue to work.
- **Negative tests:** Windows junctions, directory/file symlinks, target-root equality, linked ancestors, and force modes must produce zero writes outside the authorized root.
- **Validation:** Run the negative fixtures on Windows, Ubuntu, and macOS; compare hashes and directory listings outside the fixture root before and after execution.
- **Rollback:** Remove routing through the shared guard. No target format migration is required.
- **Dependencies:** None. This must be implemented first.
- **Effort:** 3–5 days
- **Expected score uplift:** Approximately +1.6 overall

### F-002 — `ForceManaged` can overwrite files the layer did not create

- **Category:** Installer, Update, Manifest, and Merge Safety
- **Priority:** P1
- **Severity:** High
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `scripts/install.ps1:244-275`, `scripts/install.ps1:391-459`, `scripts/install.ps1:515-542`. Pre-existing or initially skipped `.agent` files are classified broadly enough to be replaced during a later managed refresh.
- **Impact:** Project-specific memory, protocols, or skills can be lost even though managed refresh is documented as targeting generated artifacts.
- **Root cause:** Desired, discovered, skipped, managed, created, and owned states are conflated. Namespace membership is used as a substitute for exact provenance.
- **Failure scenario:** A project owns or customizes `.agent/protocols/permissions.md`; a later update with `-ForceManaged` restores the generic layer template.
- **Recommended fix:** Introduce manifest schema v3 with per-file ownership class, source hash, last installed hash, current hash, source version, and adoption state. Refresh only exact entries proven to be layer-owned and unchanged since installation.
- **Affected files:** `scripts/install.ps1`, `scripts/update-target.ps1`, manifest schema, doctor, documentation, and fixtures.
- **Positive tests:** An unchanged layer-created file refreshes to a new source version.
- **Negative tests:** Pre-existing, customized, adopted-but-edited, forged-manifest, and ambiguous legacy files remain untouched and are reported as conflicts.
- **Validation:** Execute the full ownership-state matrix and inspect file hashes and manifest transitions.
- **Rollback:** Continue reading schema v2; classify ambiguous v2 entries as user-owned.
- **Dependencies:** F-001
- **Effort:** 4–6 days
- **Expected score uplift:** Approximately +1.2 overall

### F-003 — Installation and update are not transactional

- **Category:** Installer Safety; Loop Resilience
- **Priority:** P1
- **Severity:** High
- **Status:** Observed
- **Confidence:** High
- **Evidence:** Sequential writes at `scripts/install.ps1:560-608`; the install manifest is written last. Update applies installation, performs a post-check, and appends history sequentially at `scripts/update-target.ps1:233-270`. A collision fixture left partial state without a final manifest.
- **Impact:** Permission errors, interruption, disk exhaustion, or later path collisions can leave a mixed or unowned installation. A failed post-update check may occur after target content has already changed.
- **Root cause:** No complete preflight, staging directory, operation journal, backup, atomic commit, or recovery workflow exists.
- **Failure scenario:** Core `.agent` content is written, then creation of a harness mirror fails. The target contains a partial layer but no reliable successful-operation record.
- **Recommended fix:** Implement preflight, staging, a per-operation journal, backups for replacements, an atomic same-volume commit where possible, and explicit `recover`/`rollback` commands.
- **Affected files:** Installer, updater, loop init/sync, manifest/history writers, and a new transaction module.
- **Positive tests:** Complete install and update commit once, produce one manifest/history transition, and rerun safely.
- **Negative tests:** Inject failure after every mutation boundary; the target must remain unchanged or expose a deterministic recoverable journal.
- **Validation:** Fault-injection matrix, crash/restart tests, read-only destination tests, and concurrent-writer tests.
- **Rollback:** Replay the operation journal in reverse and restore exact backups.
- **Dependencies:** F-001, F-002
- **Effort:** 1–2 weeks
- **Expected score uplift:** Approximately +1.5 overall

### F-004 — Strict manifest diff can certify modified content

- **Category:** Installer Safety; Tests and Drift Protection; Governance
- **Priority:** P1
- **Severity:** High
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `scripts/manifest-diff.ps1:116-132` compares selected lists and existence. At line 122, harnesses are compared to themselves. A modified installed skill passed strict diff with zero differences.
- **Impact:** Stale, locally modified, truncated, or incorrectly mirrored files can be certified as aligned with the current layer.
- **Root cause:** The target manifest has no per-artifact content identity and the comparison does not validate actual file content or adapter identity.
- **Failure scenario:** A skill remains locally changed while update advances the recorded layer version and strict post-update validation reports success.
- **Recommended fix:** Store and compare expected source hash, recorded installed hash, current hash, mirror group, adapter identity, ownership, and source version.
- **Affected files:** `manifest-diff.ps1`, `install.ps1`, `doctor.ps1`, `update-target.ps1`, schemas, and reports.
- **Positive tests:** Unmodified installations produce a clean content-aware diff.
- **Negative tests:** A single-byte change to every artifact type or mirror must fail with the exact path and expected/actual hashes.
- **Validation:** Tamper matrix across protocols, skills, memory templates, profiles, sidecars, root instructions, and all harness mirrors.
- **Rollback:** Legacy manifests report `integrity-unknown`, never `pass`.
- **Dependencies:** F-002
- **Effort:** 3–5 days
- **Expected score uplift:** Approximately +1.0 overall

### F-005 — Combined adapters can silently install the wrong instruction

- **Category:** Architecture; Adapter Fidelity; Tests
- **Priority:** P1
- **Severity:** High
- **Status:** Observed
- **Confidence:** High
- **Evidence:** Generic and Codex adapters can both target `AGENTS.md`. `scripts/install.ps1:463-491` and `scripts/doctor.ps1:73-104` accept a common `lizard-agent-layer` substring rather than adapter-specific identity. A combined fixture installed generic content, recorded Codex too, and passed strict doctor.
- **Impact:** Manifest and diagnostics overstate harness fidelity; adapter ordering changes the installed result.
- **Root cause:** No expanded destination-conflict graph, precedence model, or adapter-specific marker exists.
- **Failure scenario:** A selected pack adds Codex after a generic profile already targets `AGENTS.md`; the generic instruction remains while both adapters are reported as installed.
- **Recommended fix:** Build the complete destination graph before planning. Reject undeclared collisions, support explicit compatibility/precedence declarations, and embed adapter ID/version/hash markers.
- **Affected files:** Adapter schema/manifests, installer, validator, doctor, matrix, and documentation.
- **Positive tests:** Declared compatible aliases resolve deterministically.
- **Negative tests:** Every undeclared pairwise collision and order reversal fails before target mutation.
- **Validation:** Test all adapter pairs and every expanded profile-plus-pack combination.
- **Rollback:** Introduce warning-only diagnostics for one release before making collisions fatal.
- **Dependencies:** F-004
- **Effort:** 3–5 days
- **Expected score uplift:** Approximately +1.5 overall

### F-006 — Worktree creation and cleanup disagree about valid locations

- **Category:** Loop Runtime and Resilience
- **Priority:** P1
- **Severity:** High
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `scripts/loop-worktree.ps1:41-49,78-88` permits a target-contained path, while `scripts/loop-worktree-cleanup.ps1:56-60` refuses to clean it. A fixture created a nested worktree and dirtied the main tree.
- **Impact:** The layer can create a worktree that its own cleanup tool rejects, undermining isolation and recovery.
- **Root cause:** Creation, verification, and cleanup do not share one persisted lifecycle contract.
- **Failure scenario:** A user passes `TargetRoot/nested-worktree` or another relative target-contained location.
- **Recommended fix:** Reject target-equal and target-contained worktree paths during creation. Persist repository common directory, target root, worktree root, branch, base SHA, and operation ID for verification and cleanup.
- **Affected files:** Worktree creation, verifier, cleanup, schemas, templates, and documentation.
- **Positive tests:** Valid sibling worktree creation, verification, and cleanup complete successfully.
- **Negative tests:** Equal, nested, linked, wrong repository, wrong branch, dirty, detached-HEAD, and missing-path cases fail safely.
- **Validation:** Full lifecycle matrix with clean final Git status.
- **Rollback:** Publish a manual recovery command for legacy nested worktrees.
- **Dependencies:** F-001
- **Effort:** 2–3 days
- **Expected score uplift:** Approximately +1.0 overall

### F-007 — Downgrades and manifest version transitions are informational only

- **Category:** Update Safety; Governance
- **Priority:** P1
- **Severity:** High
- **Status:** Observed
- **Confidence:** High
- **Evidence:** Version relation is calculated at `scripts/update-target.ps1:180-191`, but apply proceeds unconditionally at lines 233-270. A target declaring version `99.0.0` was updated by layer version `1.4.1` without an override.
- **Impact:** Older layer checkouts can overwrite newer target contracts and discard fields or semantics they do not understand.
- **Root cause:** There is no minimum reader/writer version, migration registry, compatibility gate, or explicit downgrade policy.
- **Failure scenario:** A developer updates a target created by a newer release using an older checkout.
- **Recommended fix:** Block future-version targets by default; require explicit `-AllowDowngrade` plus approval; define reader/writer versions and ordered migrations.
- **Affected files:** Updater, upgrade wrapper, schemas, manifest, history, and documentation.
- **Positive tests:** Same-version and supported forward upgrades succeed.
- **Negative tests:** Future, incompatible major, malformed, and unapproved downgrade cases stop before writes.
- **Validation:** Complete version-relation and schema-transition matrix.
- **Rollback:** Restore transaction backup and prior manifest.
- **Dependencies:** F-002, F-003
- **Effort:** 2–4 days
- **Expected score uplift:** Approximately +0.7 overall

### F-008 — Verifier verdicts are not bound to immutable evidence

- **Category:** Loop Runtime; Tests and Assurance
- **Priority:** P1
- **Severity:** High
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `scripts/loop-verify.ps1` accepts verifier name, status, and summary as caller-supplied values. It does not require a reviewed HEAD SHA, tree/diff hash, verification commands, exit codes, or evidence hashes.
- **Impact:** A PASS packet does not prove which revision or results were reviewed and can become stale immediately.
- **Root cause:** Repository/branch binding exists, but semantic verification evidence and separation of roles remain policy-only.
- **Failure scenario:** A verifier report is generated, then the worktree changes or never ran the asserted checks.
- **Recommended fix:** Bind verdicts to HEAD, tree/diff hash, command list, exit codes, timestamps, evidence-file hashes, dirty-state snapshot, and reviewer identity.
- **Affected files:** Verifier script, schema, template, skill, audit/report tooling, and smoke tests.
- **Positive tests:** A complete, unchanged, passing evidence packet is accepted.
- **Negative tests:** Changed HEAD, dirty-after-verification, missing evidence, failed command, self-verification, wrong repository, and report tampering are rejected.
- **Validation:** Recompute hashes during audit and before any completion transition.
- **Rollback:** Keep `NEEDS_REVIEW` packet generation as a non-verdict mode.
- **Dependencies:** Structured evidence schema; F-003 is recommended.
- **Effort:** 4–7 days
- **Expected score uplift:** Approximately +1.0 overall

### F-009 — Host portability is unverified beyond Windows

- **Category:** Portability; Tests; Developer Experience
- **Priority:** P2
- **Severity:** Medium
- **Status:** Observed
- **Confidence:** High
- **Evidence:** Production scripts and tests repeatedly invoke `powershell.exe`; `.github/workflows/lizard-agent-layer-ci.yml` runs only `windows-latest`.
- **Impact:** Executable discovery, case sensitivity, permissions, encoding, path separators, and link behavior may fail on macOS or Linux.
- **Root cause:** Harness portability and installer-host portability are conflated.
- **Recommended fix:** Use the current PowerShell host or canonical `pwsh`, remove Windows-only assumptions, and add Windows, Ubuntu, and macOS CI jobs.
- **Affected files:** PowerShell child-process calls, path helpers, workflow, tests, and documentation.
- **Positive tests:** Full CI passes on Windows PowerShell 5.1 and PowerShell 7 on all supported OS families.
- **Negative tests:** Case-sensitive collisions, Unix links, read-only permissions, spaces, and unusual path characters.
- **Validation:** Identical gate set and artifacts across the OS matrix.
- **Rollback:** Retain a Windows compatibility shim and separate 5.1 job.
- **Dependencies:** F-001 and portable fixtures.
- **Effort:** 1–2 weeks
- **Expected score uplift:** Approximately +1.5 overall

### F-010 — Published schemas are not used as executable contracts

- **Category:** Architecture; Maintainability; Governance
- **Priority:** P2
- **Severity:** Medium
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `scripts/validate.ps1:206-218` parses schema JSON but validates instances through partial hand-written checks rather than Draft 2020-12 schemas.
- **Impact:** Incorrect nested types, unexpected fields, and incompatible schema changes can pass validation and reach installers.
- **Root cause:** Schema documents and runtime acceptance evolved separately.
- **Recommended fix:** Select a pinned Draft 2020-12 validator and validate profiles, packs, adapters, model profiles, loops, registries, manifests, and reports.
- **Affected files:** Validator, schemas, all declarative JSON, CI, and authoring documentation.
- **Positive tests:** Every current valid document passes.
- **Negative tests:** Wrong types, missing nested fields, invalid enums, unknown fields, unsafe paths, and unsupported versions fail predictably.
- **Validation:** Mutation corpus executed as a dedicated CI gate.
- **Rollback:** Run schema violations in warning mode for one release.
- **Dependencies:** Validator selection and schema cleanup.
- **Effort:** 4–6 days
- **Expected score uplift:** Approximately +1.1 overall

### F-011 — Preview reports may write inside the target

- **Category:** Installer Safety; Documentation and DX
- **Priority:** P2
- **Severity:** Medium
- **Status:** Implemented locally; cross-platform execution pending
- **Confidence:** High
- **Evidence:** `scripts/install.ps1:192-205,385-389` and `scripts/update-target.ps1:216-229` accept output paths inside the target. Fixtures confirmed that preview mode can create target-local plan/report files.
- **Impact:** Automation relying on preview as a target no-op can dirty the target repository.
- **Root cause:** Output containment is enforced by some loop scripts but not through a shared invariant.
- **Recommended fix:** Reject preview output paths resolving inside the target unless a separately named explicit opt-in is provided.
- **Affected files:** Installer, updater, merge/report generators, shared path helper, and documentation.
- **Positive tests:** Default reports outside the target continue to work.
- **Negative tests:** Relative, absolute, linked, equal-root, nested, parent-traversal, and case-variant target-local paths fail.
- **Validation:** Assert target hash and Git status remain unchanged after every preview command.
- **Rollback:** Preserve an explicit `-AllowTargetReportWrite` compatibility option.
- **Dependencies:** F-001
- **Effort:** 1–2 days
- **Expected score uplift:** Approximately +0.5 overall

### F-012 — Loop budgets, concurrency, and recovery are advisory

- **Category:** Loop Runtime and Resilience
- **Priority:** P2
- **Severity:** Medium
- **Status:** Observed
- **Confidence:** High
- **Evidence:** Budget, attempt, cadence, and kill-switch fields exist in templates and skills, but no executable runner accounts for tokens, acquires leases, prevents duplicate runs, or performs atomic state transitions.
- **Impact:** Duplicate runs, budget overruns, repeated failure, and inconsistent state remain possible in the external scheduling harness.
- **Root cause:** Policy artifacts are described as runtime controls without an enforcing state machine.
- **Recommended fix:** Either narrow the claim to a loop policy/toolkit or implement structured state, atomic leases, run IDs, attempt accounting, budget enforcement, append-only events, and recovery.
- **Affected files:** Loop templates, schemas, init/audit/report/sync tooling, verifier, and a possible new runner.
- **Positive tests:** A valid run acquires one lease, consumes budget once, records one event chain, and releases cleanly.
- **Negative tests:** Duplicate run, exhausted budget, crash/restart, stale lease, repeated failure, and verifier rejection fail closed.
- **Validation:** Deterministic state-machine integration suite.
- **Rollback:** Preserve report-only L1 toolkit mode as the default.
- **Dependencies:** F-003 and F-008
- **Effort:** 2–4 weeks
- **Expected score uplift:** Approximately +1.5 overall

### F-013 — Merge patches duplicate all existing instruction content

- **Category:** Report Safety and Developer Experience
- **Priority:** P2
- **Severity:** Medium
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `scripts/merge-suggestions.ps1:77-96,146-157` includes every original instruction line in generated append patches.
- **Impact:** Private project instructions are copied into secondary report artifacts that may be shared separately.
- **Root cause:** Patch generation favors full context instead of minimal-context output.
- **Recommended fix:** Generate zero-context append patches or path/hash summaries by default; clearly label report sensitivity; make existing-content inclusion an explicit opt-in.
- **Affected files:** Merge suggestion generator, report helper, secret-handling guidance, docs, and tests.
- **Positive tests:** Copy-ready merge guidance remains usable without reproducing original content.
- **Negative tests:** Seeded canary values must not appear in default patch, Markdown, JSON, or console output.
- **Validation:** Automated canary scan of every report format.
- **Rollback:** `-IncludeExistingContext` explicit mode.
- **Dependencies:** Shared report-output helper.
- **Effort:** 1–2 days
- **Expected score uplift:** Approximately +0.4 overall

### F-014 — Quality maturity is primarily lexical

- **Category:** Tests; Quality; Governance
- **Priority:** P2
- **Severity:** Medium
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `scripts/score-layer.ps1:103-201` awards points for document length, headings, bullets, support directories, and safety/testing keywords.
- **Impact:** A polished but behaviorally weak artifact can appear more mature than a concise artifact with strong executable tests.
- **Root cause:** Documentation completeness and behavioral assurance share one maturity model.
- **Recommended fix:** Separate `documentation_score` from behavioral readiness. Require runnable positive/negative fixtures, compatibility evidence, provenance, and review records for hardened/certified maturity.
- **Affected files:** Quality scorer, rubric, maturity registry, reports, skill-authoring docs, and CI.
- **Positive tests:** Concise behaviorally verified artifacts can reach high readiness.
- **Negative tests:** Keyword-stuffed or structurally polished unsafe fixtures cannot certify.
- **Validation:** Curated adversarial scoring corpus.
- **Rollback:** Preserve the current score under a non-blocking documentation-quality name.
- **Dependencies:** Behavioral fixture runner and F-010.
- **Effort:** 4–6 days
- **Expected score uplift:** Approximately +0.8 overall

### F-015 — Architectural compatibility and migration decisions are undocumented

- **Category:** Architecture; Maintainability; Documentation; Governance
- **Priority:** P3
- **Severity:** Low
- **Status:** Observed
- **Confidence:** High
- **Evidence:** `docs/architecture.md` describes layers and principles but there is no ADR set, compatibility matrix, deprecation policy, manifest migration policy, or module dependency contract.
- **Impact:** Refactoring installers, adapters, schemas, and loop semantics risks hidden backward incompatibility.
- **Root cause:** Feature growth outpaced architecture governance.
- **Recommended fix:** Add short ADRs for source of truth, target containment, file ownership, adapter precedence, manifest evolution, transaction semantics, report boundaries, and loop lifecycle.
- **Affected files:** New `docs/adr/` records, architecture docs, contributing guide, and release checklist.
- **Positive tests:** Contract-changing PRs link an ADR and migration note.
- **Negative tests:** Release validation rejects a schema/contract change without the required decision and migration metadata.
- **Validation:** Documentation onboarding and release dry run.
- **Rollback:** Documentation-only change.
- **Dependencies:** Decisions from F-001 through F-008.
- **Effort:** 1–2 days
- **Expected score uplift:** Approximately +0.5 overall

## Top 12 Improvements

The following improvements are ordered by dependency and leverage.

1. **Central path-containment module** — Route every write through a canonical destination resolver and add Windows junction plus Unix symlink negative fixtures.
2. **Manifest v3 ownership and integrity** — Record exact ownership, provenance, source/installed/current hashes, source version, and adapter identity.
3. **Transactional installer/update engine** — Preflight, lock, stage, journal, back up, commit, recover, and roll back.
4. **Content-aware strict manifest diff** — Validate actual artifact content and every mirror rather than only selection and existence.
5. **Adapter destination conflict graph** — Reject undeclared collisions before target mutation and verify adapter-specific identity.
6. **Unified worktree lifecycle** — Share one path/repository/branch contract across create, verify, and cleanup.
7. **Version and migration gates** — Block future-version targets and require explicit approved downgrade/migration.
8. **Evidence-bound verifier** — Bind verdicts to revision, diff, commands, exits, and evidence hashes.
9. **Three-OS PowerShell 7 CI** — Run the complete gate set on Windows, Ubuntu, and macOS.
10. **Real JSON Schema validation** — Execute Draft 2020-12 validation and mutation tests.
11. **Behavioral maturity gates** — Separate documentation quality from executable behavioral assurance.
12. **Explicit loop product boundary** — Implement an enforcing state machine or describe the current feature as a policy/toolkit layer.

## Dependency Graph

```text
A1 Safe filesystem
  +--> A2 Manifest v3
  |      +--> B2 Integrity diff
  |      |      +--> B3 Adapter conflict/identity
  |      +--> C2 Version migrations
  +--> B1 Transactions and locks
  |      +--> C2 Version migrations
  |      +--> F1 Enforceable loop runtime
  +--> C1 Worktree lifecycle
  +--> D2 Cross-platform CI

D1 Adversarial test framework
  +--> D2 Cross-platform CI
  +--> D3 Schema and behavioral quality
  +--> F1 Enforceable loop runtime

B2 Integrity diff + structured evidence
  +--> C3 Evidence-bound verifier
```

## Implementation Plan

### A — Baseline and Safety Net

#### A1 — Shared safe-filesystem foundation

- **Priority:** P0
- **Status:** Implemented locally; Windows validation complete, Unix CI execution pending
- **Goal:** Make the authorized filesystem boundary an executable invariant.
- **Files:** New `scripts/Lizard.SafeFs.psm1`; every write-capable script.
- **Steps:**
  1. Inventory every directory creation, copy, write, append, rename, worktree, plan, and report destination.
  2. Define target and report roots explicitly per operation.
  3. Implement canonical root normalization and nearest-existing-ancestor resolution.
  4. Reject target equality where inappropriate and reject or safely resolve reparse points.
  5. Recheck immediately before mutation to reduce time-of-check/time-of-use gaps.
  6. Route all write operations through the helper.
  7. Add structured path rejection details to reports.
- **Dependencies:** None
- **Acceptance criteria:** No force mode or destination type can write outside its authorized root; valid paths retain current behavior.
- **Validation:** Unit path tests; Windows junction/file/directory link fixtures; Unix symlink fixtures; full existing CI.
- **Rollback:** Revert module integration.
- **Effort:** 3–5 days
- **Score uplift:** +1.6

#### A2 — Manifest v3 ownership and artifact identity

- **Priority:** P1
- **Goal:** Replace path-class inference with evidence-based ownership and integrity.
- **Files:** `scripts/install.ps1`, `scripts/update-target.ps1`, `scripts/doctor.ps1`, schemas, docs, fixtures.
- **Steps:**
  1. Define artifact states: layer-owned, user-owned, adopted, locally modified, missing, stale-unmodified, conflict.
  2. Add source path/version/hash, installed hash, current hash, adapter ID, mirror group, and ownership to each manifest entry.
  3. Read v2 and v3 manifests; never infer ownership from a broad directory prefix.
  4. Default ambiguous legacy entries to user-owned.
  5. Narrow `ForceManaged` to exact unchanged layer-owned entries.
  6. Add file-specific conflict reporting and optional explicit adoption.
- **Dependencies:** A1
- **Acceptance criteria:** User-owned or customized files cannot be replaced by `ForceManaged`; unchanged layer-created files can be refreshed.
- **Validation:** Full ownership-state matrix plus v2 migration fixtures.
- **Rollback:** Dual-read compatibility and optional temporary v2 writer.
- **Effort:** 4–6 days
- **Score uplift:** +1.2

#### A3 — Split and strengthen the test harness

- **Priority:** P1
- **Goal:** Make every confirmed failure class a permanent regression test.
- **Files:** New `tests/unit/`, `tests/integration/`, `tests/adversarial/`; refactor `tests/smoke.ps1`.
- **Steps:**
  1. Extract fixture creation and assertions into shared helpers.
  2. Preserve the end-to-end smoke suite.
  3. Add isolated tests for containment, ownership, preview no-op, adapter collisions, worktrees, downgrade, and content drift.
  4. Add failure injection and concurrency helpers.
  5. Emit machine-readable test results and optional coverage metadata.
- **Dependencies:** Can start in parallel with A1.
- **Acceptance criteria:** Every F-001 through F-014 correction has at least one positive and one negative automated test.
- **Validation:** Intentional regression must fail the relevant focused suite before full CI.
- **Rollback:** Test-only; retain the original smoke entry point during migration.
- **Effort:** 1–2 weeks, incremental
- **Score uplift:** +1.5

### B — P0/P1 Corrections

#### B1 — Transaction engine and per-target locking

- **Priority:** P1
- **Goal:** Make apply/update atomic or deterministically recoverable.
- **Files:** New transaction module; installer, updater, loop init/sync, history writers.
- **Steps:**
  1. Create a unique operation ID and acquire an atomic target lock.
  2. Preflight the full source/destination graph before writes.
  3. Stage generated output outside the target.
  4. Record planned creates/replacements and backup locations in a write-ahead journal.
  5. Commit in deterministic order with same-volume atomic replacement where supported.
  6. Write the manifest and history only after successful commit.
  7. Provide `recover`, `rollback`, and stale-lock diagnostics.
- **Dependencies:** A1, A2
- **Acceptance criteria:** Injected failure leaves the previous target intact or a valid recoverable journal; two concurrent writers cannot both mutate state.
- **Validation:** Failure after every mutation index; crash/restart; stale lock; read-only file; collision; concurrent processes.
- **Rollback:** Journal-driven exact restoration.
- **Effort:** 1–2 weeks
- **Score uplift:** +1.5

#### B2 — Content-aware strict manifest diff

- **Priority:** P1
- **Goal:** Make `-Strict` a defensible content and contract check.
- **Files:** `scripts/manifest-diff.ps1`, doctor, updater, schema, reports.
- **Steps:**
  1. Fix expected-vs-actual harness comparison.
  2. Compare every current artifact against manifest/source hashes.
  3. Validate mirror group completeness and equality.
  4. Distinguish local customization from stale generated content.
  5. Return `integrity-unknown` for legacy manifests.
  6. Prevent update history from claiming alignment while unresolved differences exist.
- **Dependencies:** A2
- **Acceptance criteria:** Every artifact mutation is detected and reported with an exact disposition.
- **Validation:** Complete tamper matrix plus unchanged happy path.
- **Rollback:** Legacy existence-only mode remains available as explicitly non-strict diagnostics.
- **Effort:** 3–5 days
- **Score uplift:** +1.0

#### B3 — Adapter composition and identity gate

- **Priority:** P1
- **Goal:** Make expanded adapter results deterministic and verifiable.
- **Files:** Adapter schema/manifests, installer, validator, doctor, matrix.
- **Steps:**
  1. Build the final adapter selection before planning.
  2. Construct a destination and mirror graph.
  3. Reject conflicts unless a compatibility or precedence declaration exists.
  4. Add adapter ID/version/source hash markers.
  5. Make doctor validate exact expected identity.
  6. Expand matrix tests to combinations, not only single adapters.
- **Dependencies:** A2, B2
- **Acceptance criteria:** No adapter is recorded as installed unless its expected instruction identity is present.
- **Validation:** All pairs, all profile/pack expansions, both orderings, existing project instruction, and declared alias fixtures.
- **Rollback:** Warning-only transition for one release.
- **Effort:** 3–5 days
- **Score uplift:** +1.5

#### B4 — Downgrade and migration gates

- **Priority:** P1
- **Goal:** Prevent unsupported readers/writers from silently mutating target state.
- **Files:** Updater, upgrade wrapper, schemas, manifest, history, docs.
- **Steps:** Define reader/writer versions; create ordered migrations; block future versions; add explicit approved downgrade; back up before migration.
- **Dependencies:** A2, B1
- **Acceptance criteria:** Unsupported versions stop before writes with an actionable diagnosis.
- **Validation:** Same, patch, minor, major, future, malformed, and approved downgrade matrix.
- **Rollback:** Transaction backup.
- **Effort:** 2–4 days
- **Score uplift:** +0.7

#### B5 — Unified worktree lifecycle

- **Priority:** P1
- **Goal:** Ensure every created worktree is verifiable and cleanable by the same toolchain.
- **Files:** Worktree create/verify/cleanup scripts, schema, docs.
- **Steps:** Share path rules; forbid nested paths; persist identity; require identity in verify/cleanup; add recovery diagnostics.
- **Dependencies:** A1
- **Acceptance criteria:** Creation cannot produce a state cleanup rejects.
- **Validation:** Full lifecycle matrix including dirty, detached, wrong repository, and legacy recovery.
- **Rollback:** Manual recovery guide.
- **Effort:** 2–3 days
- **Score uplift:** +1.0

#### B6 — Evidence-bound verifier

- **Priority:** P1
- **Goal:** Make a verifier verdict reproducible and revision-specific.
- **Files:** Verifier script, schema, template, skills, audit/report scripts.
- **Steps:** Capture HEAD/tree/diff hashes; commands and exits; evidence hashes; reviewer identity; dirty state; expiry/change invalidation.
- **Dependencies:** Structured schema; B1 recommended.
- **Acceptance criteria:** PASS cannot survive a changed revision or missing/failed evidence.
- **Validation:** Negative evidence and tamper matrix.
- **Rollback:** `NEEDS_REVIEW` non-verdict mode.
- **Effort:** 4–7 days
- **Score uplift:** +1.0

### C — Architecture and Portability

#### C1 — PowerShell 7 and three-OS support

- **Priority:** P1
- **Goal:** Establish real host portability.
- **Files:** Child process invocation, path helpers, workflow, tests, docs.
- **Steps:** Replace hard-coded `powershell.exe`; normalize portable path behavior; add Windows/Ubuntu/macOS jobs; retain 5.1 compatibility.
- **Dependencies:** A1, A3
- **Acceptance criteria:** Identical gate set passes on all supported OS families.
- **Validation:** Links, permissions, case sensitivity, spaces, and encoding fixtures.
- **Rollback:** Windows-only compatibility job remains available.
- **Effort:** 1–2 weeks
- **Score uplift:** +1.5

#### C2 — Shared composition and utility modules

- **Priority:** P2
- **Goal:** Remove duplicated pack, list, path, JSON, and Git logic from procedural scripts.
- **Files:** New PowerShell modules; installer, diff, update, loop scripts.
- **Dependencies:** Stabilized A/B contracts.
- **Acceptance criteria:** One tested implementation for each shared operation; no behavior change in golden fixtures.
- **Validation:** Unit tests and full CI.
- **Rollback:** Revert module extraction.
- **Effort:** 1–2 weeks incrementally
- **Score uplift:** +0.7

### D — Reliability and Quality Gates

#### D1 — Executable JSON Schema validation

- **Priority:** P2
- **Goal:** Make published schemas the actual accepted contracts.
- **Files:** Validator, schemas, JSON instances, CI.
- **Dependencies:** A3; manifest v3 schema from A2.
- **Acceptance criteria:** Every current document validates; mutations fail deterministically.
- **Validation:** Dedicated schema and mutation gate.
- **Rollback:** Warning-only rollout.
- **Effort:** 4–6 days
- **Score uplift:** +1.1

#### D2 — Behavioral quality and maturity

- **Priority:** P2
- **Goal:** Separate documentation quality from behavioral readiness.
- **Files:** Quality scorer, rubric, maturity registry, reports, authoring docs.
- **Dependencies:** A3, D1
- **Acceptance criteria:** Certification requires runnable positive/negative evidence and compatibility metadata.
- **Validation:** Adversarial scoring corpus.
- **Rollback:** Retain legacy score as `documentation_score`.
- **Effort:** 4–6 days
- **Score uplift:** +0.8

#### D3 — Preview and report-boundary consistency

- **Priority:** P2
- **Goal:** Make preview a target no-op by default and minimize copied target content.
- **Files:** Installer, updater, report/merge generators, docs.
- **Dependencies:** A1
- **Acceptance criteria:** Preview leaves target hash and Git status unchanged; default merge reports do not duplicate existing instructions.
- **Validation:** Output containment and canary-data tests.
- **Rollback:** Explicit compatibility flags.
- **Effort:** 2–3 days
- **Score uplift:** +0.7

### E — Documentation and Governance

#### E1 — ADR and compatibility baseline

- **Priority:** P3
- **Goal:** Document durable contracts and migration expectations.
- **Files:** New `docs/adr/`, architecture docs, contributing guide, release checklist.
- **Steps:** Record containment, ownership, adapter precedence, manifest migration, transactions, report boundaries, and loop semantics.
- **Dependencies:** A/B design decisions.
- **Acceptance criteria:** Contract-changing PRs include an ADR and migration/disposition note.
- **Validation:** Release dry run and new-contributor onboarding exercise.
- **Rollback:** Documentation-only.
- **Effort:** 2–4 days
- **Score uplift:** +0.5

#### E2 — Recovery and troubleshooting documentation

- **Priority:** P2
- **Goal:** Make interrupted install/update/worktree recovery operable without source-code reading.
- **Files:** Getting started, update, safety, loop engineering, new troubleshooting guide.
- **Dependencies:** B1 and B5 behavior finalized.
- **Acceptance criteria:** A fresh operator can diagnose and recover all supported failure states from docs alone.
- **Validation:** Documentation usability test using scratch fixtures.
- **Rollback:** Documentation-only.
- **Effort:** 2–3 days
- **Score uplift:** +0.4

### F — Strategic Differentiation

#### F1 — Enforceable loop state machine or explicit toolkit scope

- **Priority:** P2
- **Goal:** Align the product claim with executable behavior.
- **Files:** Loop schemas/templates/scripts and potentially a new runner.
- **Steps:** Decide scope; if runtime is retained, add leases, atomic state, budgets, attempts, run IDs, append-only events, recovery, and verifier-bound completion.
- **Dependencies:** B1, B5, B6, A3
- **Acceptance criteria:** Duplicate, exhausted, crashed, stale, and unverifiable runs fail closed and remain recoverable.
- **Validation:** Deterministic state-machine integration suite.
- **Rollback:** Keep the current L1 report-only toolkit as the default product mode.
- **Effort:** 2–4 weeks
- **Score uplift:** +1.5

## Suggested Delivery Sequence

| Milestone | Included tasks | Expected outcome |
|---|---|---|
| M1 — Release blocker | A1 plus F-001 regression tests | Authorized write boundary becomes enforceable |
| M2 — Ownership baseline | A2, B2, B3, B4 | Managed updates and adapter claims become evidence-based |
| M3 — Failure resilience | B1, B5, B6 | Interrupted operations and loop evidence become recoverable and reproducible |
| M4 — Platform confidence | A3, C1, D1 | Full negative suites and three-OS validation |
| M5 — Quality/governance | D2, D3, E1, E2 | Maturity claims, preview semantics, and migrations become explicit |
| M6 — Strategic runtime | F1 | L1/L2 loop capability becomes enforceable or accurately scoped |

## Score-Uplift Forecast

| Stage | Expected score | Expected maturity |
|---|---:|---|
| Current official score | 59.0 | Developing |
| After M1–M2 | 69–73 | Stable |
| After M3–M4 | 78–82 | Production-ready |
| After M5–M6 | 84–88 | Production-ready |

The forecast assumes that every correction receives permanent positive and negative tests, all three OS families run equivalent gates, and migration behavior defaults to preservation.

## Release Verification Checklist

- [x] Every destination is canonically resolved and authorized immediately before mutation.
- [ ] Junction and symlink fixtures prove zero writes outside approved roots.
- [ ] Existing customized instructions, protocols, memory, and skills remain preserved.
- [ ] `ForceManaged` refreshes only exact, unchanged, layer-owned artifacts.
- [ ] Fault injection after each installer/update mutation is recoverable.
- [ ] Per-target locking prevents concurrent writers.
- [ ] Manifest diff verifies content, ownership, adapter identity, and every mirror.
- [ ] Undeclared adapter destination collisions fail before writes.
- [ ] Future-version targets and unapproved downgrades stop before writes.
- [ ] Worktree create, verify, and cleanup share one lifecycle contract.
- [ ] Verifier reports bind to revision, diff, commands, exits, and evidence hashes.
- [x] Preview commands leave target content and Git status unchanged by default.
- [ ] JSON instances pass real Draft 2020-12 schema validation.
- [ ] Behavioral maturity cannot be satisfied by keywords alone.
- [ ] Full validate, packs, drift, quality, smoke, matrix, and adversarial gates pass on Windows, Ubuntu, and macOS.
- [ ] Recovery, migration, and troubleshooting instructions pass a clean-machine onboarding test.

## Exact First Task

Implement and test a shared `Resolve-SafeTargetDestination` / `Assert-NoReparsePointEscape` module, route every installer, updater, loop, manifest, and report write through it, and add Windows junction plus Unix symlink fixtures proving that no write can leave the authorized target or report root.
