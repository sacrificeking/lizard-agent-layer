---
name: precision-domain
description: High-stakes calculation integrity, source fidelity, data provenance, financial/scientific precision, stale-data prevention, and auditability across Fintech, MedTech, and critical calculation domains. Use when implementing calculations, financial formulas, metrics pipelines, or domain-critical logic.
---

# Precision Domain

## Rules

- Distinguish strictly between unknown/null, zero, and safe default values.
- Retain complete data provenance, including source timestamps, data provider identifiers, and calculation formulas.
- Add rigorous assertions and unit tests for critical numeric calculations, rounding rules, and unit conversions.
- Prevent stale-data risks: verify timestamp freshness before processing time-sensitive data feeds.
- Guard against silent calculation failures: log structured evaluation diagnostics and abort fail-closed when calculation constraints are violated.
- Treat production release and high-stakes calculation adjustments as strictly human-gated.

## Verification

- Add focused unit tests covering precision limits, edge-case rounding, zero-division, and overflow handling.
- Verify numeric outputs against validated reference calculations and domain truth datasets.
- Run typecheck and assertion suites before finalizing calculation changes.

## Safety

- Do not perform silent truncation or uncontrolled rounding of financial/scientific values.
- Avoid lossy numeric data type conversions (e.g. float vs decimal/bigint).
- Abort calculation pipelines immediately on invariant violation rather than returning degraded estimations.
