# Changelog

All notable public changes to lizard-agent-layer are documented here.

## Unreleased

### Added

- Manifest schema v4 retains `active`, `retired-present`, `retired-missing`, and future `removed` lifecycle records across profile, pack, skill, and harness contraction. Retired content is plan-bound and preserved by default.

### Fixed

- Security-sensitive JSON readers preserve schema-declared ISO-8601 strings across Windows PowerShell 5.1 and PowerShell 7.5+, preventing canonical plans, transaction journals, and loop evidence from being silently converted to `System.DateTime`.
- GitHub Actions jobs allow 120 minutes so the complete Windows PowerShell 5.1 gate set can finish and report its actual result.

### Security

- Unix SafeFs validation now rejects nested same-device bind mounts and cross-device mount transitions, fails closed when mount identity is unavailable, and includes a dedicated privileged Ubuntu fixture.
- Install and update mutations now require immutable canonical operation plans, an independently supplied SHA-256, explicit human approval, pre-lock validation, and post-lock/pre-mutation revalidation. Applied plan identities are recorded in manifests and update history.

### Breaking

- Direct `install.ps1 -Apply` and `update-target.ps1 -Apply` calls without `-ApprovedPlanPath`, `-ApprovedPlanSha256`, and `-HumanApproved` now fail closed. Existing targets require no data rewrite; regenerate legacy Markdown plans as canonical JSON.
- Schema-v4 install manifests require lifecycle-aware readers. Current tools migrate v3 records conservatively during the next approved apply.
- Unix target layouts containing nested mounts now fail closed instead of being treated as ordinary contained directories.
- PowerShell Core 7.4 and older now fail closed for security-sensitive JSON reads; PowerShell Core 7.5+ is required for explicit string-preserving date handling.

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
