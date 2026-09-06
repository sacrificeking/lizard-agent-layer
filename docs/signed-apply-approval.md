# Signed Apply Approval

`lizard-agent-layer` uses cryptographic RS256 authorization envelopes to bind high-assurance and destructive operations to verified operator intent ([ADR 0024](adr/0024-human-readable-plan-approval.md)).

## Approval Tiers

| Tier | When Used | Verification Model |
| --- | --- | --- |
| **`summary`** *(default)* | Routine install & update in private repos | Human inspects Plan Card and confirms `APPROVE PLAN <id>`; hash computed and validated internally. |
| **`digest`** *(opt-in)* | Audit-tracked or regulated workflows | Operator independently computes and supplies `-ApprovedPlanSha256`. |
| **`signed`** *(mandatory for destructive actions)* | Complete uninstall, force overrides, records purge, or high-assurance policy | Cryptographic RS256 signature envelope, trust store, challenge, and replay ledger. |

---

## When Signed Approval is Mandatory

The layer approval policy (`Get-LizardOperationApprovalPolicy`) enforces signed approval for operations that delete or override files:

- **Complete uninstall:** `scripts/uninstall.ps1 -Scope complete`
- **Export-then-complete uninstall:** `scripts/uninstall.ps1 -Scope export-then-complete`
- **Force mutation overrides:** Any operation passed `-Force` or `-ForceManaged`
- **Records purge:** `scripts/records-lifecycle.ps1 -Action Purge`
- **Explicit policy flag:** Invocations with `-RequireSignedApproval` or `-PlanApprovalMode signed`

Standard installations with `enterprise-fullstack` or high-risk packs default to `summary` mode in local workspaces. They do **not** mandate RSA signing unless explicitly requested.

---

## Operator Workflow: Minting Signed Materials

Signed approvals require six artifacts generated outside the target repository:
1. `private-key.jwk.json`: 2048-bit RSA private key (operator machine only, never committed).
2. `trust-store.json`: Pinned public key certificate.
3. `challenge.json`: Time-bounded challenge bound to the target and plan hash.
4. `approval-envelope.json`: Cryptographic JWS envelope containing the plan payload.
5. `replay-ledger.jsonl`: Single-use ledger preventing nonce replay attacks.
6. Exact SHA-256 digests of the trust store and challenge.

Use the operator command `scripts/new-approval.ps1` (or `scripts/lizard.cmd new-approval` on Windows) to generate all required materials in a single step.

### Step 1: Preview the Operation

Generate the canonical plan outside the target:

```powershell
pwsh -NoProfile -File .\scripts\uninstall.ps1 -TargetPath D:\path\to\project -Scope complete -WritePlan -PlanPath $HOME/.lizard-agent-layer/.tmp/uninstall-plan.md -CanonicalPlanPath $HOME/.lizard-agent-layer/.tmp/uninstall-plan.json
```

Record the canonical plan path and its SHA-256 digest:

```powershell
Get-FileHash -LiteralPath "$HOME/.lizard-agent-layer/.tmp/uninstall-plan.json" -Algorithm SHA256
```

### Step 2: Mint Signed Approval Materials

Run `scripts/new-approval.ps1` with paths outside the target:

```powershell
pwsh -NoProfile -File .\scripts\new-approval.ps1 -TargetPath D:\path\to\project -ApprovedPlanPath $HOME/.lizard-agent-layer/.tmp/uninstall-plan.json -ApprovedPlanSha256 <plan-sha256> -OutputDir $HOME/.lizard-agent-layer/.tmp/approval
```

The script generates the keypair, seals the envelope, creates the replay ledger, and prints the exact `-Apply` flags to execute.

### Step 3: Apply with Cryptographic Verification

Execute the operation with the minted artifacts:

```powershell
pwsh -NoProfile -File .\scripts\uninstall.ps1 -TargetPath D:\path\to\project -Scope complete -Apply -ApprovedPlanPath $HOME/.lizard-agent-layer/.tmp/uninstall-plan.json -ApprovedPlanSha256 <plan-sha256> -HumanApproved -ApprovalEnvelopePath $HOME/.lizard-agent-layer/.tmp/approval/approval-envelope.json -TrustStorePath $HOME/.lizard-agent-layer/.tmp/approval/trust-store.json -TrustStoreSha256 <trust-sha256> -ChallengePath $HOME/.lizard-agent-layer/.tmp/approval/challenge.json -ChallengeSha256 <challenge-sha256> -ReplayLedgerPath $HOME/.lizard-agent-layer/.tmp/approval/replay-ledger.jsonl
```

---

## Windows & Host Dispatchers

On Windows systems where PowerShell 7 (`pwsh`) is not installed, use the universal dispatcher:

```cmd
scripts\lizard.cmd new-approval -TargetPath D:\path\to\project -ApprovedPlanPath %USERPROFILE%\.lizard-agent-layer\.tmp\uninstall-plan.json -ApprovedPlanSha256 <sha256> -OutputDir %USERPROFILE%\.lizard-agent-layer\.tmp\approval
```

---

## Security Invariants

- **Strict Path Isolation:** All approval inputs (`-ApprovalEnvelopePath`, `-TrustStorePath`, `-ChallengePath`, `-OutputDir`) must reside outside the target repository (`Assert-PathOutsideRoot`). Passing in-target paths fails closed with `PLAN_APPROVAL_ENVELOPE_IN_TARGET` to prevent automated self-approval by repository-contained agents.
- **Private Key Containment:** The generated `private-key.jwk.json` must **never** enter version control or the target filesystem.
- **Replay Resistance:** Every challenge contains a cryptographically random nonce. Once consumed by `Use-LizardReplayLedger`, the nonce is recorded in `replay-ledger.jsonl` and any reuse attempt fails closed with `TRUST_REPLAY_DETECTED`.
