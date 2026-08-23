# Changelog

All notable public changes to lizard-agent-layer are documented here.

## Unreleased

## 1.2.0 - 2026-08-23

### Added

- Versioned `skill.json` contracts for every skill, dependency/conflict and permission validation, a hash-bound installed skill manifest, strict Doctor checks, and a preview-first transactional install/update/migrate/disable/recover/remove lifecycle.
- SafeFs-backed deterministic target analysis with bounded reads, link/swap rejection, typed evidence strength, explicit harness approval, qualitative calibration risk, and host-native executable/argv output.
- Externally digest-pinned trust stores, short-lived challenges, RS256 evidence envelopes, revocation checks, and verifier replay protection.
- Authenticated implementer/verifier separation for worktree lifecycle and L2 completion; unsigned synthetic PASS evidence is rejected.
- Persisted route decisions, runtime execution receipts, and model calibration evaluations now require role-authorized signatures and exact decision/context hashes.
- Authorization-capable evidence schemas use signed envelope version 2; unsigned legacy evidence must be regenerated.
- Manifest schema v4 retains `active`, `retired-present`, `retired-missing`, and future `removed` lifecycle records across profile, pack, skill, and harness contraction. Retired content is plan-bound and preserved by default.
- A root-specific SafeFs capability contract plus checked-in Windows, Linux, and macOS native backends cover descriptor-relative protected reads, atomic create/replace, copy, nested-directory creation, and relative deletion without a name-based SafeFs fallback.
- A preview-first transactional uninstaller supports conservative `managed-only`, separately confirmed `complete`, and hash-verified `export-then-complete` scopes, preserves non-layer-owned content, retains residual ownership evidence after partial removal, and writes a machine-readable deletion receipt outside the target.
- Effective `curated`, `private-episodic`, and `off` memory modes now span install, update, upgrade, manifest, adapters, doctor, manifest diff, uninstall plans, and receipts. Exact-plan-bound transitions remove only unchanged layer-owned artifacts and fail closed on modified, unknown, linked, or replaced content.
- Records retention lifecycle, active cryptographic legal holds, export archives, and transactional purge with verifiable deletion receipts (`ADR-0023` and `scripts/records-lifecycle.ps1`).
- Visual Developer Quickstart Guide (`QUICKSTART.md`) with copy-paste prompts for GitHub Copilot, Cursor Composer, and Claude Code, plus one-line remote GitHub installation commands.
- Expanded focused safety test catalog to 43 comprehensive automated suites covering all integration, unit, and adversarial vectors.

### Fixed

- Generated analyzer and install-plan commands now use the active host abstraction instead of Windows-only `powershell.exe`; L2 branch/base inputs reject option confusion, invalid refs, and revision expressions before Git inspection.
- Security-sensitive JSON readers preserve schema-declared ISO-8601 strings across Windows PowerShell 5.1 and PowerShell 7.5+, preventing canonical plans, transaction journals, and loop evidence from being silently converted to `System.DateTime`.
- GitHub Actions jobs allow 120 minutes so the complete Windows PowerShell 5.1 gate set can finish and report its actual result.
- Installer manifests now include every layer-created intermediate and nested skill directory, so artifact-specific uninstall can restore an originally empty target without name-based recursive deletion.
- `memory_mode` is mandatory in schema-v4 manifests; `off` now has no physical memory namespace, memory policy, operational memory path references, or managed-memory permissions, while retaining only non-executable removed ownership tombstones.
- Update-plan binding fixtures use the string-preserving JSON reader on PowerShell 7 hosts.
- Internal macOS install plan probes canonicalize the standard `/var` temporary alias before unchanged SafeFs validation.
- The macOS temporary-root unit assertion now expects the same canonical host path returned by SafeFs.
- Long-running Ubuntu and macOS CI gates are partitioned into deterministic focused-test shards, standalone smoke jobs, and per-profile matrix jobs without reducing test coverage; default local CI remains complete and unsharded.
- Sharded CI quality evaluation now consumes the exact focused report produced by its job, while long macOS smoke, public-readiness, and high-risk adapter checks run in bounded independently reportable jobs.
- Public-readiness workflow checks recognize both LF and CRLF line endings while continuing to require lifecycle-script suppression for every locked dependency install.
- Update history and update reports now identify their post-apply manifest as schema v4 instead of retaining stale schema-v3 literals.
- Fixed single-element array unrolling in PowerShell report serialization (`Lizard.SafeReport.psm1`).
- Fixed `trust_binding_sha256` dictionary serialization in `record-execution.ps1` to ensure correct receipt hashing and signature validation.
- Corrected fail-closed execution order in `Lizard.LoopRuntime.psm1` ensuring non-PASS verifier verdicts immediately abort before trust stores are requested.
- Added console failure output in `loop-worktree.ps1` and `loop-worktree-cleanup.ps1` for transparent error reporting to non-JSON consumers.
- Fixed AJV strict object type validation in `schemas/safe-fs-capability.schema.json`.
- Updated `install.ps1` `Should-ReplacePath` to ensure layer-owned index and manifest files are deterministically refreshed during profile and pack reconfigurations.

### Security

- All adapters now gate managed target instructions on strict integrity verification and explicit authority precedence; target overlay prose is quarantined while its exact hash is plan- and manifest-bound. L2 verifier shell strings are replaced by short-lived, worktree/executable-bound, explicitly approved allowlist plans executed without a shell or inherited environment.
- Route and execution receipts now reject free-form signals and evidence prose, require typed privacy/retention metadata, constrain dynamic identities to opaque IDs, and pass file/console output through a shared deterministic canary-redaction serializer.
- Regulated data now fails to human review before signals, route selection, inventory loading, or model recommendation. Stable receipt reason codes and strict doctor policy checks prevent target policy, caller signals, attempts, and model lists from weakening the default; authenticated organization approval remains future work.
- Windows SafeFs atomic writes create and commit stage files relative to a held parent handle; a deterministic ancestor rename/Junction swap fixture proves that neither temporary nor final bytes escape the authorized root.
- Plans and transaction lock, journal, backup, rollback, and cleanup operations now use the same handle-bound SafeFs primitives and bind target identity to the physical root object.
- Unix SafeFs uses descriptor-relative `*at` operations and file/device/mount identity. Native Ubuntu/macOS release evidence is still pending and is not claimed by this entry.
- Built-in Git worktree creation/removal now fails closed where Git cannot consume SafeFs handles. Clean externally created worktrees can be registered for lifecycle verification without layer-owned Git mutation.
- Unix SafeFs validation now rejects nested same-device bind mounts and cross-device mount transitions, fails closed when mount identity is unavailable, and includes a dedicated privileged Ubuntu fixture.
- GitHub Actions installs locked validator dependencies with npm lifecycle scripts disabled.
- Install and update mutations now require immutable canonical operation plans, an independently supplied SHA-256, explicit human approval, pre-lock validation, and post-lock/pre-mutation revalidation. Applied plan identities are recorded in manifests and update history.
- Uninstall deletion binds kind, content hash, physical object identity, target-root identity, and source inputs. Windows deletes through the checked object handle; Unix quarantines the directory entry and verifies Device/Mount/Inode before unlinking.

### Breaking

- Direct `install.ps1 -Apply` and `update-target.ps1 -Apply` calls without `-ApprovedPlanPath`, `-ApprovedPlanSha256`, and `-HumanApproved` now fail closed. Existing targets require no data rewrite; regenerate legacy Markdown plans as canonical JSON.
- Schema-v4 install manifests require lifecycle-aware readers. Current tools migrate v3 records conservatively during the next approved apply.
- Unix target layouts containing nested mounts now fail closed instead of being treated as ordinary contained directories.
- PowerShell Core 7.4 and older now fail closed for security-sensitive JSON reads; PowerShell Core 7.5+ is required for explicit string-preserving date handling.
- L2 worktree create/remove apply no longer invokes Git. Users preview in the layer, perform reviewed Git creation/cleanup externally, and register the clean worktree with `-RegisterExisting -Apply -HumanApproved`.

## 1.1.0 - 2026-07-19

### Added

- Provider-neutral 10-80-10 staged execution that uses the active harness model without picker interruptions.
- Optional automatic inventory routing for arbitrary providers, gated by a target runtime contract, complete route coverage, and fingerprint-bound calibrated evidence.
- Separate route-decision and attested execution receipts, preview-first model calibration, secret blocking, escalation signals, fresh verification, protocols, schemas, and a reusable staged-execution skill.
- Deprecation warnings for legacy `modelProfiles`; built-in profiles remain provider-neutral and use `inherit-current`.
- Beginner-oriented daily-use guidance and routing output with explicit ready, pause, and blocked next actions; blocked work no longer appears to recommend an active model.

## 1.0.0 - 2026-07-12

Initial public release.

### Added

- Portable project profiles, model profiles, packs, protocols, skills, and adapters for Codex, Claude Code, Gemini, Cursor, GitHub Copilot, and generic `AGENTS.md` consumers.
- AI-guided installation and removal runbooks with explicit discovery, preview, approval, verification, and recovery stages.
- Preview-first installation, target analysis, manifest-backed ownership, transactional writes, update planning, merge suggestions, drift detection, diagnostics, and recovery tooling.
- L1 report-only and L2 assisted loop execution with budgets, leases, worktree isolation, verifier-bound completion, human-gated recovery, and no auto-merge.
- Executable Draft 2020-12 schemas, mutation tests, adapter matrix coverage, adversarial tests, quality scoring, behavioral-readiness evidence, and cross-platform CI.
- Enterprise usage, security, compatibility, dependency, troubleshooting, architecture decision, and getting-started documentation.

### Security

- Filesystem containment, symlink and reparse-point defenses, atomic writes, manifest integrity, hash-chained loop evidence, secret-handling guidance, and metadata-only report defaults.
- GitHub Actions use least-privilege permissions, immutable action commit pins, disabled checkout credential persistence, and disabled package-manager caching.
- No intentional telemetry, analytics, background upload, hosted control plane, or target-project runtime dependency.

### Compatibility

- PowerShell 7 is the primary runtime; Windows PowerShell 5.1 compatibility is continuously checked for supported workflows.
- Node.js 22 or newer is required only for executable schema validation; CI uses Node.js 24.18.0.
- The repository is MIT licensed. Organizational approval, AI-provider policy, data classification, and repository access controls remain deployment responsibilities.

### Boundaries

- L2 automation may prepare and verify work in an isolated worktree but never auto-merges.
- Installation, updates, force-managed replacement, recovery, and complete removal require reviewable plans and explicit human approval.
