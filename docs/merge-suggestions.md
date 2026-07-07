# Merge Suggestions

`scripts/merge-suggestions.ps1` generates review artifacts for existing harness instruction files without modifying the target project.

## Why they exist

Install plans tell you that a merge is needed. Merge suggestions go one step further: they produce a report, patch file, JSON metadata, and a copy-ready Markdown block for each existing instruction file that needs an intentional lizard-agent-layer reference.

## Usage

Default output under `.tmp/merge-suggestions/`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard
```

Custom output directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -OutputDir .\.tmp\merge-review\project
```

Harness override:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -Harnesses codex,claude-code,gemini
```

Machine-readable output:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\merge-suggestions.ps1 -TargetPath D:\path\to\project -Profile standard -Json
```

## Output

The output directory contains:

- `merge-suggestions.md`: human-readable review report.
- `merge-suggestions.json`: machine-readable report metadata.
- `*.patch`: append-only patch suggestions for existing instruction files.
- `*.block.md`: copy-ready Markdown blocks for manual merges.

## Statuses

- `merge-needed`: the target instruction file exists and does not yet reference `lizard-agent-layer`.
- `already-wired`: the target instruction file already references `lizard-agent-layer`.
- `create-by-installer`: the instruction file is missing, so the installer can create it directly.

## Safety behavior

The script only writes to the selected output directory. It never writes `.agent/`, sidecars, harness instruction files, or skill mirrors into the target project.
