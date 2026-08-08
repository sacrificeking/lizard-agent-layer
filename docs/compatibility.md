# Compatibility

## Supported hosts

| Host | Contract |
| --- | --- |
| Windows PowerShell 5.1 | Compatibility host; complete local gates supported |
| PowerShell 7 on Windows | Primary portable host |
| PowerShell 7 on Ubuntu | Primary portable host; symbolic-link fixtures |
| PowerShell 7 on macOS | Primary portable host; symbolic-link fixtures |
| Node.js 22+ | Required for executable Draft 2020-12 validation |

The GitHub workflow runs the complete gate set on the four PowerShell host identities. A local Windows pass is not evidence that remote Unix jobs have run.

## Filesystem assurance status

| Capability | Windows PowerShell 5.1 | Windows PowerShell 7 | Ubuntu/macOS PowerShell 7 |
| --- | --- | --- | --- |
| Lexical authorized-root containment | Local executable evidence | CI evidence required after change | CI evidence required after change |
| Linked ancestor and terminal-object rejection for protected reads | Local unit and adversarial evidence | CI evidence required after change | CI symbolic-link evidence required after change |
| Mount and bind-mount boundary detection | Not applicable to the current Windows claim | Not implemented | Not implemented |
| Handle-bound/no-follow mutation | Not implemented | Not implemented | Not implemented |

The protected read/hash work therefore narrows the established link-following exposure but does not by itself establish complete physical containment or close the synchronized path-swap risk.

## Manifest compatibility

| Concern | Current contract |
| --- | --- |
| Writer schema | 3 |
| Minimum readable schema | 2 |
| Maximum readable schema | 3 |
| Schema 2 migration | Conservative; ambiguous artifacts become user-owned |
| Future schemas | Rejected before report or target writes |
| Downgrade | Requires `-AllowDowngrade -HumanApproved` |

## Harness compatibility

Codex, Claude Code, Gemini, Cursor, and generic `AGENTS.md` adapters share the same `.agent/` core. Destination collisions require declared precedence or distinct sidecars. Matrix tests cover every built-in profile/harness pair.

## Change compatibility

Beginning with the exact-plan approval contract, direct install or update `-Apply` calls are unsupported. Existing targets need no manifest migration, but callers must generate a fresh schema-v1 canonical operation plan and pass `-ApprovedPlanPath`, `-ApprovedPlanSha256`, and `-HumanApproved`. Legacy Markdown plans cannot be upgraded into approvals.

Loop installations created before the executable runtime remain readable. Preview and apply `loop-sync.ps1` to add missing runtime manifest fields and files; sync never overwrites runtime state, events, leases, or budget.

Contract-sensitive changes require a file under `changes/` that links the relevant ADR and states migration plus compatibility disposition. Run:

```powershell
pwsh -NoProfile -File .\scripts\contract-check.ps1 -BaseRef <base-ref> -Strict
```

See [Deprecation policy](deprecation-policy.md) and [ADRs](adr/README.md).
