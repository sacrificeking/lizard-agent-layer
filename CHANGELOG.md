# Changelog

All notable public changes to lizard-agent-layer are documented here.

## Unreleased

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
