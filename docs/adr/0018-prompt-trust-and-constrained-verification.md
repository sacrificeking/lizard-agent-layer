# ADR 0018: Prompt trust and constrained verification

## Status

Accepted for incremental implementation on 2026-08-22.

## Context

Adapters previously told agents to consume target-managed profile, memory, protocol, routing, and skill text before any integrity gate. Target overlay packs could merge free-form notes and verification prose into the installed profile. Separately, the L2 verifier accepted arbitrary PowerShell command strings and executed them with verifier-process privileges.

WP-03 already made complete target-overlay bytes exact plan inputs, so post-approval overlay drift fails before mutation. That control needed explicit trust semantics, durable manifest evidence, prose quarantine, and a verifier execution boundary.

## Decision

All adapters state the same authority order: platform/system, authenticated organization, current user, integrity-verified repository policy, then other target/generated/external content. Before following managed `.agent` content, an adapter requires a current trusted strict Doctor and manifest-diff result for the target. Target content cannot waive its own check. This is documented in the installed `prompt-trust.md` protocol.

Target overlay structural settings remain usable only through an exact approved install/update plan. Overlay `notes` and `verification` prose is not merged into the executable installed profile. The manifest records the exact overlay SHA-256 and `prose_trust=quarantined`.

`loop-verify.ps1` no longer exposes or executes a free-form verification command. A verdict requires a separately stored, explicitly approved command plan and independently supplied SHA-256. The plan binds its lifetime, physical worktree-root identity, resolved Git executable path/hash, fixed runner restrictions, and allowlisted command IDs. The initial production allowlist contains only shell-free `git-head`; `git-missing-ref-probe` exists as a deterministic negative fixture. Arguments are internal constants, not plan or caller text.

The constrained runner uses `ProcessStartInfo` without a shell, fixes the working directory to the worktree root, clears inherited environment variables except minimal Windows loader values, disables Git system/global configuration and interactive credential prompting, applies a timeout, and records only command ID, timing, exit code, timeout state, output hash, and byte count. Plan ID/digest/runner ID are sealed into verifier evidence.

## Consequences

- Rich target-defined test commands are no longer run by `loop-verify`; trusted operators may run them separately until an externally enforced sandbox capability is designed and approved.
- The narrow allowlist denies network, outside-root writes, background commands, child tools, interactive prompts, shell metacharacters, and environment inspection by making them unrepresentable.
- Adapter prose cannot itself enforce an IDE or model host. The integrity gate and precedence rules narrow repository behavior claims but do not prove platform-level enforcement.
- Authenticated principals, signatures, nonce/replay protection, and revocation remain WP-10 work; this ADR provides integrity and execution containment, not identity authenticity.
