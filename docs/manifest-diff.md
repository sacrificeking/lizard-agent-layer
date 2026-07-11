# Manifest Diff

`manifest-diff.ps1` compares an installed target project against the current `lizard-agent-layer` source.

Use it before upgrades, after pack changes, and before adapting a high-risk target. It is intentionally stricter than `doctor.ps1`: doctor checks whether the installed target is internally usable; manifest diff checks whether it still matches the current layer contract.

## Usage

```powershell
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project
```

Strict mode exits non-zero when drift is detected:

```powershell
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

Machine-readable output:

```powershell
pwsh -NoProfile -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Json
```

## What It Compares

- Installed layer version versus current `VERSION`.
- Installed profile and risk posture versus the current profile plus requested packs.
- Requested packs, expanded packs, and target overlay pack sources.
- Expected skills versus installed manifest skills.
- Expected `.agent/skills/<skill>/SKILL.md` files.
- Manifest-managed paths that are missing on disk.
- Manifest v3 artifact coverage and ownership-index consistency.
- Current file hashes against the exact installed hashes for layer-owned and adopted artifacts.
- Current layer source hashes against recorded source identity.
- Skill and adapter mirror-group equality.
- Exact effective adapter instruction or sidecar identity, including declared compatibility aliases.

Schema v2 targets can still be inspected, but strict mode reports `integrity-unknown` and exits non-zero because legacy manifests cannot prove per-file ownership or content identity.

Reports are written under `.tmp/manifest-diff/`:

- `manifest-diff.json`
- `manifest-diff.md`

## Pack Overlays

When a target uses `.lizard-agent-layer/packs/<name>.json`, manifest diff resolves it the same way the installer does. Overlay packs may use `extends` to include built-in packs before applying project-specific additions.

## Relationship to Updates

`update-target.ps1` uses manifest diff before every preview/apply and again after apply in strict mode. Use `manifest-diff.ps1` directly when you only need an audit. Use `update-target.ps1` when you want the plan-first update workflow with preserved profile, packs, harnesses, apply mode, and update history.

A strict post-update pass means every claimed generated artifact is present and hash-consistent. User-owned files are preserved rather than certified as layer content.
