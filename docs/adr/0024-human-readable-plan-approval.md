# ADR 0024: Human-Readable Plan Approval and Three-Tiered Authorization

- Status: accepted
- Date: 2026-09-03
- Supersedes: ADR 0010 (the clause requiring an independently supplied lowercase SHA-256 on every apply)

## Context

ADR 0010 established immutable canonical JSON operation plans and required `-Apply` callers to independently supply a 64-hex SHA-256 string along with `-HumanApproved`. In practice, especially in IDEs and AI assistant workflows (Codex, Cursor, Copilot), the assistant generated the plan, computed the hash, and instructed the operator to type `APPROVE <64-hex>`. 

This resulted in:
1. **Machine fingerprint over decision**: The 64-hex hash conveys no target, profile, harnesses, path counts, or risk details to the human.
2. **False independence**: An assistant computing and pasting the digest into the CLI bypasses independent verification while imposing typing ceremony.
3. **Over-constrained high-risk policy**: Early v1.4.1 enforcement required RSA cryptographic trust envelopes for any `high` risk profile or pack, blocking standard local installs in private developer workspaces.

## Decision

Plan authorization transitions to a three-tiered model, defaulting to human-readable **Plan Cards**:

1. **`summary` mode (default)**:
   - The operator inspects a concise Plan Card showing the operation, target, profile, harnesses, packs, risk level, path counts, and expiry.
   - Authorization is granted with `APPROVE PLAN <plan_id>` and executed with `-Apply -ApprovedPlanPath <path> -HumanApproved`.
   - The installer/updater re-reads the canonical plan file, validates schema, expiry, `plan_id`, and intent bindings, and calculates the SHA-256 digest internally. If a `.sha256` sidecar exists, it verifies that file bytes have not drifted since preview.
   - The applied SHA-256 and plan ID are persisted on the target manifest for auditability.
2. **`digest` mode (opt-in)**:
   - For high-assurance or regulated audit environments where the human or CI pipeline independently calculates and supplies `-ApprovedPlanSha256`.
   - Rejects apply if the supplied digest does not match the canonical file bytes.
3. **`signed` mode (opt-in for install/update; mandatory for destructive operations)**:
   - Requires an RS256 signature envelope, trust store, challenge, and replay ledger outside the target root.
   - **Mandatory ONLY for destructive layer mutations**: uninstall `complete`, uninstall `export-then-complete`, `-Force`, `-ForceManaged`, and records purge/destroy.
   - Risk level `high` alone does NOT mandate signed approval for routine install and update workflows.
   - Introduces `scripts/new-approval.ps1` as the official operator CLI for minting signed approval materials.

## Consequences

- Direct `install.ps1 -Apply` and `update-target.ps1 -Apply` invocations no longer require `-ApprovedPlanSha256` by default, simplifying copy-paste workflows and AI assistant interactions.
- Existing scripts that supply `-ApprovedPlanSha256` continue to work without modification (treated as `digest` mode).
- Destructive actions retain ironclad cryptographic protection via mandatory signed approval.
- High-risk profiles and packs can be safely installed in private repositories without requiring an RSA key management ceremony.
