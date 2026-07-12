# ADR 0007: Report Boundaries And Privacy

- Status: Accepted
- Date: 2026-07-12

## Context

Secondary reports may be shared separately and must not duplicate private target instructions by default.

## Decision

Reports are written outside targets by default, use explicit schemas where durable, and minimize copied target content. Merge suggestions bind existing instructions by SHA-256 and emit metadata-only zero-context patches. Complete existing context requires `-IncludeExistingContext` and a `contains-target-context` sensitivity label.

## Consequences

Default reports are safer to review and share. Context-inclusive patch files must be treated as sensitive project material.
