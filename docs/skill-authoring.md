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
