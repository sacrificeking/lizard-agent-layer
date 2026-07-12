# ADR 0004: Adapter Composition And Precedence

- Status: Accepted
- Date: 2026-07-12

## Context

Multiple harnesses can target the same instruction path, making order-dependent installation unsafe.

## Decision

Adapter manifests declare compatibility and precedence. Composition is deterministic and order-independent. Undeclared destination collisions or ancestor overlaps fail preflight before any target mutation. Alias satisfaction is recorded in the manifest and verified by exact content identity.

## Consequences

Adding an adapter that shares a destination requires an explicit compatibility relationship or a distinct sidecar destination.
