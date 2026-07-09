# Loop State

Schema version: 1
Last run: never
Default readiness: L1 report-only

## High Priority

- None

## Watch List

- None

## Waiting On Human

- None

## Resolved Recently

- None

## State Rules

- Read this file at the start of every loop run.
- Prune stale resolved items each run.
- Record attempt counts before proposing another action.
- Escalate after three failed attempts on the same item.
- Do not store secrets, credentials, or private tokens here.
