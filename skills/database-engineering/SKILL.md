---
name: database-engineering
description: Database architecture, safe migrations, transactional DDL, query optimization, indexing, connection hygiene, and schema consistency across Oracle, PostgreSQL, MySQL, MSSQL, SQLite, and MongoDB.
---

# Database Engineering

## Rules

- Never execute or generate destructive DDL operations (`DROP TABLE`, unversioned column drops) without an explicit migration script and a tested rollback path.
- Enforce transactional boundaries (`BEGIN ... COMMIT / ROLLBACK`) for all schema and data migrations.
- Maintain zero-trust secret hygiene: never hardcode database credentials, passwords, or connection strings in application source or log outputs.
- Guard against N+1 queries and full table scans: inspect query explain plans and ensure foreign keys and query predicates are properly indexed.
- Ensure strict type synchronization between database schemas, ORM entities (e.g. Hibernate, JPA, Prisma, TypeORM), and API DTOs.
- Treat production database mutations as strictly human-gated.
