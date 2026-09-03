# 0005 — Windows operator happy path and source-checkout coupling

**Work package:** docs + small host helpers. No overlay skills. No SafeFs weakening.
**Live evidence (degen-resource-hub, Windows/Codex):** `pwsh` missing; SafeFs writes outside the workspace needed elevation; `npm` resolved to blocked `npm.ps1`; `npm.cmd` worked; doctor/manifest-diff still need the layer checkout.

Do not change product files until this idea is explicitly approved for implementation.

## Problem

Containment worked. The happy path did not.

1. **`pwsh`:** README requires PowerShell 7. Generated commands and copy-paste say `pwsh`. Windows 5.1 is a supported compatibility host (`Lizard.Host.psm1` can emit `powershell.exe`). A machine with only 5.1 cannot run front-door snippets. Doctor/install do not fail with a one-line “install PowerShell 7 from …” when `pwsh` is absent.
2. **`npm.ps1`:** On Windows PowerShell, `npm` often hits `%APPDATA%\npm\npm.ps1` and dies on ExecutionPolicy. Schema validation lives in the **source** checkout (`npm ci --ignore-scripts`), not the target. Public docs still say `npm ci`. CI already uses `npm.cmd` in the Windows 5.1 job. Humans do not.
3. **SafeFs outside the workspace:** Plans, receipts, and probe files must stay outside the target (0001). IDEs mark that path as “outside workspace”; Windows Controlled Folder Access / UAC then prompts. The rejection is correct; the error text does not say “put plans under `$HOME/.lizard-agent-layer/.tmp` and allow that folder” vs “this is a real containment escape”.
4. **Integrity scripts tied to source checkout:** `doctor.ps1` derives `LayerRoot` only from `$PSScriptRoot` (no `-LayerRoot`). `manifest-diff.ps1` already has `-LayerRoot` but defaults to the script tree and hashes source files there. Adapters tell the model to require strict doctor + manifest-diff. If the clone moves or is deleted, the installed target cannot prove overlay integrity. That coupling is **intentional** (layer source of truth, target has no npm/scripts). It is not documented as an operator dependency of daily work.

Point 10 of the same feedback (doctor + protocols before a tiny edit) is the adapter tax, not a missing scanner. Fold the wording fix here so daily Codex does not re-run source-bound doctor every turn.

## What not to do

- Do not copy `scripts/`, `doctor.ps1`, or `node_modules` into the target. “Doctor in the target setup” is rejected; that would ship the platform into every repo.
- Do not relax handle-bound SafeFs or allow in-target plans by default.
- Do not make `npm` a target-install requirement (it is not).
- Do not auto-elevate.

## Solution

| Gap | Fix |
| --- | --- |
| Missing `pwsh` | QUICKSTART/INSTALL: detect host; 5.1 snippets use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`; PS7 keep `pwsh`. `install.ps1` already goes through `Lizard.Host` for generated commands — keep that. Add a startup check in `install.ps1`/`doctor.ps1` that prints the required host if the current process is 5.1 and the user expected 7. |
| `npm` on Windows | Docs (`README`, `docs/ci.md`, `docs/schema-validation.md`, troubleshooting): on Windows use `npm.cmd ci --ignore-scripts`. State npm is **source-repo only**, never the target. |
| SafeFs elevation | On `SAFEFS_*` / access-denied when writing report roots, message: report path must be outside target **and** writable by the current user; recommended `$HOME/.lizard-agent-layer/.tmp`. Do not suggest `-AllowTargetReportWrite` as the first fix. |
| Doctor coupling | Add `-LayerRoot` to `doctor.ps1`. Record `layer_root` (absolute clone path at install time) on the target manifest. Doctor/USING look that up: “run `pwsh -File <layer_root>/scripts/doctor.ps1 -TargetPath <repo>`”. If the clone moved, fail `LAYER_ROOT_MISSING` with the recorded path. Discoverable **without** copying scripts into the target. |
| Wrappers | One source-repo entrypoint `scripts/lizard.ps1` (and `lizard.cmd` on Windows) that selects `pwsh` vs `powershell.exe -ExecutionPolicy Bypass` and `npm.cmd` vs `npm`. Subcommands at least `doctor`, `install`, `manifest-diff`. Not installed into targets. Generated plan commands should call this wrapper when present. |
| Daily / risk-tiered gates | **Low / trivial** (typo, local fix, read-only): `permissions.md` + `git-safety` only. Do not run doctor, premortem, or pack skills. **Medium/high:** if overlay trust is unknown (after install, update, or clone of `.agent/`), run doctor + manifest-diff from the recorded layer root; load the implementation skill (0006). Routine medium edits do not re-run doctor. Keep the 80-line always-on budget. |

## Implementation

1. `scripts/doctor.ps1` — `-LayerRoot`; if omitted and target has a manifest `layer_root` that still exists, use it.
2. Installer writes `layer_root` onto the install manifest (existing source checkout, not a copy).
3. `scripts/lizard.ps1` + `scripts/lizard.cmd` host/npm wrappers as above.
4. SafeFs/report access-denied: recommend `$HOME/.lizard-agent-layer/.tmp`; do not suggest `-AllowTargetReportWrite` first.
5. Docs: Windows `npm.cmd`; wrapper usage; “source checkout is required for doctor/schema, not for daily coding”.
6. Six adapters: unknown-trust doctor only; trivial-task skip. Overlay calorie still ≤80.
7. Tests: doctor with `-LayerRoot`; doctor from wrapper; calorie; troubleshooting mentions `npm.cmd`. No elevation-bypass test.

## Premortem

- Softening doctor-every-turn can let a stale overlay look trusted. Mitigate: still require the gate after install/update and when `manifest-diff` would be the first check in a new clone; champions keep CI `doctor -Strict`.
- Documenting `powershell.exe` without `-ExecutionPolicy Bypass` recreates the npm.ps1 class of failure for scripts.
- Telling users to disable ExecutionPolicy globally is worse than `npm.cmd`.
- `-AllowTargetReportWrite` as the SafeFs hint would undo 0001.

## Done when

- A Windows user without `pwsh` gets a host-correct command, `lizard.cmd` wrapper, or a clear PS7 hint.
- Source-repo docs use `npm.cmd` on Windows.
- Manifest records `layer_root`; doctor is findable from that path; **no** doctor.ps1 copied into the target.
- Trivial tasks skip doctor; unknown-trust after install/update still runs it.
- SafeFs still rejects in-target plans and linked ancestors.
