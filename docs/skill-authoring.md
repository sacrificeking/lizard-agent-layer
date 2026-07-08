# Skill Authoring

A reusable skill is a small package under `skills/<name>/SKILL.md`.

## Rules

- Use lowercase hyphenated names.
- Keep frontmatter to `name` and `description` for Codex compatibility.
- Put trigger context in `description`.
- Keep instructions concise and procedural.
- Add references only when the skill needs substantial domain detail.

## Validation

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

The validator checks skill names, required frontmatter, profile references, and JSON validity.

## Quality scoring

Run the layer scorer before promoting a skill:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\score-layer.ps1
```

A strong skill should explain when it activates, what the agent should do, how to verify the work, and what safety boundaries matter. References, scripts, examples, and tests raise maturity but are not required for the baseline gate.

