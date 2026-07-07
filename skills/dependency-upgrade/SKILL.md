---
name: dependency-upgrade
description: Dependency update planning and risk-aware package workflow. Use when installing, removing, auditing, upgrading, or reviewing dependencies, package manifests, lockfiles, npm outdated output, or major-version risks.
---

# Dependency Upgrade

## Rules

- Treat dependency changes as approval-required.
- Prefer focused upgrades over broad churn.
- Separate lockfile-only changes from code changes when possible.
- Run the profile verification commands after changes.
- Document major-version risks before applying.
