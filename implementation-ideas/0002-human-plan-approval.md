# 0002 — Human-readable plan approval; digest and signed apply optional

**Work package:** WP-1 human approval card (default for local install/update); WP-2 opt-in digest; WP-3 `scripts/new-approval.ps1`; signed **mandatory only** for destructive layer mutations.
**Supersedes:** 0001 WP-B (mandatory high-risk RSA kit).
**Requires:** new ADR superseding the “always independently supplied SHA-256” clause of [ADR 0010](../docs/adr/0010-exact-plan-approval-binding.md).
**Trigger:** Live preview asked a human to `APPROVE <64-hex>`. The hex is unreadable, adds no security if the same agent computed it, and high-risk 1.4.1 policy then also demanded RSA artifacts the docs cannot produce.

**Live install (degen-resource-hub):** operator confirmed signed approvals were disproportionate for a local private Codex workspace, and that the layer still has no pleasant end-user command to mint trust store / challenge / envelope / replay ledger. That is this idea, not a new one.

Do not change product files until this idea is explicitly approved for implementation.

## Problem

ADR 0010 made `-Apply` require three things: canonical plan path, **independently retained** lowercase SHA-256, `-HumanApproved`. High-risk policy (1.4.1 working tree) added RS256 envelope + trust store + challenge + replay ledger.

What a human actually gets:

```text
APPROVE 09b19cc06e2788bccd89cd44046e2c63d0eac331626fb51271e75bc144f92674
```

That string does not say target, profile, harness, path count, or expiry. It is a machine fingerprint, presented as if it were a decision.

When the **same** assistant hashes the file, prints `APPROVE <hash>`, and pastes it into `-ApprovedPlanSha256`, the “independently supplied” property is false. The human performed copy-paste, not verification. The control becomes busywork.

High-risk then fail-closes apply unless the human also has an operator mint path that **does not exist** in public docs (`permissions.md` / `safety-model.md` are empty on this). First install of `enterprise-fullstack` or any high pack (`database-backend`, `backend-api`, `security-hardening`, `precision-domain`) is blocked for no operable reason.

The overlay does not need this ceremony in daily `.agent/` context. It is an **installer** control. It should not be “always on” just because a profile is labeled high.

## Goal

1. Default apply: the human approves a **readable plan card**, not a hex blob.
2. Exact SHA-256 binding: **optional**, installed/enabled only when the user wants substitution-resistant apply.
3. Signed apply (RSA): **optional**. On high-risk installs, **ask** whether to enable it. Never enable from risk label alone. Never block apply because the user said no.
4. Keep preview-first, sidecar-not-authority, plans outside the target (0001). Do not delete the hash machinery — stop forcing humans to parrot it.

## Solution

Three approval **modes**, chosen at install preview and recorded on the plan and later on the target manifest so update/uninstall inherit the choice.

| Mode | Human sees | Machine still does | When |
| --- | --- | --- | --- |
| `summary` (default) | Plan card: operation, target, profile, harnesses, packs, risk, path counts, expiry, plan id | Apply loads **that** plan file; rejects if `plan_id` / `intent_sha256` / expiry do not match the approved card; re-hashes internally and refuses if bytes changed since preview | private use, `minimal`/`standard`, first rollout |
| `digest` (opt-in) | Same card **plus** “optionally verify this SHA-256 yourself” | Also requires caller-supplied `-ApprovedPlanSha256` matching the file | user asked; regulated workflow that wants independent digest |
| `signed` (opt-in) | Same card plus pointer to operator kit **outside** the target | Envelope + trust store + challenge + replay ledger, all outside target | user asked, typically after a high-risk **question** |

High-risk question (install/update preview, once, before apply):

> This selection is high risk (profile and/or packs). Use extra apply binding?
> - No (default): summary approval only
> - Digest: I will supply the plan SHA-256 myself
> - Signed: cryptographic envelope outside the target (needs the operator kit)

Silence or “just install” → `summary`. Do not infer `signed` from `enterprise-fullstack` or from analyzer pack recommendations.

`summary` still requires `-HumanApproved` and `-ApprovedPlanPath`. It must **not** require `-ApprovedPlanSha256`. If the flag is passed anyway, honor it (treat as `digest` for that apply).

Do **not** install extra overlay skills, protocols, or USING.md chapters for this. It is installer/update/uninstall only. Optional “install” means: persist `plan_approval_mode` on the **manifest**, not a pack of Markdown.

## Implementation

### WP-1 — Human approval card (default path)

1. New ADR 0024 (or next free number) superseding ADR 0010’s mandatory independent SHA:
   - Canonical plan + expiry + intent binding stay.
   - Default authorization is human approval of a **printed card** bound to `plan_id` (already in the plan) and `intent_sha256`.
   - Independent SHA and signed envelopes are optional modes.
   - Sidecar `.sha256` remains convenience, never authority.
2. Preview Markdown/console prints a fixed card, for example:

   ```text
   Plan id:        <plan_id>
   Operation:      install
   Target:         D:\...\degen-resource-hub
   Profile:        standard
   Harnesses:      github-copilot
   Packs:          (none)
   Risk:           medium
   Paths:          122 create / 0 overwrite / 0 conflict
   Expires:        2026-08-27 17:26 UTC
   Approval mode:  summary
   ```

   Human/AI approval line (default):

   ```text
   APPROVE PLAN <plan_id>
   ```

   Not `APPROVE <64-hex>`.
3. `install.ps1` / `update-target.ps1` / `uninstall.ps1`:
   - `summary`: `-Apply -ApprovedPlanPath -HumanApproved` is enough. Verify file `plan_id` equals the id shown in the preview that produced that file (file still has to be the canonical plan; if bytes were edited, `intent_sha256` / canonical check already fail).
   - Internal: still compute SHA and store it on the **manifest** after apply (`applied_plan_sha256`) for forensics. Do not make the human type it.
   - Between preview write and apply, if the plan file bytes change, fail closed (`PLAN_BINDING_DIGEST_MISMATCH` or equivalent) by comparing to the sidecar **only when the sidecar exists**; if sidecar missing, rely on canonical/expiry/intent checks. Do not resurrect “human must paste sidecar”.
4. INSTALL.md / QUICKSTART.md / INSTALL assistant procedure: ask for `APPROVE PLAN <id>` after showing the card. State clearly that pasting a hash from the assistant is not independent verification.
5. Tests: `standard` apply without `-ApprovedPlanSha256` succeeds; tampered plan bytes still fail; overlay calorie unchanged.

### WP-2 — Opt-in digest

1. Enable via:
   - Installer flag `-PlanApprovalMode digest`, or
   - Answer to the high-risk (or any-risk) question, or
   - Later `update-target` option recorded on the manifest
2. When mode is `digest`, today’s contract applies: `-ApprovedPlanSha256` required and must match file bytes. Docs show `Get-FileHash` as a **local** step the human runs, not a command the agent fills in.
3. Default profiles and packs do **not** set `digest`. No new pack required; a flag is enough. A pack would be the wrong shape (it would dump skills into the overlay).
4. Tests: digest mode without hash fails; with matching hash succeeds; with agent-supplied hash is allowed (the human chose the mode) but public examples must not compute hash and apply in the same snippet.

### WP-3 — Signed apply: official kit; mandatory only when destructive

Operator feedback: keep signatures for destructive / remote / production **layer** mutations; do not tax a local private overlay install.

| Operation | Default mode | Signed RSA |
| --- | --- | --- |
| install / update, any profile, including high packs | `summary` | **Ask** once on high risk; “no” still applies. Never auto-on from `enterprise-fullstack`. |
| uninstall `managed-only` | `summary` | no |
| uninstall `complete` / `export-then-complete`, `-Force`, `-ForceManaged`, records purge/destroy | `signed` | **yes** — these delete or clobber. |
| Git push, deploy, remote migration, CI edit | unchanged `permissions.md` human gate | **not** RSA envelopes. Those are model/operator actions, not `install.ps1`. Do not invent signed apply for `git push`. |

1. `Get-LizardOperationApprovalPolicy`: `signed_approval_required` if mode is `signed`, `-RequireSignedApproval`, **or** the operation is one of the destructive rows above. `riskLevel=high` alone does **not** set it.
2. High-risk **install/update** preview: three-way question (summary / digest / signed); persist `plan_approval_mode` on the plan. “No” → `summary` + `high_risk_binding_declined=true`.
3. Official operator command: **`scripts/new-approval.ps1`** (stable name). Mandatory `-TargetPath`, `-ApprovedPlanPath`, `-ApprovedPlanSha256`, `-OutputDir` (all outside target). Mints JWK, trust store, challenge, envelope, replay ledger; prints the six apply flags; warns the private key must not enter the target or git. Use `Lizard.Trust.psm1` / `Lizard.Plan.psm1` / `Lizard.SafeFs.psm1` only — never `TestTrustHelpers`.
4. `docs/signed-apply-approval.md` is the only workflow page. QUICKSTART/INSTALL must not point at `permissions.md` for envelopes.
5. Tests: local `standard`/`enterprise-fullstack` install without envelope succeeds; `complete` uninstall without envelope fails; in-target envelope still `PLAN_APPROVAL_ENVELOPE_IN_TARGET`; invert any test that says high risk ⇒ signed.

### Docs and overlay

- Operator card / adapters: no always-on SHA ritual.
- `docs/architecture.md` non-goals: “forcing humans to parrot a SHA-256 they did not compute”.
- Changelog: breaking for callers that assumed SHA always required — that is the point; document the three modes.

## Premortem

- `summary` without any byte check lets an agent show card A and apply a **replaced** file at the same path. Mitigate: canonical JSON + `plan_id` + expiry + intent hash already in the file; apply re-reads that file. Path swap still needs the human to pass `-ApprovedPlanPath` to the file they reviewed. Assistants must not silently point at a second file.
- Teams that wanted ADR 0010 as a bank control will see a regression if `digest`/`signed` are not easy to turn on. Mitigate: high-risk **ask** with a one-line why; persist mode on the manifest; enterprise docs recommend `digest` as the usual “yes”.
- Asking every high-risk preview will annoy experts. Mitigate: honor a stored default (`--PlanApprovalMode` or env is too much; manifest + explicit flag is enough). First install asks once.
- Keeping `-ApprovedPlanSha256` optional while examples still compute it in the same shell recreates theater. Ban that pattern in the public-command test from 0001.
- Do not invent a new overlay pack or skill named `plan-approval`. That would burn calorie and still not bind apply.
- Do not auto-mint RSA “temporarily” when the user did not opt into `signed`. That is a fake control.

## Done when

- Default first install: human/AI can apply after `APPROVE PLAN <plan_id>` with no hex and no RSA.
- A 64-hex `APPROVE` line is no longer the documented default.
- High-risk **install/update** asks about extra binding; “no” still applies.
- Destructive uninstall/force/purge require `signed` and `scripts/new-approval.ps1`.
- `digest` and `signed` exist, fail closed; local overlay install does not require them.
- Overlay always-on set is unchanged.
- 0001 WP-A remains the docs/path/harness fix; this idea owns approval UX and policy.
