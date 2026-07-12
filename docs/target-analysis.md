# Target Analysis

`scripts/analyze-target.ps1` inspects a project without modifying it and recommends a profile, harness set, skills, packs, and risk level.

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
pwsh -NoProfile -File .\scripts\analyze-target.ps1 -TargetPath D:\path\to\project -Json
```

## Interpretation

The analyzer is intentionally conservative. It should help pick the first installation command, but humans should still adjust harnesses, packs, risk posture, and skills when a project has unusual constraints.

`recommendedPacks` are additive bundle suggestions. The generated preview command includes `-Packs ...` when bundle signals are detected.
