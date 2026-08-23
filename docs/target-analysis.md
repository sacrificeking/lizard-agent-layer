# Target Analysis

`scripts/analyze-target.ps1` inspects a project without modifying it and recommends a profile, an explicitly approved harness set, skills, packs, and risk level. It scans in ordinal order through SafeFs, rejects links and observed directory swaps, and reads bounded marker content through held-file primitives.

## Signals

The analyzer currently detects:

- Node, React, Vite, TypeScript, Next.js, and Supabase dependencies.
- Supabase directories, Edge Functions, and migrations.
- Existing instruction files such as `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and `.github/copilot-instructions.md`.
- Cursor usage through `.cursor/`.
- Finance, market, crypto, DeFi, stock, DCA, and yield markers in repository paths.
- Design-system signal through `DESIGN.md`.
- Agent-runtime signals through common LLM and tool-runtime dependencies.
- Monorepo signals through workspaces, pnpm, Turborepo, Nx, Lerna, and Rush markers.
- Non-Node signals through Python, Rust, Go, Java, and .NET project markers.
- Security and CI signals through workflow, env, container, auth, token, policy, and permission markers.
- UI/design package signals through Tailwind, Radix, lucide, and framer-motion dependencies.

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
