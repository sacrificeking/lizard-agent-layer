# Profiles

Profiles describe how much agent infrastructure a target project should receive.

## minimal

For small scripts, libraries, or experiments. Installs generic instructions by default plus git safety and research audit skills.

## standard

For normal product repositories. Installs Codex, Claude Code, and Gemini adapters by default, plus release, dependency upgrade, git safety, and research audit workflows.

## supabase-react-finance

For high-risk React/Vite/Supabase finance applications. Installs Codex, Claude Code, and Gemini adapters by default, plus frontend, design system, Supabase, edge functions, data quality, release, git safety, dependency, and research audit skills.

## Harness override

Use `-Harnesses` with `scripts/install.ps1` to override profile defaults:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,cursor
```

Available adapters:

- `codex`
- `claude-code`
- `gemini`
- `cursor`
- `generic-agents-md`

## Model profiles

Profiles may map model roles:

- `implementation`: primary editing model
- `review`: independent reviewer
- `research`: broad research and synthesis model
- `lowRiskAssistant`: optional local or smaller model for low-risk tasks
