# Skill Maturity

Skill maturity makes reusable agent behavior auditable. Documentation quality and behavioral readiness are measured separately.

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
- It may still have no executable behavioral evidence.

### hardened

A hardened skill includes supporting material and current executable evidence.

Expected traits:

- Ready traits.
- At least one support asset under `references/`, `examples/`, `scripts/`, or `tests/`.
- An `evidence.json` with positive and negative fixtures.
- Every fixture assertion exists in a focused test suite that passed on the current host.
- Compatibility and review provenance are valid.

### certified

A certified skill combines excellent documentation with high behavioral readiness. It is the target state for high-impact skills.

Expected traits:

- Hardened traits.
- `references/` for domain rules, rubrics, or source material.
- Behavioral readiness of at least 90 with passing positive and negative fixtures.
- Current-host compatibility, model-class metadata, ownership, review date, and review record.

## Package layout

```text
skills/<skill-name>/
  SKILL.md
  evidence.json
  references/
    *.md
  tests/
    *.md
  examples/
    *.md
  scripts/
    *.ps1
```

Only `SKILL.md` is required. Without `evidence.json`, maturity is capped at `ready` regardless of keywords, headings, or decorative test files.

## Evidence contract

`evidence.json` never contains arbitrary commands. Each fixture names a repository-relative focused test and an exact assertion marker. Behavioral readiness is awarded only when the test exists, contains that marker, and passed in the current `.tmp/tests/focused-test-report.json`. This ties maturity to executed evidence without letting quality metadata execute unreviewed shell commands.

## Installation behavior

The installer copies complete skill packages into `.agent/skills/` and harness-specific mirrors. Existing target files are still skipped unless force behavior is explicitly added in the future.

## Reporting

Run:

```powershell
pwsh -NoProfile -File .\scripts\score-layer.ps1
```

The report lists documentation score, behavioral readiness, health, maturity, and risk for every skill. Standalone scoring without a current focused-test report does not claim hardened or certified maturity.
