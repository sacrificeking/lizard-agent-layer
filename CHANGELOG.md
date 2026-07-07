# Changelog

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
