# ADR 0008: Loop Lifecycle And No Auto-Merge

- Status: Accepted
- Date: 2026-07-12

## Context

Assisted loops need isolation and evidence without allowing an agent to silently approve and merge its own work.

## Decision

L1 remains report-only. L2 uses an isolated sibling worktree, one hashed lifecycle envelope, distinct implementer/verifier identities, executable verification evidence, and lifecycle-bound cleanup. Auto-merge is always false; a human chooses merge, revise, discard, or pause.

## Consequences

Detached, stale, self-verified, command-failing, unbound, or tampered states fail closed. Loop runtime enforcement beyond this lifecycle is a separate state-machine contract.
