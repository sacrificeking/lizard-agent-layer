# lizard-agent-layer Codex/VS Code Static Audit

**Audit date:** 2026-08-01  
**Audit type:** Read-only static architecture, security, lifecycle, privacy, governance, developer-experience, extensibility, and test-evidence review  
**Source root:** `D:\Projekte\GitHub_Projects\lizard-agent-layer`  
**Branch:** `main`  
**Commit:** `1797097d8a1c5ab5444ac82e83786ac1ccc841f6`  
**Dynamic-test status:** Not started; explicit approval of the exact Phase 2 plan is still required  
**Regulatory-research status:** Offline; regulatory currency was not independently verified

## 1. Executive assessment

The repository has a strong design direction and several useful safety controls, but its implementation does not yet substantiate its strongest approval, recovery, reversibility, privacy, agent-governance, and regulated-use claims.

- No `BLOCKER` was established.
- No `CRITICAL` finding was demonstrated statically.
- Multiple `HIGH` findings were independently confirmed, challenged by a different auditor, and adjudicated as valid or valid with narrowed impact.
- The source repository was clean before and after the read-only audit.
- No test suite was executed during the static phase.
- Existing repository-generated reports, schemas, scores, and test artifacts were not treated as independent proof.

Preliminary release disposition:

| Context | Decision | Rationale |
| --- | --- | --- |
| Private project | `NO_GO` for release-readiness claims; isolated evaluation is reasonable | Useful controls exist, but the score is below the conditional-go threshold and material High findings remain |
| Normal company | `NO_GO` | Approval binding, command governance, retention, evidence authenticity, and supportable uninstall are incomplete |
| Regulated financial enterprise / ING-DiBa reference context | `NO_GO` | Regulated-data gates, provider approval, authenticated segregation, retention/deletion, safe recovery, and internal evidence are materially incomplete |

These are technical-readiness decisions, not legal conclusions, certifications, or ING-DiBa approvals.

## 2. Scope, baseline, and limitations

### 2.1 Observed environment

| Item | Observed state |
| --- | --- |
| Workspace and Git root | `D:\Projekte\GitHub_Projects\lizard-agent-layer` |
| Branch | `main` |
| Commit | `1797097d8a1c5ab5444ac82e83786ac1ccc841f6` |
| Worktree | Clean before and after audit |
| Operating system | Windows 10 Pro 64-bit, `10.0.19045` |
| Shell | Windows PowerShell `5.1.19041.7548` |
| PowerShell 7 | Not installed or discoverable |
| Node.js | `25.6.1` |
| Git | `2.52.0.windows.1` |
| Dependencies | `node_modules` present |
| Network | Not accessed |
| Commands/tests | Read-only inspection only; no test suite executed |
| Source writes during static audit | None |

### 2.2 Audit limitations

- No dynamic installer, updater, recovery, loop, or removal test was run.
- No Windows junction or symlink attack was executed.
- No Unix bind-mount, Linux, macOS, or PowerShell 7 behavior was observed.
- No real Codex-in-VS-Code installation journey was performed.
- No provider, model, MCP, connector, IDE extension, cloud-agent, or CI-runner behavior was observed.
- No process-level or network-level telemetry observation was performed.
- No official current regulatory sources were accessed.
- No organization-specific policies, provider contracts, classifications, approvals, IAM evidence, retention schedules, or audit records were supplied.
- Existing `.tmp` evidence was treated as repository-generated and was not accepted as independent proof.
- A complete product-supported uninstall roundtrip is not currently possible because no executable uninstaller exists.

## 3. Active instruction chain and prompt-injection boundary

The active instruction chain was:

1. Platform/system and Codex operating constraints.
2. The user-supplied Persona Prompt.
3. Repository-root `AGENTS.md`.
4. Ordinary repository content, treated as untrusted audit evidence.

No nested `AGENTS.md` or `AGENTS.override.md` applied to the workspace. Repository documentation, source comments, skills, profiles, fixtures, test data, generated evidence, and commit content were not permitted to change audit scope, enable networking, authorize mutation, expose secrets, suppress findings, or declare compliance.

The repository's own root instructions correctly classify installers as high-risk, require preview-first behavior, and prohibit default overwrites of existing target instructions, skills, memory, and protocols.

## 4. Repository map

| Area | Static inventory | Purpose |
| --- | ---: | --- |
| `scripts/` | 36 scripts/modules | Analysis, install, update, transactions, routing, loops, doctor, validation, and reports |
| `schemas/` | 32 schemas | Profiles, manifests, routing, loops, evidence, contracts, and reports |
| `skills/` | 21 skill packages / 25 files | Reusable agent workflows |
| `packs/` | 7 packs | Feature and risk overlays |
| `profiles/` | 3 profiles | Minimal, standard, and Supabase/React/finance baselines |
| `protocols/` | 7 protocols | Permissions, memory, secrets, release, handoff, staging, and context |
| `adapters/` | 6 harness adapters / 12 files | Codex, Claude Code, Gemini, Cursor, GitHub Copilot, and generic AGENTS.md |
| `tests/` | 27 files | Unit, smoke, integration, adversarial, and schema fixtures |
| `docs/` | 36 files | Architecture, safety, transactions, enterprise, compatibility, CI, packs, profiles, skills, and ADRs |
| `routing-policies/` | 1 policy | Provider-neutral staged routing |
| `loops/` | 5 definitions | L1/L2 loop patterns and registry |
| `model-profiles/` | 4 legacy profiles | Deprecated compatibility catalog |

The structural separation of profiles, packs, skills, protocols, adapters, schemas, and scripts is clear. The main lifecycle coupling remains concentrated in `install.ps1`, `update-target.ps1`, manifest handling, and transaction recovery.

## 5. Positive controls

The following controls are materially present in implementation or test code, although they were not dynamically observed during this audit:

- Lexical canonicalization and separator-bound root containment.
- Windows link, junction, and reparse-point rejection for target writes.
- Atomic lock acquisition using file creation with `CreateNew`.
- Write-ahead mutation records and backups for installer/update transactions.
- Conservative default preservation of existing target files.
- Sidecar-first handling of existing instruction destinations.
- Artifact-level ownership and SHA-256 fields in manifest v3.
- Fail-closed handling of newer unsupported manifest versions.
- Fail-closed advanced routing when inventories, runtime capabilities, calibration, or route coverage are incomplete.
- Separate route-decision and execution receipts.
- L2 worktree isolation, Git-state checks, and explicit `auto_merge=false` fields.
- Exact npm dependency versions and package-lock integrity hashes.
- GitHub Actions pinned to full commit SHAs.
- GitHub Actions permission limited to `contents: read`.
- Checkout credential persistence and package-manager cache disabled.
- CI definitions for Windows, Ubuntu, macOS, PowerShell 7, and Windows PowerShell 5.1.
- Clear documentation that repository instructions cannot govern providers, IDEs, MCP servers, runners, operating-system accounts, or external data flows.
- No explicit runtime HTTP client, telemetry SDK, analytics client, or hidden remote Git operation found statically.

## 6. Consolidated severe findings

Every finding in this section was confirmed by one auditor, challenged by another auditor, and adjudicated by the Audit Director.

### H-01 — Exact plan approval is not bound to apply

**Severity:** `HIGH`  
**Confidence:** High  
**Status:** Documented requirement contradicted by implementation

The installation runbook requires approval referring to the exact final plan. The installer accepts `-Apply` without an approved-plan path, plan hash, target identity, source commit, approval subject, expiry, or option-set binding.

Apply performs a fresh preflight, then mutates the target. The optional plan is written only near the end of the operation. Consequently, source content, target state, selected packs, harnesses, overlays, or command options can differ from the state the user reviewed without producing a plan-binding failure.

**Cross-challenge:** Confirmed. A preflight reduces ordinary errors but does not prove identity with a previously approved immutable plan.

**Required remediation:** Preview must emit canonical plan JSON and a SHA-256 digest. Apply must require the exact approved plan and digest, recompute all source/target/options/preconditions, and fail before lock acquisition or mutation on any mismatch.

### H-02 — Transaction recovery trusts mutable journal data and is not retry-safe

**Severity:** `HIGH`  
**Confidence:** High

The recovery implementation has several interacting weaknesses:

1. `backup_path` is read from mutable target-local journal JSON and joined to the transaction directory without proving that the resolved source remains inside the backup root.
2. The source hash is checked against another mutable value from the same journal.
3. Rollback reverses the persisted mutation list, processes all entries regardless of prior rollback status, and saves the reversed list.
4. A second recovery attempt reverses it again, which can restore a later intermediate state when the same path was mutated more than once.
5. A crash after persisting `state=committed` but before metadata cleanup can leave a lock that the recovery command reports as available while transaction join rejects the committed journal.

**Cross-challenge:** All five behaviors were confirmed statically. The external-source issue requires a caller-controlled journal and recovery approval, which narrows exploitability but does not remove the confused-deputy boundary.

**Required remediation:** Introduce a strict journal schema, bind operation ID and target-root identity, constrain and no-follow-check every backup source, store mutations in stable chronological order, replay by descending sequence, skip already rolled-back entries, and implement an explicit committed-cleanup recovery state.

### H-03 — Physical path containment is incomplete

**Severity:** `HIGH`  
**Confidence:** High for the design gaps; medium for platform-specific exploitability

The shared filesystem module detects symlinks and reparse metadata, but a POSIX bind mount or ordinary mountpoint is not a symlink and will not be detected by the current checks.

Write helpers validate a path and then perform a new name-based filesystem operation. A concurrent local process can potentially replace a checked ancestor between validation and mutation.

Loop evidence collection performs lexical containment checks but does not reject a linked final evidence file before `Get-FileHash`/`Get-Item`. A linked worktree file can therefore cause an out-of-root read. The durable evidence contains only path, size, and SHA-256, which narrows this to an unauthorized read/hash side channel rather than direct plaintext disclosure.

**Cross-challenge:** POSIX mount coverage, TOCTOU, and read-side symlink gaps were confirmed. Dynamic Windows and Unix fixtures remain necessary to establish exact host behavior.

**Required remediation:** Add safe-read and safe-hash primitives, reject linked terminal objects, identify mount/device boundaries on Unix, and use handle-bound/no-follow operations where supported. Fail closed where a physical boundary cannot be established.

### H-04 — Update and uninstall lose ownership evidence

**Severity:** `HIGH`  
**Confidence:** High

Updates may change profiles, packs, and harnesses. Every installer run starts a new artifact record set and serializes only artifacts registered by the current selection. Deselected skills, mirrors, sidecars, and other artifacts are neither removed nor retained as retired records.

This can leave physical artifacts in the target while deleting their ownership evidence from the manifest. A later manifest-based uninstall cannot prove what they are.

There is no executable uninstaller. The runbook is conservative, but there is no preview/apply identity, transaction journal, resumable delete state, quarantine, machine-readable deletion receipt, or behavioral uninstall suite.

A schema-valid manifest is also self-asserted: it does not independently prove historical ownership. The runbook requires containment rechecks before deletion but does not explicitly require hash, file identity, type, root identity, mount state, and plan hash to be revalidated immediately before every delete.

**Cross-challenge:** Contract-reduction orphans and the lack of executable removal were confirmed.

**Required remediation:** Preserve retired/tombstoned artifacts and implement a preview-first, exact-plan-bound, transactional `uninstall.ps1` that revalidates every artifact before removal, backs up or quarantines deleted files, removes files before empty directories, and verifies the final tree and preserved-file hashes.

### H-05 — `memoryMode: off` is advertised but not implemented

**Severity:** `HIGH` for restricted-data contexts; `MEDIUM` otherwise  
**Confidence:** High

The installation documentation offers `off`, and the profile schema accepts it. The installer exposes no `MemoryMode` parameter, all built-in profiles select `curated`, and installation unconditionally creates the personal, semantic, and working-memory directories and templates.

Installed adapters subsequently instruct agents to read those memory files.

**Cross-challenge:** Confirmed. Even a manually authored `off` profile would still receive memory files under the current installer flow.

**Required remediation:** Implement `curated`, `private-episodic`, and `off` across installer, plan, manifest, adapters, updater, doctor, and uninstaller. In `off`, create no memory artifacts or references and reject later managed memory writes.

### H-06 — Regulated data does not inherently force human review

**Severity:** `HIGH`  
**Confidence:** High

Normal strategy, execution, and verification routes include the `regulated` data class. The router automatically blocks `secrets`, but regulated-data review depends on a separate caller-supplied signal such as `regulated-data`.

Advanced routing filters candidate models against their declared allowed data classes. That is useful, but it is not an enforced privacy, legal, provider, purpose, jurisdiction, or internal-policy approval decision.

**Cross-challenge:** Confirmed and narrowed: model eligibility checks exist, while a mandatory review/approval envelope does not.

**Required remediation:** Make regulated data fail to `human-review` unless a current organization-owned approval envelope binds provider, model, harness, runtime fingerprint, purpose, data class, region, approver, validity interval, and decision reference.

### H-07 — `metadata-only` and `raw_prompt_stored=false` are not enforced invariants

**Severity:** `HIGH`  
**Confidence:** High

`route-task.ps1` accepts arbitrary signal strings, splits and trims them, persists them verbatim, and hard-codes `raw_prompt_stored=false`. The route-receipt schema permits unrestricted signal strings while requiring the false flag.

`record-execution.ps1` similarly accepts a free-form `EvidenceRef`, limited only by length, and stores it beside the same false declaration.

Even `DataClass=secrets` only blocks routing; it does not redact a caller-supplied secret included in `Signals` before an applied receipt is written.

Receipts require explicit `-Apply`, are path-contained, and are gitignored by default. This is therefore not automatic prompt collection or remote exfiltration. It is a durable local leakage and false-label channel.

**Cross-challenge:** Confirmed with the above scope limitation.

**Required remediation:** Use enumerated signal IDs, opaque bounded evidence identifiers, typed sensitivity fields, a shared safe-report serializer, deterministic redaction, and secret/personal-data canary tests across files, console output, errors, journals, and reports.

### H-08 — Agent startup and verifier commands cross unenforced trust boundaries

**Severity:** `HIGH`  
**Confidence:** High

Installed adapters direct agents to read target-controlled profile, memory, protocols, routing policy, and mirrored skills before an automatic strict doctor/manifest verification gate. These files are not marked as untrusted data with explicit platform/user/repository precedence.

Target overlay packs can include free-form `notes` and `verification` prose. The operator must select or update such an overlay, which narrows reachability, but the plan binds to the pack name rather than the exact overlay bytes. The manifest records overlay source and path without its content hash.

Separately, `loop-verify.ps1` accepts arbitrary command strings and runs each through PowerShell `-Command` with verifier-process privileges. Worktree isolation does not restrict environment reads, filesystem access outside the worktree, network use, child processes, or background processes.

The permissions protocol's statement that tests and type checks are always allowed is unsafe when target-defined test commands are executable code.

**Cross-challenge:** Startup ordering, overlay plan/apply TOCTOU, and arbitrary unsandboxed verifier commands were confirmed. Verifier commands must be explicitly supplied, which prevents automatic discovery but does not constrain their effects.

**Required remediation:** Define an explicit prompt-trust model, verify managed content before use, quarantine target prose from executable policy, bind overlay hashes into plans, and replace command strings with reviewed executable/argv contracts executed by a constrained runner.

### H-09 — Routing and verifier attestations are self-asserted

**Severity:** `HIGH`  
**Confidence:** High

Routing runtime, calibration, actual-model identity, execution receipts, implementer identity, and verifier identity are target-local strings and unkeyed hashes. The implementation performs many useful consistency, expiry, fingerprint, route, branch, and Git-state checks, but it does not authenticate a trusted issuer or principal.

Model evaluation evidence hashes are accepted by format rather than recomputed from bounded evidence. Actual provider/model values are supplied through command-line parameters. Verifier separation is only case-insensitive string inequality.

Most decisively, the integration test constructs a synthetic verifier PASS envelope and the L2 runtime accepts it as completion evidence.

**Cross-challenge:** Confirmed. Current artifacts support integrity consistency, not cryptographic or identity-backed attestation.

**Required remediation:** Use trusted executor/verifier identities, signed receipts, nonces/challenges, decision and plan hashes, provider/runtime-reported model identities, external approval references, replay protection, and schema/signature validation at every consumer.

### 6.1 Severe-finding evidence index

| Finding | Primary documentation claim | Responsible implementation | Positive/static test evidence | Negative evidence or uncovered case |
| --- | --- | --- | --- | --- |
| H-01 Exact plan binding | [`INSTALL.md:15`](../../INSTALL.md#L15), [`INSTALL.md:126`](../../INSTALL.md#L126) | [`scripts/install.ps1:1`](../../scripts/install.ps1#L1), [`scripts/install.ps1:797`](../../scripts/install.ps1#L797), [`scripts/install.ps1:845`](../../scripts/install.ps1#L845) | Apply performs a fresh internal preflight at [`scripts/install.ps1:797`](../../scripts/install.ps1#L797) | No approved plan path/hash parameter and no plan-drift negative test |
| H-02 Recovery trust/retry | [`docs/transactions.md:7`](../transactions.md#L7), [`docs/transactions.md:18`](../transactions.md#L18) | [`scripts/Lizard.Transaction.psm1:319`](../../scripts/Lizard.Transaction.psm1#L319), [`scripts/Lizard.Transaction.psm1:323`](../../scripts/Lizard.Transaction.psm1#L323), [`scripts/Lizard.Transaction.psm1:361`](../../scripts/Lizard.Transaction.psm1#L361), [`scripts/transaction-recover.ps1:37`](../../scripts/transaction-recover.ps1#L37) | Fault injection and one successful recovery path exist at [`tests/integration/transaction.tests.ps1:97`](../../tests/integration/transaction.tests.ps1#L97) | No tampered `backup_path`, failed-first-recovery retry, repeated same-path mutation, or committed-cleanup crash test |
| H-03 Physical containment | [`INSTALL.md:157`](../../INSTALL.md#L157), [`UNINSTALL.md:14`](../../UNINSTALL.md#L14), [`docs/safety-model.md:17`](../safety-model.md#L17) | [`scripts/Lizard.SafeFs.psm1:81`](../../scripts/Lizard.SafeFs.psm1#L81), [`scripts/Lizard.SafeFs.psm1:109`](../../scripts/Lizard.SafeFs.psm1#L109), [`scripts/loop-verify.ps1:180`](../../scripts/loop-verify.ps1#L180) | Link/junction write tests exist at [`tests/unit/safe-fs.tests.ps1:30`](../../tests/unit/safe-fs.tests.ps1#L30) and [`tests/adversarial/install-containment.tests.ps1:31`](../../tests/adversarial/install-containment.tests.ps1#L31) | No bind-mount, final read-link, or synchronized ancestor-swap test |
| H-04 Reversibility/ownership | [`README.md:141`](../../README.md#L141), [`UNINSTALL.md:41`](../../UNINSTALL.md#L41), [`UNINSTALL.md:102`](../../UNINSTALL.md#L102) | [`scripts/update-target.ps1:239`](../../scripts/update-target.ps1#L239), [`scripts/install.ps1:346`](../../scripts/install.ps1#L346), [`scripts/install.ps1:764`](../../scripts/install.ps1#L764), [`scripts/Lizard.Manifest.psm1:26`](../../scripts/Lizard.Manifest.psm1#L26) | Manifest v3 state tests exist at [`tests/integration/manifest-v3.tests.ps1:1`](../../tests/integration/manifest-v3.tests.ps1#L1) | No executable uninstaller, contract-reduction orphan test, delete transaction, or plan-time-to-delete identity test |
| H-05 Memory off | [`INSTALL.md:74`](../../INSTALL.md#L74), [`docs/getting-started.md:95`](../getting-started.md#L95) | [`scripts/install.ps1:1`](../../scripts/install.ps1#L1), [`scripts/install.ps1:845`](../../scripts/install.ps1#L845), [`adapters/codex/AGENTS.lizard.md:5`](../../adapters/codex/AGENTS.lizard.md#L5) | Profile schema accepts memory modes at [`schemas/lizard-agent-layer.schema.json:6`](../../schemas/lizard-agent-layer.schema.json#L6) | No installer parameter or mode-matrix test; memory creation is unconditional |
| H-06 Regulated-data gate | [`docs/enterprise-usage.md:40`](../enterprise-usage.md#L40), [`skills/staged-execution/SKILL.md:30`](../../skills/staged-execution/SKILL.md#L30) | [`routing-policies/staged-balanced.json:28`](../../routing-policies/staged-balanced.json#L28), [`scripts/route-task.ps1:136`](../../scripts/route-task.ps1#L136), [`scripts/route-task.ps1:217`](../../scripts/route-task.ps1#L217) | Secret blocking and manually supplied escalation signals are tested at [`tests/integration/model-routing.tests.ps1:88`](../../tests/integration/model-routing.tests.ps1#L88) | `DataClass=regulated` alone is not tested as a mandatory human gate |
| H-07 Receipt privacy | [`docs/staged-execution.md:63`](../staged-execution.md#L63), [`docs/adr/0009-provider-neutral-staged-routing.md:24`](../adr/0009-provider-neutral-staged-routing.md#L24) | [`scripts/route-task.ps1:38`](../../scripts/route-task.ps1#L38), [`scripts/route-task.ps1:289`](../../scripts/route-task.ps1#L289), [`scripts/record-execution.ps1:32`](../../scripts/record-execution.ps1#L32), [`schemas/route-receipt.schema.json:37`](../../schemas/route-receipt.schema.json#L37) | Receipt schema and benign receipt tests exist at [`tests/integration/model-routing.tests.ps1:108`](../../tests/integration/model-routing.tests.ps1#L108) | Tests assert the hard-coded flag rather than absence of secret/prompt canaries |
| H-08 Prompt/tool trust | [`docs/enterprise-usage.md:57`](../enterprise-usage.md#L57), [`protocols/permissions.md:5`](../../protocols/permissions.md#L5) | [`adapters/codex/AGENTS.lizard.md:5`](../../adapters/codex/AGENTS.lizard.md#L5), [`scripts/install.ps1:91`](../../scripts/install.ps1#L91), [`scripts/install.ps1:168`](../../scripts/install.ps1#L168), [`scripts/loop-verify.ps1:61`](../../scripts/loop-verify.ps1#L61), [`scripts/loop-verify.ps1:173`](../../scripts/loop-verify.ps1#L173) | Overlay references are name-validated at [`scripts/install.ps1:141`](../../scripts/install.ps1#L141); verifier failures block PASS | No malicious prompt/overlay fixture or environment/network/outside-root verifier-command containment test |
| H-09 Attestation/segregation | [`docs/staged-execution.md:77`](../staged-execution.md#L77), [`skills/loop-verifier/SKILL.md:11`](../../skills/loop-verifier/SKILL.md#L11) | [`schemas/routing-runtime.schema.json:7`](../../schemas/routing-runtime.schema.json#L7), [`scripts/record-execution.ps1:42`](../../scripts/record-execution.ps1#L42), [`scripts/loop-verify.ps1:85`](../../scripts/loop-verify.ps1#L85), [`scripts/Lizard.LoopRuntime.psm1:267`](../../scripts/Lizard.LoopRuntime.psm1#L267) | Git-state, branch, command failure, stale-state, and tamper consistency tests exist at [`tests/adversarial/loop-evidence.tests.ps1:65`](../../tests/adversarial/loop-evidence.tests.ps1#L65) | A handcrafted PASS is accepted in [`tests/integration/loop-runtime.tests.ps1:40`](../../tests/integration/loop-runtime.tests.ps1#L40); no signature/principal/replay test |

## 7. Medium and lower findings

### M-01 — Target analysis can cross read boundaries and has weak calibration

`analyze-target.ps1` uses ordinary `Resolve-Path`, manually descends child directories without link rejection, and directly reads marker files such as `package.json`. A linked directory or marker file may therefore extend its read boundary.

Recommendations rely heavily on marker presence and substring counts. The analyzer supplies reasons but not calibrated confidence, false-positive/false-negative estimates, deterministic scan ordering guarantees, or explicit separation between approved providers and merely detected instruction files.

### M-02 — Generated commands are Windows-specific

The analyzer and generated install plan hard-code `powershell.exe` even though the repository claims PowerShell 7 portability on Windows, Ubuntu, and macOS. Documentation examples use `pwsh`, so generated plans can be invalid on claimed Unix hosts.

### M-03 — Skill lifecycle is incomplete

Only 2 of the 21 skill packages contain `evidence.json`. Skills generally include only `name` and `description` frontmatter. Package version, dependencies, permissions, compatibility, conflict declarations, migration, disablement, recovery, and removal semantics are absent or advisory.

The maturity documentation appropriately caps skills without current executable evidence, but a complete safe lifecycle is not implemented.

### M-04 — Retention, disposal, and legal hold are absent

Gitignore rules reduce accidental commits but are not retention or access control. Memory, routing receipts, update history, and loop logs have no general executable TTL, purpose-bound retention, legal-hold override, selective purge, or deletion receipt.

Punctual expiries and cleanup exist for routing evidence, loop leases, worktrees, and transaction metadata; the finding applies to the broader durable-data lifecycle.

### M-05 — Doctor/update/report lifecycle gaps

- Doctor does not make every active, committed, invalid, or journal-missing transaction lock a decisive health outcome.
- Some doctor and upgrade child reads do not use safe child-path resolution.
- Target-local update-report behavior is inconsistent.
- Some report writes occur outside the target transaction and can remain after an apply failure.

### M-06 — CI dependency execution can be reduced

CI uses `npm ci` rather than `npm ci --ignore-scripts`, although the dependency documentation states lifecycle scripts are not required. Current dependency pins and integrity hashes are positive controls, but suppressing lifecycle scripts would reduce supply-chain execution exposure.

### M-07 — Metadata can still be sensitive

Absolute paths, usernames, branch names, command text, actor labels, project names, and filesystem topology can be confidential or personal data even when source excerpts are absent. Sensitivity, audience, purpose, retention, and redaction fields are not consistently applied across all reports and receipts.

### M-08 — L1/L2 are governance protocols without a constrained host

L1 report-only and L2 assisted-mode rules are useful, but the repository does not execute or sandbox the agent itself. An IDE, model, or local process can bypass the scripts and operate directly. Claims should distinguish `DOCUMENTED`, `IMPLEMENTED`, `TESTED`, and externally `ENFORCED` controls.

### L-01 — Git option-confusion edge cases

Branch and base-reference strings are passed to Git without consistent `--end-of-options` handling or strict `git check-ref-format` validation. PowerShell passes each value as one argument, so arbitrary shell injection was not established; the residual concern is option confusion and denial of service.

### INFO-01 — CI supply-chain configuration is materially good

The obvious claim that CI uses mutable action tags, write tokens, cached untrusted content, or persisted checkout credentials was disproved. Action SHAs were not verified against upstream sources because network access was prohibited.

### INFO-02 — No intentional runtime network client found statically

Static inspection found no explicit runtime PowerShell HTTP client, Node network client, telemetry SDK, analytics client, curl/wget invocation, or hidden remote Git operation. This does not prove IDE, provider, MCP, DNS, dependency, CI-runner, or dynamically loaded behavior.

## 8. Claim Ledger

No tests in this ledger were executed during the static audit. “Positive evidence” and “negative evidence” refer to implementation and test code found in the repository.

| ID | Claim | Implementation/evidence | Status | Confidence | Residual uncertainty |
| --- | --- | --- | --- | --- | --- |
| CL-01 | Multi-harness adapters | Six adapter manifests, shared core, adapter composition, static matrix runner | `PARTIALLY_VERIFIED` | High | Runtime behavior and current harness semantics not observed |
| CL-02 | Codex support through `AGENTS.md` and skill mirrors | Codex adapter targets `AGENTS.md` and `.agents/skills` | `PARTIALLY_VERIFIED` | High | Startup trust and integrity gate missing |
| CL-03 | Provider-neutral 10-80-10 staged execution | Staged policy and skill use logical roles and `inherit-current` | `PARTIALLY_VERIFIED` | Medium | Actual phase execution is advisory and not independently attestable |
| CL-04 | Optional calibrated automatic routing | Inventory/runtime schemas, route selection, expiry and fingerprint checks | `PARTIALLY_VERIFIED` | Medium | Runtime and model identity are self-asserted |
| CL-05 | Target-specific analysis and recommendations | Stack/marker analyzer with reasons and pack/profile selection | `PARTIALLY_VERIFIED` | Medium | Link containment, confidence, and heuristic accuracy unproven |
| CL-06 | Preview-first target mutation | Default no-apply paths and negative test code | `PARTIALLY_VERIFIED` | High | Not observed dynamically; report writes still occur outside target |
| CL-07 | Approval bound to exact final plan | Runbook requirement only | `CONTRADICTED` | High | No immutable plan/apply token or digest |
| CL-08 | Sidecars instead of silent overwrite | Adapter merge policies and installer sidecar logic | `PARTIALLY_VERIFIED` | High | Update/reduction and stale-pointer behavior incomplete |
| CL-09 | Manifest-backed, hash-bound ownership | Manifest v3 artifact records and hash state classification | `PARTIALLY_VERIFIED` | High | Mutable self-asserted manifest and orphaned retired artifacts |
| CL-10 | Linked-ancestor and mount rejection | SafeFs reparse/link checks | `CONTRADICTED` | High | POSIX mounts, read-side links, and TOCTOU remain |
| CL-11 | Transactional writes, rollback, and recovery | Atomic lock, journals, backups, rollback code and fault tests | `CONTRADICTED` | High | Journal trust, retry order, and committed cleanup defects |
| CL-12 | L1/L2 worktree isolation and verifier independence | Worktree, Git-state, evidence and no-auto-merge checks | `PARTIALLY_VERIFIED` | High | Verifier identity and PASS provenance unauthenticated |
| CL-13 | Metadata-only/private receipts | Gitignored receipt paths and privacy flags | `CONTRADICTED` | High | Arbitrary signals and evidence references can persist |
| CL-14 | No intentional runtime network client | Positive static search and scoped documentation | `PARTIALLY_VERIFIED` | Medium | No dynamic process/network observation |
| CL-15 | Executable schemas, mutations, adversarial CI | 32 schemas, mutation corpus, focused/adversarial tests, OS CI matrix | `PARTIALLY_VERIFIED` | High | Tests not run; mutation and abuse coverage remain incomplete |
| CL-16 | Complete user-preserving uninstall | AI-guided runbook only | `UNSUPPORTED` | High | No executable, transactional, resumable lifecycle |
| CL-17 | Effective memory modes | Documentation/schema only for `off` | `CONTRADICTED` | High | Installer always creates memory |
| CL-18 | Safe complete skill lifecycle | Skill packages can be added and copied | `UNSUPPORTED` | High | Versioning, migration, disablement, recovery, and removal incomplete |

### 8.1 Claim Ledger evidence index

| Claim | Source | Implementation | Positive evidence | Negative evidence / gap |
| --- | --- | --- | --- | --- |
| CL-01 | [`README.md:9`](../../README.md#L9) | [`adapters/codex/adapter.json:1`](../../adapters/codex/adapter.json#L1), [`scripts/Lizard.Manifest.psm1:108`](../../scripts/Lizard.Manifest.psm1#L108) | Profile/harness matrix runner at [`scripts/matrix.ps1:53`](../../scripts/matrix.ps1#L53) | No adapter behavior observed on real harnesses |
| CL-02 | [`README.md:45`](../../README.md#L45) | [`adapters/codex/adapter.json:8`](../../adapters/codex/adapter.json#L8), [`scripts/install.ps1:714`](../../scripts/install.ps1#L714) | Static matrix includes Codex | Startup trust gate missing |
| CL-03 | [`README.md:10`](../../README.md#L10) | [`routing-policies/staged-balanced.json:1`](../../routing-policies/staged-balanced.json#L1), [`scripts/route-task.ps1:188`](../../scripts/route-task.ps1#L188) | Routing integration test at [`tests/integration/model-routing.tests.ps1:1`](../../tests/integration/model-routing.tests.ps1#L1) | No observation that a harness performed the three phases |
| CL-04 | [`docs/staged-execution.md:67`](../staged-execution.md#L67) | [`scripts/route-task.ps1:193`](../../scripts/route-task.ps1#L193), [`scripts/calibrate-model.ps1:49`](../../scripts/calibrate-model.ps1#L49) | Expiry/fingerprint/candidate tests exist | Runtime/model identity remains self-asserted |
| CL-05 | [`INSTALL.md:31`](../../INSTALL.md#L31) | [`scripts/analyze-target.ps1:26`](../../scripts/analyze-target.ps1#L26), [`scripts/analyze-target.ps1:129`](../../scripts/analyze-target.ps1#L129) | Positive rich-target smoke fixture at [`tests/smoke.ps1:105`](../../tests/smoke.ps1#L105) | No negative classifier, linked scan, or calibrated-confidence suite |
| CL-06 | [`README.md:149`](../../README.md#L149) | [`scripts/install.ps1:816`](../../scripts/install.ps1#L816), [`scripts/update-target.ps1:280`](../../scripts/update-target.ps1#L280) | Preview containment test at [`tests/adversarial/install-containment.tests.ps1:60`](../../tests/adversarial/install-containment.tests.ps1#L60) | This audit did not observe preview/apply behavior |
| CL-07 | [`INSTALL.md:126`](../../INSTALL.md#L126) | [`scripts/install.ps1:1`](../../scripts/install.ps1#L1) | Internal preflight only | No plan hash, approval artifact, or drift test |
| CL-08 | [`README.md:54`](../../README.md#L54) | [`scripts/install.ps1:672`](../../scripts/install.ps1#L672) | Sidecar smoke path at [`tests/smoke.ps1:15`](../../tests/smoke.ps1#L15) | No stale/manual-merge lifecycle identity |
| CL-09 | [`README.md:153`](../../README.md#L153) | [`scripts/Lizard.Manifest.psm1:40`](../../scripts/Lizard.Manifest.psm1#L40), [`scripts/install.ps1:735`](../../scripts/install.ps1#L735) | Manifest-v3 integration tests | No authenticated ownership or retired artifact continuity |
| CL-10 | [`README.md:150`](../../README.md#L150) | [`scripts/Lizard.SafeFs.psm1:55`](../../scripts/Lizard.SafeFs.psm1#L55), [`scripts/Lizard.SafeFs.psm1:109`](../../scripts/Lizard.SafeFs.psm1#L109) | SafeFs and containment tests | Mount, TOCTOU, and read-side final link gaps |
| CL-11 | [`README.md:152`](../../README.md#L152) | [`scripts/Lizard.Transaction.psm1:74`](../../scripts/Lizard.Transaction.psm1#L74), [`scripts/Lizard.Transaction.psm1:314`](../../scripts/Lizard.Transaction.psm1#L314) | Transaction fault-injection tests | No hostile journal, retry-idempotence, or committed-cleanup test |
| CL-12 | [`README.md:17`](../../README.md#L17) | [`scripts/loop-worktree.ps1:70`](../../scripts/loop-worktree.ps1#L70), [`scripts/loop-verify.ps1:231`](../../scripts/loop-verify.ps1#L231) | Loop runtime and adversarial evidence tests | Identity/authenticity and host capability containment missing |
| CL-13 | [`docs/staged-execution.md:63`](../staged-execution.md#L63) | [`scripts/route-task.ps1:260`](../../scripts/route-task.ps1#L260), [`scripts/record-execution.ps1:67`](../../scripts/record-execution.ps1#L67) | Gitignore and schema checks | Caller can store sensitive strings beside a false privacy label |
| CL-14 | [`README.md:164`](../../README.md#L164), [`SECURITY.md:21`](../../SECURITY.md#L21) | No runtime HTTP client found in executable tree | Public-readiness static scan at [`tests/integration/public-readiness.tests.ps1:63`](../../tests/integration/public-readiness.tests.ps1#L63) | Scanner is incomplete; no dynamic network observation |
| CL-15 | [`README.md:16`](../../README.md#L16), [`README.md:18`](../../README.md#L18) | [`scripts/ci.ps1:57`](../../scripts/ci.ps1#L57), [`tools/schema-validator/validate.mjs:78`](../../tools/schema-validator/validate.mjs#L78) | 14 focused suites plus smoke/matrix/schema/contract gates are referenced | Tests were not run; several severe scenarios have no fixture |
| CL-16 | [`README.md:141`](../../README.md#L141), [`UNINSTALL.md:1`](../../UNINSTALL.md#L1) | No product uninstaller | Public-readiness checks validate runbook wording | No behavioral removal or roundtrip suite |
| CL-17 | [`INSTALL.md:74`](../../INSTALL.md#L74) | [`scripts/install.ps1:845`](../../scripts/install.ps1#L845) | Schema permits `off` | Installer has no memory-mode parameter and always installs memory |
| CL-18 | [`docs/skill-authoring.md:1`](../skill-authoring.md#L1), [`docs/skill-maturity.md:52`](../skill-maturity.md#L52) | [`scripts/install.ps1:633`](../../scripts/install.ps1#L633) | Two skills have executable-evidence metadata | No complete version/migrate/disable/recover/remove lifecycle |

## 9. Context scores

| Dimension | Maximum | Private | Company | Regulated |
| --- | ---: | ---: | ---: | ---: |
| Security and trust boundaries | 20 | 14 | 12 | 9 |
| Correctness, idempotence, and recovery | 15 | 10 | 8 | 6 |
| Reversibility and ownership | 10 | 5 | 4 | 3 |
| Target-specific installation | 10 | 6 | 5 | 4 |
| Codex/VS Code developer experience | 10 | 7 | 6 | 4 |
| Skills and extensibility | 10 | 6 | 5 | 4 |
| Enterprise and regulated governance | 15 | 8 | 6 | 3 |
| Tests, CI, and evidence quality | 10 | 8 | 7 | 5 |
| **Total** | **100** | **64** | **53** | **38** |

The scoring rubric requires at least 80, no Blocker/Critical, and compensating controls for every High for `CONDITIONAL_GO`. None of the contexts meets that threshold.

## 10. Regulatory applicability

Regulatory currency was not independently verified because the static audit prohibited network research. No ING-DiBa internal policy, approved architecture, provider contract, data classification, or organizational control evidence was supplied.

| Area | Applicability state | Evidence limitation |
| --- | --- | --- |
| GDPR and German data-protection requirements | `POTENTIALLY_APPLICABLE`, `LEGAL_REVIEW_REQUIRED`, `INTERNAL_EVIDENCE_REQUIRED` | Depends on personal-data flows, organizational roles, legal basis, provider terms, retention, and safeguards |
| DORA | `POTENTIALLY_APPLICABLE`, `LEGAL_REVIEW_REQUIRED`, `INTERNAL_EVIDENCE_REQUIRED` | Provider risk, resilience, incidents, testing, change, outsourcing, concentration, and exit processes are not established here |
| EU AI Act | `POTENTIALLY_APPLICABLE`, `LEGAL_REVIEW_REQUIRED`, `INTERNAL_EVIDENCE_REQUIRED` | Depends on organizational role and use case; no offline legal conclusion is made |
| BaFin / MaRisk | `POTENTIALLY_APPLICABLE`, `LEGAL_REVIEW_REQUIRED`, `INTERNAL_EVIDENCE_REQUIRED` | Current applicability and internal implementation cannot be inferred from source code |
| EBA ICT/security or outsourcing guidance | `POTENTIALLY_APPLICABLE`, `LEGAL_REVIEW_REQUIRED`, `INTERNAL_EVIDENCE_REQUIRED` | Provider classification, contracts, oversight, concentration risk, and exit evidence are absent |
| ING-DiBa-specific compliance or approval | `INTERNAL_EVIDENCE_REQUIRED` | No internal evidence was supplied |

The repository may contribute technical evidence to an organizational control system. It cannot itself establish compliance, provider approval, data residency, segregation of duties, retention, incident handling, change control, or exit readiness.

## 11. Top ten unverified or contradicted claims

1. Exact plan-to-apply identity.
2. Complete, safe, selective uninstall.
3. Retry-safe interrupted-operation recovery.
4. Mount-aware and race-resistant filesystem containment.
5. Effective `memoryMode: off`.
6. Mandatory review for regulated data.
7. Authenticated actual-model and verifier identity.
8. Structurally enforced metadata-only reporting.
9. Safe full skill lifecycle across update, migration, disablement, and removal.
10. Cross-platform behavior and a real Codex/VS Code user journey.

## 12. Prioritized implementation plan

### 12.1 P0 — Release-blocking work

| WP | Owner | Change | Dependencies | Required evidence and measurable exit criterion |
| --- | --- | --- | --- | --- |
| P0-01 Exact approval artifact | Core installer owner | Emit canonical plan JSON and SHA-256; bind source commit/version, target identity, target precondition hashes, profile, packs, harnesses, memory, routing, overlays, force flags, and report paths | Stable canonical JSON and plan schema | Changed source, target, options, overlay bytes, plan, or expiry produces `PLAN_BINDING_MISMATCH` before first mutation |
| P0-02 Journal trust and retry | Transaction owner | Validate journal schema, operation ID, root identity, sequence uniqueness, status, relative backup paths, and backup containment; make retries status-aware and sequence-stable | P0-03 safe-read/write APIs | Tampered journal fails closed; second and third recovery attempts restore the exact original tree and hashes |
| P0-03 Physical filesystem boundary | Filesystem owner | Add safe-read/safe-hash APIs, final-component link rejection, POSIX device/mount checks, and handle-bound/no-follow mutation where supported | Host abstraction and platform fixtures | Symlink, junction, bind-mount, final-link, and synchronized ancestor-swap fixtures cannot escape authorized roots |
| P0-04 Artifact lifecycle | Manifest/update owner | Preserve `active`, `retired-present`, `retired-missing`, and `removed` artifact records; expose retired paths in update plans | Manifest schema migration | Profile/pack/harness contraction never loses ownership evidence and never deletes retired content by default |
| P0-05 Executable uninstall | Lifecycle owner | Implement preview-first transactional `uninstall.ps1`, exact plan binding, per-artifact revalidation, quarantine/backup, file-before-directory removal, export, resume, rollback, and deletion receipt | P0-01 through P0-04 | Full install/update/local-modification/uninstall roundtrip restores original tree and preserved hashes; rerun is idempotent |
| P0-06 Memory modes | Privacy and installer owners | Implement `curated`, `private-episodic`, and `off` in install/update/manifest/adapters/doctor/uninstall | P0-01, P0-04, P0-05 | `off` creates no memory paths, files, references, permissions, or update residue |
| P0-07 Regulated-data approval | Governance/routing owner | Default regulated data to human review unless a current organization-owned approval binds provider, model, harness, purpose, data class, region, runtime fingerprint, owner, and validity | Provider-approval schema and trusted issuer | Every phase/risk/model-mode combination blocks missing, stale, revoked, mismatched, or wrong-region approval |
| P0-08 Safe reporting | Privacy/reporting owner | Replace free-form durable signals/evidence refs with stable IDs; add typed sensitivity, purpose, audience, retention, and redaction through one serializer | Receipt/report schema updates | Secret, email, customer, path, command, Unicode, multiline, and oversized canaries are absent or deterministically redacted from files, console, errors, and journals |
| P0-09 Constrained verifier runner | Agent-security owner | Replace PowerShell command strings with reviewed executable/argv contracts, sanitized environment, explicit cwd, timeout, process-tree termination, egress policy, filesystem policy, and command-plan hash | P0-01, host abstraction | Outside-root, environment, child-process, background-process, interactive, shell-metacharacter, and network canaries are denied or require separate capability approval |
| P0-10 Authenticated evidence | Evidence/routing/loop owners | Sign routing, execution, lifecycle, and verifier receipts; bind nonce, plan, policy, commit, runtime, model/provider identity, principal, and timestamp; add replay protection | Trusted key/identity model | Forged, replayed, copied, recomputed, handcrafted, wrong-principal, unsigned, and expired evidence is rejected |
| P0-11 Prompt trust model | Adapter/security owners | State instruction precedence and untrusted-content rules in every adapter; verify managed hashes before use; quarantine overlay prose; require overlay content-hash approval | P0-01, P0-03, P0-10 | Malicious memory, profile, overlay, protocol, or mirrored-skill text cannot expand permissions, enable network, suppress findings, or trigger tool calls |

### 12.2 P1 — Required hardening and supportability

| WP | Owner | Change | Dependencies | Exit criterion |
| --- | --- | --- | --- | --- |
| P1-01 Analyzer hardening | Analyzer owner | Safe no-follow scan, deterministic ordering, confidence and evidence fields, bounded negative signals, explicit approved-harness input | P0-03 | False-positive/negative and linked-target matrix passes |
| P1-02 Cross-platform commands | Host/DX owner | Render commands through host abstraction instead of hard-coded `powershell.exe` | Existing `Lizard.Host.psm1` | Generated commands execute on Windows PS 5.1, Windows pwsh, Ubuntu pwsh, and macOS pwsh |
| P1-03 Skill lifecycle | Skills owner | Add version, compatibility, dependency, permission, provenance, conflict, migration, disable, recovery, and removal metadata | Schema/version policy | Example skill completes create/validate/install/update/migrate/disable/recover/remove lifecycle without invasive core edits |
| P1-04 Retention and legal hold | Privacy/governance owner | Artifact classes, purpose, owner, TTL, disposal, legal hold, export, selective purge, and deletion evidence | P0-05, P0-08 | Boundary-date expiry, hold precedence, interruption, resume, export, and preserved-user-content tests pass |
| P1-05 Doctor and recovery state | Transaction/doctor owner | Make lock/journal states strict health outcomes; add committed-cleanup and journal-missing guidance | P0-02 | Doctor deterministically classifies active, stale, committed, recovery-required, invalid, and missing-journal locks |
| P1-06 Report transaction consistency | Update/report owner | Propagate target-report options consistently and journal every target-local report mutation | P0-02 | Failed update leaves no unapproved target report residue |
| P1-07 CI dependency hardening | CI owner | Use `npm ci --ignore-scripts`; add lifecycle-script canary, dependency review, license review, and network-capability allowlist | None | Install-script fixture never executes; lockfile change requires explicit evidence |
| P1-08 Control-responsibility matrix | Enterprise owner | Map each claim to repository enforcement, external enforcement, procedure, internal evidence, or unsupported status | P0 governance work | No documentation claim implies control over provider/IDE/MCP/runner boundaries without external evidence |

### 12.3 P2 — Assurance and maturity

| WP | Owner | Change | Exit criterion |
| --- | --- | --- | --- |
| P2-01 Independent dynamic assurance | Test/evidence owner | Execute the approved hostile lifecycle matrix on every supported host | Reproducible evidence packets for all core safety claims |
| P2-02 Real IDE journeys | DX owner | Fresh Codex/VS Code install, update, recovery, and removal studies for beginner and expert users | Exact task-completion and error-recovery criteria met |
| P2-03 Enterprise pilot pack | Enterprise/security/privacy owners | Provide organization-owned provider, classification, IAM, retention, incident, change, audit, and exit templates | Pilot cannot start without named owners and current internal evidence |
| P2-04 Regulatory review | Legal/privacy/risk owners | Verify current primary official sources and map actual deployment context | Legal review and internal evidence completed without repository self-certification |

## 13. Independent auditor memo summaries

### Audit Director and Chief Architect

The architecture is understandable and generally modular. The release claims exceed the evidence in plan identity, recovery, deletion, trust, and regulated governance. Severe findings were not averaged away by otherwise strong CI and documentation.

### PowerShell, filesystem, and transaction auditor

Confirmed lexical containment, reparse rejection, atomic locks, journals, and backups as positive controls. Identified POSIX mount gaps, TOCTOU, mutable backup-source trust, retry-unstable rollback ordering, committed-cleanup residue, journal durability windows, inconsistent target-report behavior, and incomplete doctor recovery checks.

### Agent, prompt-injection, and tool-security auditor

Confirmed that startup consumes target-controlled policy before strict integrity verification, verifier commands are unsandboxed, exact-plan approval is procedural, model/runtime attestation is self-asserted, L2 verifier identities can be forged, memory off is ineffective, and L1/L2 enforcement does not constrain the host agent.

### Banking governance and regulatory auditor

Confirmed candid enterprise disclaimers but found no mandatory regulated-data approval envelope, auditable provider-governance decision, authenticated segregation of duties, or records lifecycle. Regulated-financial deployment remains `NO_GO` and requires legal review plus internal evidence.

### Privacy and data-flow auditor

Mapped prompt/provider, memory, routing, execution, loop, report, and external-network boundaries. Confirmed false receipt privacy labels, ineffective memory off, missing regulated review, absent general retention/legal hold, sensitive metadata, and natural-language-only DLP controls.

### Developer-experience and VS Code auditor

The runbooks provide a good one-prompt starting point and explicit decision record, but generated commands are Windows-specific, plan/apply identity is missing, dynamic IDE behavior is untested, error recovery is complex, and full removal depends on assistant judgment rather than a product command.

### Skills, extensibility, and compatibility auditor

Profiles, packs, adapters, and schemas are cleanly separated and collision logic is useful. A new skill can be added without rewriting the core, but the lifecycle lacks versioning, permissions, dependencies, migrations, disablement, recovery, authenticated provenance, and removal.

### Test, CI, and evidence auditor

The repository contains broad unit, integration, smoke, adversarial, schema, matrix, and cross-platform CI definitions. Important gaps remain for exact-plan drift, uninstall, recovery retry, mounts/TOCTOU, analyzer read containment, prompt injection, command sandboxing, receipt canaries, memory off, forged identity, and npm lifecycle suppression. None of the tests was executed in the static phase.

### Red-team and supply-chain auditor

Confirmed verifier linked-file reads, analyzer linked-target exposure, target-overlay policy injection, unsuppressed npm lifecycle scripts, and uneven malicious-fixture coverage. Disproved broad claims of mutable CI action tags, overprivileged workflow tokens, credential persistence, and cache poisoning in the current workflow.

## 14. Phase 2 dynamic test plan — approval pending

Dynamic tests must not begin until this exact plan and its local writes are explicitly approved.

### 14.1 Boundaries

- Read-only original source: `D:\Projekte\GitHub_Projects\lizard-agent-layer`
- Approved sandbox root: `C:\tmp\lizard-agent-layer-audit-1797097d8a1c`
- Sandbox source copy: `C:\tmp\lizard-agent-layer-audit-1797097d8a1c\source-copy`
- Fixtures: `C:\tmp\lizard-agent-layer-audit-1797097d8a1c\fixtures`
- Evidence: `C:\tmp\lizard-agent-layer-audit-1797097d8a1c\evidence`
- Audit driver to create: `C:\tmp\lizard-agent-layer-audit-1797097d8a1c\phase2-audit.ps1`

No source-repository write, network access, dependency installation, elevation, remote operation, commit, push, release, deployment, migration, production access, or secret-value access is requested.

`node_modules` already exists and will be copied locally. PowerShell 7 is unavailable, so this phase can observe Windows PowerShell 5.1 only. Unix/macOS and bind-mount scenarios will remain `NOT_TESTABLE` rather than using a remote runner or requesting broader permissions.

### 14.2 Exact bootstrap commands

```powershell
git -C 'D:\Projekte\GitHub_Projects\lizard-agent-layer' status --short
git -C 'D:\Projekte\GitHub_Projects\lizard-agent-layer' rev-parse HEAD

New-Item -ItemType Directory -Path 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c'
git clone --no-hardlinks --local 'D:\Projekte\GitHub_Projects\lizard-agent-layer' 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\source-copy'
Copy-Item -LiteralPath 'D:\Projekte\GitHub_Projects\lizard-agent-layer\node_modules' -Destination 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\source-copy\node_modules' -Recurse
New-Item -ItemType Directory -Path 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\fixtures'
New-Item -ItemType Directory -Path 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\evidence'
```

Run the complete repository gate set against the sandbox clone:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\source-copy\scripts\ci.ps1' -LayerRoot 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\source-copy' -StrictGitStatus
```

Run the bounded adversarial driver:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\phase2-audit.ps1' -LayerRoot 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\source-copy' -FixtureRoot 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\fixtures' -EvidenceRoot 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\evidence' -MaximumCases 20
```

The driver will use repository entry points and controlled fixture data only. For each scenario it will record command, working directory, environment, exit code, relevant output, changed paths, and evidence SHA-256.

### 14.3 Scenario matrix

1. Empty repository.
2. Small private script repository.
3. Node/TypeScript product.
4. React/Supabase/finance repository.
5. Multi-language monorepo.
6. Existing Codex, Claude, Gemini, Cursor, and Copilot instructions.
7. Dirty affected and unaffected paths.
8. Read-only files and permission failures.
9. Long, Unicode, spaced, and special-character paths.
10. Windows symlink/junction ancestors and linked evidence files where host privileges permit.
11. Malicious manifest paths and newer schema versions.
12. Tampered hashes, journals, receipts, calibration, and verifier evidence.
13. Concurrent apply attempts.
14. Interrupted apply, failed first recovery, and repeated recovery.
15. Missing, stale, modified, adopted, and integrity-unknown artifacts.
16. Offline operation without intentionally invoked network commands.
17. Repository prompt-injection and overlay-policy fixtures.
18. Invalid or overprivileged skill fixture.
19. Plan/apply drift and approval-binding attempts.
20. Install/update/contract-reduction/removal roundtrip.

Because no product uninstaller exists, scenario 20 will record the product-supported uninstall entry point as `UNSUPPORTED`. A reference manifest-based cleanup may be performed only inside the fixture and will not count as evidence supporting the product's uninstall claim.

### 14.4 Verification commands

```powershell
git -C 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\source-copy' status --short
git -C 'D:\Projekte\GitHub_Projects\lizard-agent-layer' status --short
git -C 'D:\Projekte\GitHub_Projects\lizard-agent-layer' rev-parse HEAD

Get-ChildItem -LiteralPath 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c\evidence' -Recurse -File |
  Get-FileHash -Algorithm SHA256 |
  Sort-Object Path
```

### 14.5 Expected writes and execution limits

All expected writes are confined to the approved sandbox root:

- one local Git clone;
- one copied `node_modules` tree;
- `.tmp` reports inside the sandbox clone;
- at most 20 fixture trees;
- one audit driver;
- JSON, Markdown, and text evidence plus SHA-256 results.

Maximum scope:

- One source clone
- Twenty fixtures
- Three concurrent local processes
- Ninety minutes total execution
- Five GB maximum sandbox size

Stop immediately if:

- the original source commit or status changes;
- any write appears outside the sandbox;
- a command requests network, dependency installation, elevation, secrets, or remote access;
- an unexpected executable or child process is invoked;
- a target boundary cannot be resolved safely;
- a test would require real credentials or private data;
- the time or size limit is reached.

Cleanup will not be automatic so that evidence remains reviewable. After review, removal of the exact sandbox root requires separate approval:

```powershell
Remove-Item -LiteralPath 'C:\tmp\lizard-agent-layer-audit-1797097d8a1c' -Recurse -Force
```

## 15. Approval status

At the time this report was written, Phase 2 had **not** been approved and no dynamic test had started.

The required approval question is:

> Do you approve this exact dynamic audit plan, including the listed sandbox path, commands, and local writes?
