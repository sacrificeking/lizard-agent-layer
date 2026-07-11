# Merge Suggestions

`scripts/merge-suggestions.ps1` generates review artifacts for existing harness instruction files without modifying the target project.

## Why they exist

Install plans tell you that a merge is needed. Merge suggestions go one step further: they produce a report, patch file, JSON metadata, and a copy-ready Markdown block for each existing instruction file that needs an intentional lizard-agent-layer reference.

## Usage

Default output under `.tmp/merge-suggestions/`:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard
```

Custom output directory:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -OutputDir .\.tmp\merge-review\project
```

Harness override:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini
```

Machine-readable output:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -Json
```

Compatibility mode with complete existing instruction context in patch files:

```powershell
pwsh -NoProfile -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -IncludeExistingContext
```

## Output

The output directory contains:

- `merge-suggestions.md`: human-readable review report.
- `merge-suggestions.json`: machine-readable report metadata.
- `*.patch`: zero-context append suggestions by default; apply with tooling that supports zero-context unified diffs, or use the copy-ready block.
- `*.block.md`: copy-ready Markdown blocks for manual merges.

## Statuses

- `merge-needed`: the target instruction file exists and does not yet reference `lizard-agent-layer`.
- `already-wired`: the target instruction file already references `lizard-agent-layer`.
- `create-by-installer`: the instruction file is missing, so the installer can create it directly.

## Safety behavior

The script only writes to the selected output directory. It never writes `.agent/`, sidecars, harness instruction files, or skill mirrors into the target project.

Default output is `metadata-only`: it records the instruction path and SHA-256 but never copies existing project instructions into Markdown, JSON, patch, block, or console output. `-IncludeExistingContext` is an explicit compatibility mode that includes existing content only in the generated patch and labels the report `contains-target-context`. Treat those patch files as sensitive project material.
