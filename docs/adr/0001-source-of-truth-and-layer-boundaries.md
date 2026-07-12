# ADR 0001: Source Of Truth And Layer Boundaries

- Status: Accepted
- Date: 2026-07-12

## Context

Reusable agent behavior must evolve independently from repository-specific decisions and from any one model harness.

## Decision

`lizard-agent-layer` is the source of truth for generic profiles, packs, protocols, skills, schemas, and adapters. A target installation is a versioned adaptation recorded by its manifest. Project memory, permissions, decisions, and local instruction authority remain owned by the target. Harness adapters translate the generic core but do not fork its semantics.

## Consequences

Generic improvements are updated here and adapted through plan-first install/update workflows. Target-local knowledge is never promoted automatically into this repository. Model-specific affordances may differ, but safety and ownership contracts remain model-agnostic.
