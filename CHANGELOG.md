# Changelog

## 1.2.0 - 2026-07-08

### Added

- `update-target.ps1` as the plan-first workflow for installed target projects, including version comparison, manifest diff preview, conservative apply mode, and optional safe `-ForceManaged` refresh.
- Target update reports under `.tmp/updates/` with `update-plan.md`, `update-report.json`, and pre/post manifest diff artifacts.
- Applied update history in `.agent/lizard-agent-layer.update-history.jsonl` for future audits and repeatable integration upgrades.
- Installer `-ForceManaged` support that refreshes layer-generated artifacts without overwriting unowned root instruction files.
- Smoke coverage for update preview, update apply, requested pack preservation, update history, and strict post-update manifest diff.
- Update target documentation and quick-start integration.

## 1.1.0 - 2026-07-08

### Added

- Target pack overlays under `.lizard-agent-layer/packs/` with `extends` support for built-in packs.
- `manifest-diff.ps1` for comparing installed target manifests against the current layer, requested packs, expanded packs, expected skills, risk posture, and missing managed paths.
- Pack-specific smoke coverage for built-in pack installs, target overlay packs, manifest diff strict checks, and pack-preserving upgrades.
- Analyzer detection for monorepos, Python, Rust, Go, Java, .NET, CI/security markers, and path-based agent runtime signals.
- Manifest metadata for `requested_packs` and `pack_sources`.

### Changed

- `upgrade.ps1` now preserves requested packs from install manifests and project profiles.
- Install plans now distinguish requested packs from expanded packs.
- Pack schema, validation, and reports now understand `extends`.

## 1.0.0 - 2026-07-08

### Added

- Bundle and pack system with curated manifests for frontend, Supabase React, finance, agent runtime, design system, and security hardening project shapes.
- `pack-report.ps1` with strict pack integrity checks and Markdown/JSON reports.
- Installer `-Packs` support that merges pack skills, stack, verification, harnesses, risk, size, model profiles, notes, and install manifest metadata into the selected profile.
- Target analyzer pack recommendations through `recommendedPacks` and generated preview commands with `-Packs`.
- Pack schema, pack documentation, CI pack gate, and drift tracking for packs and schemas.
- Reusable `agent-runtime` and `security-hardening` skills.

### Changed

- CI now runs the pack gate by default and supports `-SkipPacks` for diagnosis.
- Drift intelligence now tracks pack manifests and schemas.

## 0.9.0 - 2026-07-08

### Added

- Drift intelligence for adapters, skills, protocols, profiles, model profiles, and registry rules.
- `drift-check.ps1` with baseline update, strict comparison, token estimates, and Markdown/JSON reports.
- Committed `registry/drift-baseline.json` for intentional behavior tracking.
- Drift gate integrated into local CI with `-SkipDrift` for diagnosis.
- Drift intelligence documentation and README integration.

## 0.8.0 - 2026-07-08

### Added

- Skill maturity registry with baseline, ready, hardened, and certified levels.
- Maturity reporting in `score-layer.ps1` and generated quality reports.
- Complete skill-package installation for references, examples, scripts, and tests.
- Certified `research-audit` example package with reference material and scenario test.
- Skill maturity documentation and authoring guidance.

## 0.7.0 - 2026-07-08

### Added

- Quality registry with rubric and configurable risk signals.
- `score-layer.ps1` for skill, adapter, and profile scoring.
- JSON and Markdown quality reports under `.tmp/quality/`.
- Strict quality gate integrated into local CI.
- Quality registry documentation and skill-authoring guidance.

## 0.6.0 - 2026-07-07

### Added

- Local `scripts/ci.ps1` gate runner for validate, smoke, matrix, and optional strict git status checks.
- GitHub Actions workflow for repository CI on pull requests, pushes, and manual dispatches.
- CI documentation and quick-start integration.

## 0.5.0 - 2026-07-07

### Added

- Standalone `merge-suggestions.ps1` generator for existing instruction files.
- Markdown, JSON, patch, and copy-block artifacts for manual harness instruction merges.
- Smoke coverage proving merge suggestions do not write into target projects.
- Merge suggestion documentation and quick-start integration.

## 0.4.0 - 2026-07-07

### Added

- Optional install plan reports through `install.ps1 -WritePlan` and `-PlanPath`.
- Structured merge suggestions when existing instruction files require sidecar review.
- Merge suggestions persisted into the install manifest on apply.
- Install plan documentation and smoke coverage for read-only preview plan behavior.

### Changed

- Installer output now reports merge suggestion counts when sidecars are needed.
- Getting-started flow now includes a reviewable plan step before preview/apply.

## 0.3.0 - 2026-07-07

### Added

- Target analyzer for profile, harness, skill, signal, and risk recommendations.
- Adapter matrix script that verifies selected profile/harness combinations through install plus strict doctor checks.
- Documentation for target analysis and matrix testing.
- Smoke coverage for analyzer recommendations.

### Changed

- Validation now parses the analyzer and matrix scripts.
- Getting-started flow now starts with a read-only target analysis.

## 0.2.0 - 2026-07-07

### Added

- Multi-harness adapter architecture for Codex, Claude Code, Gemini, Cursor, and generic AGENTS.md tools.
- Adapter and model-profile schemas.
- Model profiles for GPT-5 Codex, Claude Sonnet, Gemini Pro, and local small models.
- Handoff protocol for cross-model development.
- Harness override support in installer and upgrade workflows.
- Doctor and smoke coverage for multi-harness targets.

## 0.1.0 - 2026-07-07

### Added

- Initial `lizard-agent-layer` repository.
- Minimal, standard, and Supabase React finance profiles.
- Codex adapter and reusable skill set.
- Preview-first installer for target projects.
- Curated memory templates and core safety protocols.
- Validation, doctor, and smoke-test scripts.
