---
name: database-engineering
description: Database architecture, safe migrations, transactional DDL, query optimization, indexing, connection hygiene, and schema consistency across Oracle, PostgreSQL, MySQL, MSSQL, SQLite, and MongoDB. Use when creating migrations, updating database schemas, optimizing queries, or refactoring data access layers.
---

# Database Engineering

## Rules

- Never execute or generate destructive DDL operations (`DROP TABLE`, unversioned column drops) without an explicit migration script and a tested rollback path.
- Enforce transactional boundaries (`BEGIN ... COMMIT / ROLLBACK`) for all schema and data migrations.
- Maintain zero-trust secret hygiene: never hardcode database credentials, passwords, or connection strings in application source or log outputs.
- Guard against N+1 queries and full table scans: inspect query explain plans and ensure foreign keys and query predicates are properly indexed.
- Ensure strict type synchronization between database schemas, ORM entities (e.g. Hibernate, JPA, Prisma, TypeORM), and API DTOs.
- Treat production database mutations as strictly human-gated.

## Verification

- Add focused migration tests validating forward application and rollback idempotency.
- Verify schema migrations against local and test databases before submitting PRs.
- Inspect explain plans and validate query latency benchmarks on indexed queries.

## Safety

- Avoid non-reversible schema alterations in production environments without explicit human approval.
- Preserve all existing records and avoid lossy column conversions during data migrations.
- Do not log raw database connection strings, credentials, or sensitive customer records.
