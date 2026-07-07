---
name: release
description: Controlled release workflow with verification, changelog, versioning, tagging, and final push gate. Use when preparing releases, version bumps, changelogs, publish steps, tags, or ship/go-live workflows.
---

# Release

## Rules

- Inspect working tree first.
- Identify pending changes and unrelated work.
- Run the target profile verification commands.
- Determine semantic version impact.
- Update changelog or release notes.
- Stop before remote push or tag push until the user explicitly approves.

## High-risk additions

- Verify database migrations before remote application.
- Verify generated types if schema changed.
- Verify public UI version labels if the project has them.
