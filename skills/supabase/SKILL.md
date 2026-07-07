---
name: supabase
description: Supabase database, auth, generated types, RLS, migrations, Postgres, client boundaries, and schema safety. Use for Supabase work, SQL migrations, auth/session issues, RLS policies, generated database types, or remote database operations.
---

# Supabase

## Rules

- Treat schema changes as high-risk.
- Preserve RLS intent and auth boundaries.
- Prefer additive migrations unless a destructive change is explicitly planned.
- Regenerate or update generated types after schema changes.
- Do not run remote migrations without explicit user approval.
- Verify edge functions and client calls handle missing env vars and upstream failures.
