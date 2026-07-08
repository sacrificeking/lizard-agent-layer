---
name: security-hardening
description: Security review, threat modeling, permission boundaries, dependency risk, secret exposure, destructive action risk, and release hardening. Use when tasks mention security, auth, secrets, permissions, production risk, dependency vulnerabilities, or hardening.
---

# Security Hardening

## Rules

- Identify trust boundaries before changing auth, database, network, or filesystem behavior.
- Treat secrets, tokens, credentials, and production access as high-risk.
- Prefer least-privilege changes over broad permissions.
- Check dependency, script, and workflow changes for supply-chain risk.
- Preserve rollback paths for risky changes.
- Do not weaken safety gates to make a failing task pass.

## Verification

- Run the relevant tests, lint, typecheck, build, or security audit commands available in the project.
- Inspect changed config, environment, CI, auth, database, and dependency surfaces.
- Summarize remaining risk and any checks that could not be run.

## Safety

- Do not expose or log secrets.
- Do not apply production or remote changes without explicit user approval.
- Ask for confirmation before destructive or permission-broadening actions.
