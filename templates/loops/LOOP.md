# lizard-agent-layer Loops

This project uses lizard-agent-layer loop engineering in report-only mode by default.

## Operating Mode

- Default readiness: L1 report-only
- Default action: inspect, summarize, update loop state, append run log
- Default denial: no source edits, no dependency changes, no release actions, no migrations, no secrets
- Human gate: required before any apply, publish, migration, auth, security, finance, or ForceManaged action

## Installed Patterns

- daily-triage: daily project risk and stale-work report
- release-readiness: release decision packet before versioning or publishing
- layer-update-watch: compare this target against newer lizard-agent-layer releases

## Runtime Files

- loop-state.md: current loop memory and active findings
- loop-budget.md: token caps, model routing, and kill switch
- loop-run-log.md: append-only run history
- loop-constraints.md: denylist, allowlist, and human gates

## Model Routing

Use cheaper models for inventory, classification, state pruning, and summaries. Use stronger models for verifier roles, security/auth/finance risk, release verdicts, and profile or pack adaptation.

## Kill Switch

Pause all loops when any of these happens:

- token budget exceeds the configured daily cap
- the same item reaches max attempts
- a production incident or release freeze is active
- a loop touches denied paths or proposes unsafe scope
- human reviewers are unavailable for high-risk decisions
