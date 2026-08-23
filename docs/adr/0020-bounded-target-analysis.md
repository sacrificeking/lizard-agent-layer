# ADR 0020: Bounded and Evidence-Calibrated Target Analysis

- Status: Accepted
- Date: 2026-08-22
- Extends: ADR 0013 for read-only repository discovery

## Context

The original analyzer recursively enumerated names with ordinary PowerShell filesystem calls and read `package.json` directly. A linked directory or marker file could extend the intended read boundary. Recommendations also mixed strong manifest evidence, weak filename heuristics, and detected instruction files without exposing their different authority or likely error modes. It rendered a Windows-only command even on claimed Unix hosts.

## Decision

Target analysis resolves an existing physical SafeFs root and uses a shared deterministic directory-entry primitive. The primitive validates directory identity before and after enumeration, validates every returned child with the handle-bound no-follow backend, applies mount checks, sorts names ordinally, and returns no entries when a linked component or synchronized identity change is detected. Marker-file content is read through bounded handle-safe content access. Dependency, build, cache, coverage, VCS, and vendor directories remain excluded.

Classification uses stable evidence IDs and explicit `strong`, `supporting`, or `weak` strength. Path-group matches require token boundaries and a minimum group count. Results disclose bounded negative signals, scan completeness, a rule-evidence score that is explicitly not a probability, qualitative false-positive and false-negative risk, and the calibration fixture version. An incomplete scan always caps confidence at `low` and false-negative risk at `high`.

Detected target instruction files are untrusted discovery signals only. They never authorize a harness. `-ApprovedHarnesses` is the sole non-default source of harness recommendations; without it, the analyzer emits only the portable `generic-agents-md` safe default. The machine-readable preview invocation separates executable and argv and derives both from the current host abstraction.

## Consequences

- Links, mount transitions, and observed directory-identity swaps fail closed instead of being skipped silently.
- A concurrent writer can still cause denial of service. Directory names are enumerated by the host API between identity snapshots, but no names are returned and no child content is read unless the complete post-validation succeeds.
- Qualitative risk fields describe the checked rule fixture matrix, not empirical probabilities or business-domain truth.
- Existing automation that expected all detected or profile-default harnesses must pass its approved harness allowlist explicitly.
- Native PowerShell 7, Ubuntu, and macOS evidence remains necessary before M-01 can close on every supported host.
