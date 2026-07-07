# Getting Started

## 1. Analyze the target

Start with a read-only recommendation for profile, risk level, harnesses, and skills.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project
```

Use `-Json` when another script should consume the recommendation.

## 2. Choose a profile

Use `minimal` for small repositories, `standard` for normal product work, and `supabase-react-finance` for high-risk React/Supabase finance projects. Treat the analyzer as a starting point, not as an irreversible decision.

## 3. Preview first

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard
```

Preview mode prints planned creates, existing skips, harness files, skill mirrors, and manual merge needs.

## 4. Optionally override harnesses

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini,cursor
```

## 5. Apply when the plan is acceptable

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath D:\path\to\project -Profile standard -Apply
```

## 6. Audit the target

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1 -TargetPath D:\path\to\project
```

Use `-Strict` in CI or release-style checks.

## 7. Validate this layer before changing it

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\matrix.ps1
```
