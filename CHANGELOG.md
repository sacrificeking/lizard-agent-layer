# Changelog

All notable public changes to `lizard-agent-layer` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.4.1 - 2026-08-27

### Added
- **Centralized High-Risk Operation Approval Policy:** Introduced `Get-LizardOperationApprovalPolicy` in `scripts/Lizard.Plan.psm1` enforcing mandatory cryptographic signed approval (`PLAN_SIGNED_APPROVAL_REQUIRED`) for high-risk operations (including enterprise profiles, complete uninstall scopes, and force mutations).
- **Mandatory Replay Protection For Signed Mutations:** Required single-use replay ledgers (`PLAN_REPLAY_LEDGER_REQUIRED`) for all signed operation approvals, preventing token reuse and concurrent replay attacks.
- **Explicit Post-State Transaction Rollback Binding:** Added `post_state` objects (`schemas/transaction-journal.schema.json`) to all transaction mutations. Rollback operations now verify that deleted files have not been recreated externally and that directories have not been replaced before restoring original state (`TRANSACTION_ROLLBACK_DESTINATION_DIVERGED`).
- **macOS SafeFS Permission Normalization & Path Alias Resolution:** Added explicit POSIX permission normalization (`0644`) during atomic file replacement and canonicalized `/var`, `/tmp`, and `/etc` paths to prevent descriptor traversal rejection on macOS root symlinks.
- **Deep Repository Verification Drift Engine:** Created `scripts/check-repository-drift.ps1` to detect discrepancies between profiles, harnesses, schemas, CI matrix configurations, policies, and documentation.
- **Automated Release Readiness Evidence:** Created `scripts/release-readiness.ps1` providing machine-readable verification reports and blocker analysis prior to release promotion.
- **Automated Release Pipeline with Exact-SHA Provenance:** Added `.github/workflows/release.yml` with exact commit SHA verification, mandatory green CI validation, and SHA256 checksum artifact generation.
- **Comprehensive Release Regression Suites:** Added integration tests in `tests/release/` and `tests/adversarial/` verifying approval policies, post-state rollback safety, macOS permissions, and repository drift invariants.

### Changed
- **CI Matrix Consistency:** Synchronized CI workflow definitions with the canonical profile registry, replacing deprecated profile identifiers with `enterprise-fullstack`.
- **Analyzer Smoke Contract Hardening:** Calibrated precision signal thresholding and directory structure requirements in `scripts/analyze-target.ps1` and `tests/smoke.ps1`.
- **Universal Test Suite Canonical JSON Migration:** Migrated all 30 test scripts and test helpers across `tests/` to use `ConvertFrom-LizardJson` and added static policy linting in `scripts/check-json-reader-policy.ps1`.
- **Release Protocol & Skill Governance:** Updated `protocols/release-gates.md` and `skills/release/SKILL.md` with explicit exact-commit SHA green CI invariants.

## 1.4.0 - 2026-08-26

### Added
- **Signed Apply Approval For High-Risk Mutations:** Added opt-in `-RequireSignedApproval` to `install.ps1`, `update-target.ps1`, and `uninstall.ps1` requiring cryptographic RS256 authorization envelopes (`schemas/operation-plan-approval.schema.json`) verified against external trust stores via `Assert-LizardPlanApprovalSignature`.
- **Target-Root Approval Isolation & Replay Protection:** Rejects approval envelopes stored within the target repository (`PLAN_APPROVAL_ENVELOPE_IN_TARGET`) to prevent AI shell self-approval, and enforces single-use challenge tracking via `Use-LizardReplayLedger` (`TRUST_REPLAY_DETECTED`).
- **Identity-Bound Transaction Rollback & Anti-Clobber Protection:** Recorded `post_hash` on all mutation journal entries (`schemas/transaction-journal.schema.json`). Rollback and recovery operations verify that live destination files match the recorded post-mutation hash and fail closed with `TRANSACTION_ROLLBACK_DESTINATION_DIVERGED` if files were modified externally.
- **Multi-Host CI Evidence Alignment:** Mapped exact host verification gates (`powershell-7-windows`, `powershell-7-unix-base`, `powershell-7-unix-focused-shards`, `powershell-7-unix-smoke`, `powershell-7-unix-profiles`) across Windows, Ubuntu, and macOS in `docs/compatibility.md`.
- **Adversarial & Unit Test Coverage:** Added dedicated test suite `tests/adversarial/signed-apply-approval.tests.ps1` and unit test cases for rollback divergence in `tests/unit/transaction-primitives.tests.ps1`.

### Changed
- **Universal Canonical JSON Migration:** Replaced all raw `ConvertFrom-Json` calls across all 22 layer scripts and helper modules with `ConvertFrom-LizardJson` and `Lizard.SafeFs.psm1` to eliminate date-type and numeric coercion divergences.
- **Uninstall Integer Check Hardening:** Schema-v4 uninstall validation in `scripts/uninstall.ps1` now validates integer values numerically without requiring PowerShell-specific `[int]` runtime subtyping.
- **Zero High-Advisory Toolchain Baseline:** Updated `fast-uri` to `3.1.6` in `package-lock.json` and `docs/dependencies.md`, resolving all open npm advisories.
- **Repository-Wide Cleanup:** Removed temporary implementation drafts, consolidated architectural references in `docs/architecture.md`, and synchronized drift baseline.

## 1.3.0 - 2026-08-25

### Added
- **Generic & Runtime-Adaptive Enterprise Architecture:** Replaced rigid technology-specific packs with universal domain packs (`database-backend`, `frontend-engineering`, `backend-api`, `precision-domain`), universal skills, and the `enterprise-fullstack` profile dynamically adapting to Oracle, PostgreSQL, MSSQL, MySQL, MongoDB, React, Vue, Angular, Spring Boot, NestJS, FastAPI, and Go.
- **Fail-Closed Definition of Done Gate in Autonomous Loops (`scripts/loop-verify.ps1`):** Requires evaluated criteria packets (`-CriteriaPath`) on PASS/WARN verdicts, sealed into `schemas/verifier-evidence.schema.json`. Missing patterns (`DOD_PATTERN_REQUIRED`), uncataloged patterns (`DOD_PATTERN_NOT_FOUND`), or empty DoD criteria arrays (`DOD_DEFINITION_EMPTY`) fail closed.
- **Criteria Path Quarantine (`scripts/loop-verify.ps1`):** Enforced `Assert-PathOutsideRoot` for `-CriteriaPath` to reject criteria packets placed inside the target repository or worktree roots (`SAFEFS_FORBIDDEN_ROOT`).
- **Autonomous Loop DoD Patterns:** Integrated concrete `definitionOfDone` items in `minimal-fix-assist.json`, `daily-triage.json`, `layer-update-watch.json`, and `release-readiness.json`.
- **Plan Premortem Skill (`skills/premortem/`):** Systematic, path-grounded failure autopsy before execution with checkout-bound mitigations.
- **Project Decision Harvest Skill (`skills/project-decision-harvest/`):** Grounded decision elicitation that proposes 3–5 path-cited rules into `templates/memory/semantic/DECISIONS.md`.
- **Repo-Grounded Change Skill (`skills/repo-grounded-change/`):** Grounded code modifications citing sibling implementations and presenting 3 dynamic diff-specific review questions.
- **Target-Owned Local Skills Support:** Enabled `.agent/skills-local/` across `doctor.ps1` and all 6 IDE adapters for custom target-local skills without layer contamination.
- **Human Operator Card (`.agent/USING.md`):** Standardized human operator guide installed in target repositories, triggered on-demand (ask-only).
- **Prompt Calorie Budget Gate (`tests/unit/overlay-calorie-budget.tests.ps1`):** Automated test suite strictly enforcing $\le 80$ lines total composed always-on context across all IDE adapters.
- **Documentation Single-Harness Guardrails:** Enforced allowlist regex assertions across all public documentation files prohibiting accidental multi-harness copy-paste snippets.
- **Parallel Sharded Test Runner (`tests/run-sharded.ps1`):** Multi-core parallel execution engine running focused safety test suites concurrently across configurable shards.

### Changed
- **Contract-Shaped IDE Adapters:** Refactored all 6 IDE adapters (`codex`, `claude-code`, `cursor`, `github-copilot`, `gemini`, `generic-agents-md`) to concise, contract-shaped standing instructions with ask-only `USING.md` triggers and a 2-matching-skill cap.
- **Session-Level Paste Stop:** Tightened `protocols/permissions.md` and `protocols/secret-handling.md` to require an immediate session-level task stop on untrusted chat-pastes with categorized repro requests (`credential`, `customer-or-account`, `production-dump`, `unsure-treat-as-dump`).
- **Streamlined Enterprise Profile:** Refactored `profiles/enterprise-fullstack.json` default skills to the clean 6-skill core with specialized domains added via opt-in `-Packs`.
- **Conditional Protocol Installation:** Updated `scripts/install.ps1` to copy `release-gates.md` only when the `release` skill is installed, and `handoff.md` only for multi-harness setups.
- **Documentation Standardization:** Standardized all public documentation install, apply, and update snippets to single-harness defaults (`github-copilot`), removed markdown splice in Quickstart, and added enterprise backend ecosystem signals.
- **Archival Boundaries:** Documented intentional non-goals in `docs/architecture.md` and pointed enterprise residual risks at that section.

## 1.2.0 - 2026-08-23

### Added
- **Versioned Skill Contracts:** Versioned `skill.json` contracts for every skill, dependency/conflict and permission validation, a hash-bound installed skill manifest, strict Doctor checks, and a preview-first transactional install/update/migrate/disable/recover/remove lifecycle.
- **Deterministic SafeFs Target Analysis:** SafeFs-backed target analysis with bounded reads, link/swap rejection, typed evidence strength, explicit harness approval, qualitative calibration risk, and host-native executable/argv output.
- **Authenticated Evidence & Trust Framework:** Externally digest-pinned trust stores, short-lived challenges, RS256 evidence envelopes, revocation checks, and verifier replay protection.
- **Authenticated Implementer/Verifier Separation:** Enforced distinct cryptographic identity for worktree lifecycle and L2 loop completion; unsigned synthetic PASS evidence is rejected.
- **Cryptographic Routing & Calibration Receipts:** Persisted route decisions, runtime execution receipts, and model calibration evaluations now require role-authorized signatures and exact decision/context hashes.
- **Lifecycle-Aware Manifest Schema v4:** Retains `active`, `retired-present`, `retired-missing`, and future `removed` lifecycle records across profile, pack, skill, and harness contraction. Retired content is plan-bound and preserved by default.
- **Native Handle-Bound Filesystem Access:** Root-specific SafeFs capability contract plus checked-in Windows, Linux, and macOS native backends covering descriptor-relative protected reads, atomic create/replace, copy, nested-directory creation, and relative deletion without a name-based SafeFs fallback.
- **Transactional Multi-Scope Uninstaller:** Preview-first transactional uninstaller supporting conservative `managed-only`, separately confirmed `complete`, and hash-verified `export-then-complete` scopes, preserving non-layer-owned content, retaining residual ownership evidence after partial removal, and writing a machine-readable deletion receipt outside the target.
- **Effective Memory Modes:** Implemented `curated`, `private-episodic`, and `off` memory modes spanning install, update, upgrade, manifest, adapters, doctor, manifest diff, uninstall plans, and receipts. Exact-plan-bound transitions remove only unchanged layer-owned artifacts and fail closed on modified, unknown, linked, or replaced content.
- **Records Retention & Legal Hold:** Records retention lifecycle, active cryptographic legal holds, export archives, and transactional purge with verifiable deletion receipts in `scripts/records-lifecycle.ps1`.
- **Developer Quickstart Guide (`QUICKSTART.md`):** Visual guide with copy-paste prompts for GitHub Copilot, Cursor Composer, and Claude Code, plus remote installation commands.
- **Automated Test Catalog:** Expanded focused safety test catalog to 43 comprehensive automated suites covering integration, unit, and adversarial vectors.

### Fixed
- **Host Abstraction & Ref Validation:** Generated analyzer and install-plan commands use the active host abstraction; L2 branch/base inputs reject option confusion, invalid refs, and revision expressions before Git inspection.
- **JSON Date Portability:** Security-sensitive JSON readers preserve schema-declared ISO-8601 strings across Windows PowerShell 5.1 and PowerShell 7.5+, preventing canonical plans, transaction journals, and loop evidence from being silently converted to `System.DateTime`.
- **CI Execution Ceilings:** Configured GitHub Actions job ceilings to 120 minutes so complete Windows PowerShell 5.1 gates finish deterministically.
- **Artifact-Specific Uninstall Manifests:** Installer manifests now include every layer-created intermediate and nested skill directory, allowing artifact-specific uninstall to restore an originally empty target without recursive deletion.
- **Memory Mode Enforcement:** `memory_mode` is mandatory in schema-v4 manifests; `off` mode creates no physical memory namespace, memory policy, operational memory path references, or managed-memory permissions.
- **macOS Canonical Temporary Roots:** Internal macOS install plan probes canonicalize the standard `/var` temporary alias before SafeFs validation.
- **Sharded CI Quality Reporting:** Sharded CI quality evaluation consumes the exact focused report produced by its job, while long macOS smoke, public-readiness, and high-risk adapter checks run in bounded independently reportable jobs.
- **Line Ending Portability:** Public-readiness workflow checks recognize both LF and CRLF line endings while continuing to require lifecycle-script suppression for locked dependency installs.
- **Update History Manifest Schema:** Update history and update reports identify post-apply manifests as schema v4 instead of retaining stale schema-v3 literals.
- **PowerShell Array Serialization:** Fixed single-element array unrolling in PowerShell report serialization (`Lizard.SafeReport.psm1`).
- **Trust Binding Digest Serialization:** Fixed `trust_binding_sha256` dictionary serialization in `record-execution.ps1` to ensure correct receipt hashing and signature validation.
- **Fail-Closed Loop Verification:** Corrected execution order in `Lizard.LoopRuntime.psm1` ensuring non-PASS verifier verdicts immediately abort before trust stores are requested.
- **AJV Strict Object Validation:** Fixed AJV strict object type validation in `schemas/safe-fs-capability.schema.json`.
- **Deterministic Manifest Refresh:** Updated `install.ps1` `Should-ReplacePath` to ensure layer-owned index and manifest files are deterministically refreshed during profile and pack reconfigurations.

### Security
- **Strict Instruction Integrity & Authority Precedence:** All adapters gate managed target instructions on strict integrity verification and explicit authority precedence; target overlay prose is quarantined while its exact hash is plan- and manifest-bound.
- **Canary Redaction & Bounded Receipts:** Route and execution receipts reject free-form signals and evidence prose, require typed privacy/retention metadata, constrain dynamic identities to opaque IDs, and pass output through a shared canary-redaction serializer.
- **Regulated Data Default Review:** Regulated data fails closed to human review before signals, route selection, inventory loading, or model recommendation.
- **Handle-Bound Race Resistance:** Windows SafeFs atomic writes create and commit stage files relative to a held parent handle, verified via ancestor rename/junction swap fixtures proving no escape from the authorized root.
- **Physical Root Identity Binding:** Plans and transaction lock, journal, backup, rollback, and cleanup operations use handle-bound SafeFs primitives and bind target identity to the physical root object.
- **Unix Mount Boundary Containment:** Unix SafeFs validation rejects nested same-device bind mounts and cross-device mount transitions, failing closed when mount identity is unavailable.
- **Supply Chain Hardening:** GitHub Actions installs locked validator dependencies with npm lifecycle scripts disabled (`--ignore-scripts`).
- **Canonical Operation Plans:** Install and update mutations require immutable canonical operation plans, an independently supplied SHA-256, explicit human approval, pre-lock validation, and post-lock/pre-mutation revalidation.
- **Object-Level Uninstall Deletion:** Uninstall deletion binds kind, content hash, physical object identity, target-root identity, and source inputs without name-based recursive deletion.

### Breaking
- **Mandatory Plan Approval Flags:** Direct `install.ps1 -Apply` and `update-target.ps1 -Apply` calls without `-ApprovedPlanPath`, `-ApprovedPlanSha256`, and `-HumanApproved` fail closed.
- **Schema-v4 Manifest Requirement:** Schema-v4 install manifests require lifecycle-aware readers; legacy v3 records are migrated conservatively during approved apply.
- **Nested Mount Rejection:** Unix target layouts containing nested mounts fail closed instead of being treated as ordinary contained directories.
- **PowerShell Core 7.5+ Baseline:** PowerShell Core 7.4 and older fail closed for security-sensitive JSON reads; PowerShell Core 7.5+ is required for string-preserving date handling.
- **External Worktree Isolation:** L2 worktree create/remove apply no longer invokes Git directly; worktrees are prepared externally and registered via `-RegisterExisting -Apply -HumanApproved`.

## 1.1.0 - 2026-07-19

### Added
- **Provider-Neutral Staged Execution:** 10-80-10 staged execution that uses the active harness model without model picker interruptions.
- **Calibrated Inventory Routing:** Optional automatic inventory routing for arbitrary providers, gated by a target runtime contract, complete route coverage, and fingerprint-bound calibrated evidence.
- **Attested Execution Receipts:** Separate route-decision and attested execution receipts, preview-first model calibration, secret blocking, escalation signals, fresh verification, protocols, schemas, and a reusable staged-execution skill.
- **Operator Daily Guidance:** Beginner-oriented daily-use guidance and routing output with explicit ready, pause, and blocked next actions.

### Changed
- **Provider-Neutral Profile Defaults:** Deprecated concrete `modelProfiles` in favor of provider-neutral `inherit-current` defaults across all built-in profiles.

## 1.0.0 - 2026-07-12

### Added
- **Core Agent Infrastructure:** Portable project profiles, model profiles, packs, protocols, skills, and adapters for Codex, Claude Code, Gemini, Cursor, GitHub Copilot, and generic `AGENTS.md` consumers.
- **AI-Guided Runbooks:** Interactive installation and removal runbooks with explicit discovery, preview, approval, verification, and recovery stages.
- **Lifecycle Tooling:** Preview-first installation, target analysis, manifest-backed ownership, transactional writes, update planning, merge suggestions, drift detection, diagnostics, and recovery tooling.
- **Bounded Autonomous Loops:** L1 report-only and L2 assisted loop execution with budgets, leases, worktree isolation, verifier-bound completion, human-gated recovery, and no auto-merge.
- **Executable Validation Suite:** Draft 2020-12 schemas, mutation tests, adapter matrix coverage, adversarial tests, quality scoring, behavioral-readiness evidence, and cross-platform CI.
- **Comprehensive Documentation:** Enterprise usage, security, compatibility, dependency, troubleshooting, architecture decisions, and getting-started documentation.

### Security
- **Containment & Integrity Foundation:** Filesystem containment, symlink and reparse-point defenses, atomic writes, manifest integrity, hash-chained loop evidence, secret-handling guidance, and metadata-only report defaults.
- **Hardened CI Workflows:** GitHub Actions configured with least-privilege permissions, immutable action commit pins, disabled checkout credential persistence, and disabled package-manager caching.
- **Zero Telemetry & Runtime Independence:** No intentional telemetry, analytics, background uploads, hosted control planes, or target-project runtime dependencies.

### Compatibility
- **Cross-Platform Host Support:** PowerShell 7 as the primary portable runtime with continuous Windows PowerShell 5.1 backward compatibility.
- **Locked Toolchain Baseline:** Node.js 22+ required only for executable schema validation; CI pinned to Node.js 24 LTS.
- **Open Source Licensing:** MIT license with full commercial and private permissions.


