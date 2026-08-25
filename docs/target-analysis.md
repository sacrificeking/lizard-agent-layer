# Target Analysis

`scripts/analyze-target.ps1` inspects a project without modifying it and recommends a profile, an explicitly approved harness set, skills, packs, and risk level. It scans in ordinal order through SafeFs, rejects links and observed directory swaps, and reads bounded marker content through held-file primitives.

## Signals

The analyzer detects project ecosystem and architectural markers:

- Enterprise and backend ecosystems (Java/Maven/Gradle, .NET/C#, Python, Go, Rust, Node/TypeScript).
- Frontend UI and fullstack frameworks (React, Vite, Next.js, Angular, Vue).
- Database systems, schema migrations, and backend API structures.
- Finance, accounting, ledger, and precision calculation paths.
- Monorepo structures (workspaces, pnpm, Turborepo, Nx).
- Security, auth, permissions, and CI/CD workflow configurations.
- Existing agent instructions (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, Copilot instructions, Cursor rules).

Dependency, build, coverage, and cache directories are skipped during recursive marker scans.

## Usage

```powershell
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project
```

Machine-readable output:

```powershell
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project -ApprovedHarnesses codex,github-copilot -Json
```

## Interpretation

The analyzer is intentionally conservative. Target instruction files are reported under `detectedHarnesses`, but cannot authorize their own runtime. Only values supplied through `-ApprovedHarnesses` appear as explicitly approved recommendations; the no-input default is `generic-agents-md`.

Every JSON result includes stable evidence IDs and strength, bounded negative signals, scan completeness, qualitative false-positive and false-negative risk, and a confidence score whose type is `bounded-evidence-score-not-probability`. These fields explain a deterministic rule result; they are not statistical assurance or a substitute for human knowledge of the project.

`previewInvocation` is the authoritative executable/argv representation. `previewCommand` is display text rendered from the current PowerShell host. A scan stopped by `MaxFiles` is explicit, uses `low` confidence, and reports `high` false-negative risk.

`recommendedPacks` are additive bundle suggestions. The generated preview command includes `-Packs ...` when bundle signals are detected.
