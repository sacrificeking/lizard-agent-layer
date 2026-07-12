# ADR 0003: Ownership And Manifest Identity

- Status: Accepted
- Date: 2026-07-12

## Context

Path lists alone cannot distinguish unchanged layer output from user-owned or locally modified files.

## Decision

Manifest schema v3 records per-artifact ownership, source path/version/hash, installed/current hash, adapter identity, aliases, and mirror group. `ForceManaged` may replace only an unchanged layer-owned artifact with proven provenance. Ambiguous legacy entries migrate as user-owned.

## Consequences

Updates preserve customization by default. Integrity-unknown or modified artifacts become explicit conflicts rather than silent replacements.
