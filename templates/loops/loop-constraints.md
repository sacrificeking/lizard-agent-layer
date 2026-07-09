# Loop Constraints

Schema version: 1
Default mode: report-only
Auto-merge: false
Max files changed without human: 0

## Denylist

The loop must not auto-edit these paths or domains:

- .env
- .env.*
- **/secrets/**
- **/credentials/**
- **/*_key*
- **/*_secret*
- supabase/migrations/**
- auth/**
- payments/**
- billing/**
- finance-critical logic
- production infrastructure

## Allowlist

Report-only actions are allowed:

- read repository files
- write .agent/loops state files
- append loop-run-log.md
- generate reports under .tmp/loops

## Human Gates

Require explicit human approval before:

- editing source code
- applying lizard-agent-layer updates
- using ForceManaged
- changing dependencies or lockfiles
- touching auth, security, finance, database migrations, or production infrastructure
- opening, merging, tagging, pushing, publishing, or deploying

## Secrets Policy

Never place secrets, credentials, API keys, tokens, or private customer data in prompts, state files, run logs, or reports.
