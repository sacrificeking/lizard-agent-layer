# Skill Maturity

Skill maturity makes reusable agent behavior auditable. It separates a valid skill from a deeply supported skill package.

## Levels

### baseline

A baseline skill is valid, safe enough to install, and understandable from `SKILL.md` alone.

Expected traits:

- Valid frontmatter.
- Clear description and activation context.
- Actionable rules or workflow.
- No unsafe local assumptions.

### ready

A ready skill adds enough verification and safety discipline for regular project use.

Expected traits:

- Baseline traits.
- Explicit verification, checks, tests, review, or audit guidance.
- Explicit safety, permission, secret, destructive-action, or risk boundaries.

### hardened

A hardened skill includes supporting material that reduces ambiguity and improves repeatability.

Expected traits:

- Ready traits.
- At least one support asset under `references/`, `examples/`, `scripts/`, or `tests/`.

### certified

A certified skill has both reference material and scenario tests. It is the target state for high-impact skills.

Expected traits:

- Hardened traits.
- `references/` for domain rules, rubrics, or source material.
- `tests/` for scenario-based expected behavior.

## Package layout

```text
skills/<skill-name>/
  SKILL.md
  references/
    *.md
  tests/
    *.md
  examples/
    *.md
  scripts/
    *.ps1
```

Only `SKILL.md` is required. Support folders are optional and should be added when they make behavior more precise.

## Installation behavior

The installer copies complete skill packages into `.agent/skills/` and harness-specific mirrors. Existing target files are still skipped unless force behavior is explicitly added in the future.

## Reporting

Run:

```powershell
pwsh -NoProfile -File .\scripts\score-layer.ps1
```

The report lists score, health, maturity, and risk for every skill.
