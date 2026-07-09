---
name: release-readiness
description: Produce report-only release readiness packets with version, changelog, gates, drift, risks, and human approval requirements.
---
# release-readiness

Use this skill before version commits, tags, release notes, or publishing. It produces a decision packet; it does not make release decisions automatically.

## Required Evidence

- Current version file
- Changelog top section
- Git status
- Available CI, build, smoke, quality, drift, pack, and manifest reports
- Known high-risk changes since the last release

## Rules

- Do not bump versions.
- Do not tag, push, publish, or deploy.
- Do not override failed gates.
- Human approval is required for release, failed gate acceptance, database migrations, auth/security/finance changes, and dependency risk.

## Output Format

```markdown
## Release Readiness

Verdict: READY|BLOCKED|HUMAN-DECISION
Version: <version>
Changelog: present|missing|needs work
Gates:
- <gate>: pass|fail|not run
Risks:
- <risk or none>
Human decisions:
- <decision or none>
Next action: <one sentence>
```

## Model Routing

Cheap models can collect evidence. Use a stronger model for the final verdict when the release touches security, auth, finance, Supabase, or dependencies.
