# Getting Started

## 1. Analyze the target

Start with a read-only recommendation for profile, risk level, harnesses, and skills.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project
```

Use `-Json` when another script should consume the recommendation.

## 2. Choose a profile

Use `minimal` for small repositories, `standard` for normal product work, and `supabase-react-finance` for high-risk React/Supabase finance projects. Treat the analyzer as a starting point, not as an irreversible decision.

## 3. Write a plan report

Generate a human-readable plan before touching the target project.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -WritePlan
```

Use `-PlanPath` to choose the report location:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -WritePlan -PlanPath .\.tmp\plans\project-plan.md
```

Preview mode still does not create `.agent/`, sidecars, or harness files in the target. The plan is the only explicit write.

## 4. Preview first

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard
```

Preview mode prints planned creates, existing skips, harness files, skill mirrors, manual merge needs, and merge suggestion counts.

## 5. Optionally override harnesses

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,cursor
```

## 6. Apply when the plan is acceptable

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Apply
```

If an existing instruction file such as `AGENTS.md` already exists, the installer writes a sidecar and records merge suggestions instead of modifying the original file.

## 7. Audit the target

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project
```

Use `-Strict` in CI or release-style checks.

## 8. Validate this layer before changing it

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\matrix.ps1
```
