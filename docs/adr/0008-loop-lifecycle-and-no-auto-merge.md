# ADR 0008: Loop Lifecycle And No Auto-Merge

- Status: Accepted
- Date: 2026-07-12

## Context

Assisted loops need isolation and evidence without allowing an agent to silently approve and merge its own work.

## Decision

L1 remains report-only. L2 uses an isolated sibling worktree, one hashed lifecycle envelope, distinct implementer/verifier identities, executable verification evidence, and lifecycle-bound cleanup. An explicitly invoked runtime owns atomic state transitions, one active lease, run and item identities, budget accounting, a hash-chained event log, and human-approved stale-lease recovery. L2 completion additionally requires PASS evidence bound to the same lifecycle operation and target. Auto-merge is always false; a human chooses merge, revise, discard, or pause.

## Consequences

Detached, stale, self-verified, command-failing, unbound, duplicate, over-budget, or tampered states fail closed. The runtime is scheduler-independent and does not execute model calls, merge, push, release, or deploy. Existing loop installations gain the additive runtime files through a reviewed `loop-sync.ps1 -Apply` migration; authoritative state and events are never force-overwritten.
