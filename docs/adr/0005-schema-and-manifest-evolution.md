# ADR 0005: Schema And Manifest Evolution

- Status: Accepted
- Date: 2026-07-12

## Context

Published schemas and readers must evolve without making installed targets unreadable or accepting undocumented shapes.

## Decision

All repository JSON contracts use executable Draft 2020-12 schemas and pinned validation tooling. Writers emit one current schema version; readers declare a bounded compatibility range. Contract changes include a change declaration with migration disposition. Future schemas fail before writes. Conservative migrations preserve ambiguous target content.

## Consequences

Schema changes require valid current instances, negative mutations, compatibility notes, and migration metadata even when the disposition is backward-compatible.
