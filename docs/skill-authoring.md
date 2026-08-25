# Skill Authoring

A reusable skill is a small package under `skills/<name>/SKILL.md`.

## Rules

- Use lowercase hyphenated names.
- Keep frontmatter to `name` and `description` for Codex compatibility.
- Put trigger context in `description`.
- Keep instructions structured as contract-shaped specifications: When to Use, Success Criteria, Boundaries, Verification & Evidence, Output, and Stop Conditions.
- Add references only when the skill needs substantial domain detail.

## Validation

Run:

```powershell
pwsh -NoProfile -File .\scripts\validate.ps1
```

The validator checks skill names, required frontmatter, profile references, and JSON validity.

## Quality scoring

Run the layer scorer before promoting a skill:

```powershell
pwsh -NoProfile -File .\scripts\score-layer.ps1
```

A strong skill should explain when it activates, what the agent should do, how to verify the work, and what safety boundaries matter. References, scripts, examples, and tests raise documentation quality but do not prove behavior.

Lexical completeness alone is capped at `ready`. Add `evidence.json` only when repository tests genuinely exercise the skill's behavior. Declare at least one positive and one negative fixture, bind each to a focused test plus exact assertion marker, and record compatible hosts, model classes, owner, review date, and review record. Do not add decorative evidence merely to increase maturity.

## Package maturity

Keep simple skills as `baseline` or `ready`. Promote high-impact skills toward `hardened` or `certified` only when support assets reduce ambiguity and executable evidence proves positive and negative behavior. See [Skill maturity](skill-maturity.md).

## Target-Owned Local Skills

Target repositories can define custom, team-specific skills under `.agent/skills-local/<name>/SKILL.md`:
- **Ownership:** User-owned and git-committed by the target repository team.
- **Lifecycle:** Never clobbered or overwritten by `update-target.ps1` or `install.ps1`.
- **Integrity:** `doctor.ps1 -Strict` reports them as user-managed without requiring catalog hashes.
- **Contract:** Follow the same contract shape (When / Success / Boundaries / Evidence / Output / Stop) and point to `.agent/protocols/permissions.md`. Local skills cannot expand permissions.
