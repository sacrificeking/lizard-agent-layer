# Compatibility

## Supported hosts

| Host | Contract |
| --- | --- |
| Windows PowerShell 5.1 | Compatibility host; complete local gates supported |
| PowerShell 7.5+ on Windows | Primary portable host |
| PowerShell 7.5+ on Ubuntu | Primary portable host; symbolic-link and dedicated privileged mount fixtures |
| PowerShell 7.5+ on macOS | Primary portable host; symbolic-link and mount-identity policy fixtures |
| Node.js 22+ | Required for executable Draft 2020-12 validation |

The GitHub workflow runs the complete gate set on the four PowerShell host identities. Windows runs the gates sequentially in one job per runtime. Ubuntu and macOS partition the same set into a base/governance job, six deterministic focused-safety shards, a standalone smoke job, and one matrix job per built-in profile. A local Windows pass is not evidence that remote Unix jobs have run, and no individual Unix shard is evidence for the complete host contract.

Generated install and analyzer invocations use `Lizard.Host.psm1`. Windows PowerShell 5.1 renders `powershell.exe` with execution-policy compatibility; Windows PowerShell 7, Ubuntu, and macOS render `pwsh`, and Unix argv never receives `-ExecutionPolicy`. Machine-readable analyzer output exposes executable and argv separately. Git branch/base inputs reject option-like strings and revision expressions before Git inspection; base resolution uses an explicit end-of-options boundary.

## Filesystem assurance status

| Capability | Windows PowerShell 5.1 | Windows PowerShell 7.5+ | Ubuntu PowerShell 7.5+ | macOS PowerShell 7.5+ |
| --- | --- | --- | --- | --- |
| Lexical authorized-root containment | Local executable evidence | `powershell-7-windows` CI | `powershell-7-unix-base` CI | `powershell-7-unix-base` CI |
| Linked ancestor and terminal-object rejection | Local unit and adversarial evidence | `powershell-7-windows` CI | `powershell-7-unix-focused-shards` CI | `powershell-7-unix-focused-shards` CI |
| Mount and bind-mount boundary detection | Not applicable to NTFS | Not applicable to NTFS | `powershell-7-unix-base` (privileged mount fixtures) | `powershell-7-unix-base` (mounted-root policy) |
| Handle-bound/no-follow SafeFs access | Locally verified on NTFS | `powershell-7-windows` CI | `openat`/`statx` (`powershell-7-unix-*`) | `openat`/`fstat`/`fstatfs` (`powershell-7-unix-*`) |

Mount enforcement observes the current process mount namespace and rejects unavailable identity data. Windows uses parent-relative native opens, atomic create-new and replacement, and relative deletion. Linux and macOS use descriptor-relative component walks, no-follow terminal opens, mount/device identity, atomic stage commits, and relative deletion. Unsupported primitives fail closed. Git worktree create/remove apply is disabled because Git cannot consume this boundary; clean externally created worktrees can be registered read-only. WP-01C and H-03 are validated through the automated multi-host CI matrix across Windows, Ubuntu, and macOS.

## JSON runtime compatibility

Security-sensitive JSON readers preserve ISO-8601 timestamps as JSON strings so canonical plans, transaction journals, and loop evidence keep their schema-declared types. Windows PowerShell 5.1 already preserves these values as strings. PowerShell Core must be 7.5 or newer because the shared reader requires `ConvertFrom-Json -DateKind String`; older PowerShell Core versions fail closed with `LIZARD_JSON_DATE_POLICY_UNSUPPORTED` instead of silently producing `System.DateTime` values.

On macOS, internal install plan probes canonicalize the host-provided `/var/...` temporary root to `/private/var/...` before SafeFs validation. This narrowly handles the operating system's standard `/var` alias and does not weaken linked-ancestor rejection for caller-provided paths.

Windows full jobs, Unix base/focused jobs, and Unix per-profile matrix jobs have a 120-minute ceiling. Unix standalone smoke jobs have a 240-minute ceiling because their plan-bound lifecycle operations are intentionally sequential. These are execution ceilings, not expected durations or substitutes for per-gate timing evidence. Default local `scripts/ci.ps1` and `tests/run-focused.ps1` invocations remain complete and unsharded.

## Manifest compatibility

| Concern | Current contract |
| --- | --- |
| Writer schema | 4 |
| Minimum readable schema | 2 |
| Maximum readable schema | 4 |
| Schema 2 migration | Conservative; ambiguous artifacts become user-owned |
| Schema 3 migration | Existing records become active; deselected records are retained on the next approved apply |
| Future schemas | Rejected before report or target writes |
| Downgrade | Requires `-AllowDowngrade -HumanApproved` |

## Harness compatibility

Codex, Claude Code, Gemini, Cursor, and generic `AGENTS.md` adapters share the same `.agent/` core. Destination collisions require declared precedence or distinct sidecars. Matrix tests cover every built-in profile/harness pair.

## Change compatibility

Beginning with the exact-plan approval contract, direct install or update `-Apply` calls are unsupported. Existing targets need no manifest migration, but callers must generate a fresh schema-v1 canonical operation plan and pass `-ApprovedPlanPath`, `-ApprovedPlanSha256`, and `-HumanApproved`. Legacy Markdown plans cannot be upgraded into approvals.

Manifest schema v4 requires lifecycle-aware readers. Current tools read schema v3 conservatively and migrate it during the next approved apply. Older tools reject v4 through `minimum_reader_schema_version` instead of interpreting retained retired records as active artifacts.

Loop installations created before the executable runtime remain readable. Preview and apply `loop-sync.ps1` to add missing runtime manifest fields and files; sync never overwrites runtime state, events, leases, or budget.

Contract-sensitive changes require a file under `changes/` that links the relevant ADR and states migration plus compatibility disposition. Run:

```powershell
pwsh -NoProfile -File .\scripts\contract-check.ps1 -BaseRef <base-ref> -Strict
```

See [Deprecation policy](deprecation-policy.md) and [ADRs](adr/README.md).
