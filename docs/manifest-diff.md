# Manifest Diff

`manifest-diff.ps1` compares an installed target project against the current `lizard-agent-layer` source.

Use it before upgrades, after pack changes, and before adapting a high-risk target. It is intentionally stricter than `doctor.ps1`: doctor checks whether the installed target is internally usable; manifest diff checks whether it still matches the current layer contract.

## Usage

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project
```

Strict mode exits non-zero when drift is detected:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Strict
```

Machine-readable output:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\manifest-diff.ps1 -TargetPath D:\path\to\project -Json
```

## What It Compares

- Installed layer version versus current `VERSION`.
- Installed profile and risk posture versus the current profile plus requested packs.
- Requested packs, expanded packs, and target overlay pack sources.
- Expected skills versus installed manifest skills.
- Expected `.agent/skills/<skill>/SKILL.md` files.
- Manifest-managed paths that are missing on disk.

Reports are written under `.tmp/manifest-diff/`:

- `manifest-diff.json`
- `manifest-diff.md`

## Pack Overlays

When a target uses `.lizard-agent-layer/packs/<name>.json`, manifest diff resolves it the same way the installer does. Overlay packs may use `extends` to include built-in packs before applying project-specific additions.
