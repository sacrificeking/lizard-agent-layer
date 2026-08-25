---
name: precision-domain
description: High-stakes calculation integrity, source fidelity, data provenance, financial/scientific precision, stale-data prevention, and auditability across Fintech, MedTech, and critical calculation domains.
---

# Precision Domain

## Rules

- Distinguish strictly between unknown/null, zero, and safe default values.
- Retain complete data provenance, including source timestamps, data provider identifiers, and calculation formulas.
- Add rigorous assertions and unit tests for critical numeric calculations, rounding rules, and unit conversions.
- Prevent stale-data risks: verify timestamp freshness before processing time-sensitive data feeds.
- Guard against silent calculation failures: log structured evaluation diagnostics and abort fail-closed when calculation constraints are violated.
- Treat production release and high-stakes calculation adjustments as strictly human-gated.
