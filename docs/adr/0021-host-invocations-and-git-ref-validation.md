# ADR 0021: Host-Native Invocations and Strict Git References

- Status: Accepted
- Date: 2026-08-22
- Extends: ADR 0008 and ADR 0020

## Context

Generated install-plan commands hard-coded `powershell.exe`, `-ExecutionPolicy Bypass`, and Windows path assumptions despite a supported PowerShell 7 matrix on Windows, Ubuntu, and macOS. L2 worktree inputs also reached Git with inconsistent validation. PowerShell passed each value as one process argument, so shell injection was not established, but option-like values and Git revision expressions could be interpreted differently from the intended branch/base contract.

## Decision

`Lizard.Host.psm1` owns PowerShell file invocations. A typed invocation contains a host ID, executable, argv, and display-only command. Windows host IDs receive the compatibility execution-policy arguments; Linux and macOS do not. Current-host commands resolve the running PowerShell executable, while synthetic host cases use `powershell.exe` only for Windows PowerShell 5.1 and `pwsh` everywhere else. Install plans and the analyzer consume this abstraction.

`Lizard.Git.psm1` owns caller-supplied branch and base-reference validation. Values that are empty, oversized, option-like, contain whitespace/control characters, or fail `git check-ref-format` are rejected before reports or mutation. Base references are intentionally limited to `HEAD`, full 40-hex object IDs, or valid ref names; revision expressions such as `HEAD~1` and `HEAD^` are not part of the contract. Resolution uses `rev-parse --verify --end-of-options` with commit peeling and requires one exact 40-hex result.

Signed lifecycle consumers revalidate branch syntax even when the branch originates in an authenticated envelope. This is defense in depth and prevents authenticated-but-malformed input from reaching later Git operations.

## Consequences

- Generated commands are valid for the host that generated them and expose executable/argv separately where machine consumption is supported.
- Display strings remain documentation, not a shell authorization contract.
- Previously accepted revision expressions and option-like branch/base strings now fail with stable `GIT_*` codes and require a fresh valid plan or lifecycle operation.
- Complete execution evidence remains pending on Windows PowerShell 7, Ubuntu, and macOS.
