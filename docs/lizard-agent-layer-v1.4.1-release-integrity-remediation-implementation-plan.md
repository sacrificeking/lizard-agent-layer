# lizard-agent-layer v1.4.1
# Release Integrity & Verification Remediation Implementation Plan

## 0. Mission

The goal of v1.4.1 is **not to add new product features**.

The goal is to make the existing v1.4.0 architecture, security model, verification system, portability guarantees, and release process **internally consistent, reproducible, fail-closed, and release-safe**.

The release must close the remaining gaps identified during the independent v1.4.0 audit:

1. A release can currently be published while the exact release SHA still has failing or incomplete CI.
2. CI profile matrices can drift from the profiles that actually exist in the repository.
3. macOS currently shows reproducible `EACCES` / permission failures in SafeFS-related and generated-artifact workflows.
4. Smoke-test fixtures have drifted from the analyzer's current signal contract.
5. Some tests still use raw `ConvertFrom-Json`, recreating the exact `System.DateTime` issue already fixed in production code.
6. Signed high-risk approval is optional rather than policy-mandatory.
7. Replay-ledger enforcement is optional even when signed approval is required.
8. Transaction rollback anti-clobber protection does not fully cover post-delete / post-directory mutation state.
9. Release provenance is weak: `main` is not sufficiently protected, required checks are not enforced, and release/tag signing or equivalent provenance is missing.
10. Documentation and claims can describe stronger assurance than is demonstrated by the exact release SHA.
11. Verification configuration itself can drift from implementation.
12. Release governance is mostly procedural instead of technically enforced.

The target is a release where:

> No tag or GitHub Release can be produced unless the exact immutable commit has passed every required release gate on every supported host.

---

# 1. Non-Goals

Do **not** add unrelated features in v1.4.1.

Explicitly out of scope:

- new profiles
- new packs
- new skills
- new agent modes
- new harnesses
- new model-routing features
- new L2/L3 capabilities
- new memory modes
- UI or branding work
- unrelated refactoring
- speculative architecture rewrites

Refactoring is allowed only when directly required to:

- remove duplicated verification logic,
- eliminate drift,
- make a safety invariant enforceable,
- make failing cross-platform code testable,
- reduce release risk.

---

# 2. Global Definition of Done

v1.4.1 MUST NOT be considered complete until **all** conditions below are satisfied.

## 2.1 Repository State

- [ ] Working tree is clean.
- [ ] Version is consistently `1.4.1`.
- [ ] CHANGELOG contains only verified claims.
- [ ] No temporary implementation files remain.
- [ ] No stale profiles, fixtures, matrices, generated reports, or deprecated contract references remain.
- [ ] Contract drift checks pass.
- [ ] Documentation drift checks pass.

## 2.2 Supported Runtime Verification

Required supported environments:

- [ ] Windows + PowerShell 7
- [ ] Windows + Windows PowerShell 5.1
- [ ] Ubuntu + PowerShell 7
- [ ] macOS + PowerShell 7

Every mandatory release job must pass on the **exact same commit SHA**.

## 2.3 Security

- [ ] High-risk mutations require signed approval.
- [ ] Signed approvals require replay protection.
- [ ] Approval envelopes cannot reside inside the target repository.
- [ ] Transaction rollback refuses to overwrite divergent live state.
- [ ] Delete rollback refuses to overwrite a recreated path.
- [ ] Directory rollback refuses to mutate an unexpected replacement object.
- [ ] SafeFS behavior is verified on all supported platforms.

## 2.4 Release Integrity

- [ ] `main` has branch protection / ruleset enforcement.
- [ ] Required release checks are configured.
- [ ] Direct unverified release from a local workstation is no longer the normal supported flow.
- [ ] Release creation depends on successful CI of the exact SHA.
- [ ] Release workflow verifies tag ↔ commit identity.
- [ ] Release workflow refuses dirty, stale, mismatched, or previously failed candidates.
- [ ] Release provenance is recorded.
- [ ] Tag signing, GitHub artifact attestation, or equivalent cryptographic provenance is implemented where technically available.
- [ ] GitHub Release is created only after all release gates pass.

---

# 3. Workstream Overview

| ID | Workstream | Priority |
|---|---|---:|
| WS-01 | Freeze v1.4.1 Scope | P0 |
| WS-02 | Repair CI Profile/Harness Matrix Drift | P0 |
| WS-03 | Repair Analyzer Smoke Contract Drift | P0 |
| WS-04 | Complete Canonical JSON Migration | P0 |
| WS-05 | Root-Cause and Fix macOS SafeFS / EACCES Failures | P0 |
| WS-06 | Make Exact-SHA Green CI a Hard Release Requirement | P0 |
| WS-07 | Enforce Repository Branch / Ruleset Governance | P0 |
| WS-08 | Make Signed Approval Mandatory for High-Risk Mutations | P1 |
| WS-09 | Make Replay Protection Mandatory for Signed Approval | P1 |
| WS-10 | Complete Transaction Rollback Post-State Binding | P1 |
| WS-11 | Add Repository-Wide Verification Drift Detection | P1 |
| WS-12 | Add Release Provenance / Attestation | P1 |
| WS-13 | Align Documentation with Executable Reality | P1 |
| WS-14 | Harden Release Skill and Release Protocol | P1 |
| WS-15 | Build Explicit Release Readiness Report | P1 |
| WS-16 | Add Release Regression Test Suite | P1 |
| WS-17 | Final Multi-Host Soak and v1.4.1 Release | P0 |

---

# 4. WS-01 — Freeze v1.4.1 Scope

## Objective

Prevent new functionality from interfering with the remediation release.

## Tasks

### TASK-01.1 — Create v1.4.1 remediation branch

Recommended branch:

```text
remediation/v1.4.1-release-integrity
```

### TASK-01.2 — Define release freeze

Add a short section to the contributor/release documentation:

```text
v1.4.1 is a verification and release-integrity remediation release.
No unrelated product features are accepted until the release gates are green.
```

### TASK-01.3 — Record audit remediation goals

Create or update a remediation tracking document, for example:

```text
docs/remediation/v1.4.1-release-integrity.md
```

Include:

- finding ID
- severity
- affected files
- remediation PR/commit
- tests
- evidence
- status

## Acceptance Criteria

- [ ] Every v1.4.1 commit maps to one or more remediation tasks.
- [ ] No unrelated feature work is included.
- [ ] Changelog claims are written only after verification exists.

---

# 5. WS-02 — Repair CI Profile/Harness Matrix Drift

## Problem

The workflow contains stale references to `supabase-react-finance`, while current built-in profiles are:

```text
minimal
standard
enterprise-fullstack
```

A manually maintained matrix can drift again later.

## Objective

The CI matrix must derive from canonical repository configuration or be automatically validated against it.

## TASK-02.1 — Remove stale profile references

Search repository-wide for:

```text
supabase-react-finance
```

Inspect every occurrence.

Remove or migrate all references that are no longer valid.

Do not simply delete a reference without understanding whether it was intended to test:

- profile behavior,
- Supabase-specific pack behavior,
- finance/precision behavior,
- enterprise-fullstack behavior,
- a historical fixture.

If the old matrix entry represented functional coverage, migrate that coverage to:

```text
enterprise-fullstack
```

plus appropriate packs.

## TASK-02.2 — Define canonical profile discovery

Create a helper such as:

```text
scripts/Get-LizardBuiltinProfiles.ps1
```

or preferably a reusable module function:

```powershell
Get-LizardBuiltinProfileIds
```

Behavior:

1. Read `profiles/*.json`.
2. Parse using `ConvertFrom-LizardJson`.
3. Validate each profile against its schema.
4. Extract profile ID.
5. Sort using ordinal ordering.
6. Return deterministic output.
7. Fail if:
   - duplicate profile IDs exist,
   - filename and declared ID disagree,
   - schema validation fails.

## TASK-02.3 — Define canonical harness discovery

Create equivalent logic for supported adapters.

Possible source:

```text
adapters/*
```

or an explicit canonical registry if one already exists.

The important rule is:

> There must be exactly one source of truth.

Do not independently hardcode harness names in several workflows.

## TASK-02.4 — Add matrix consistency test

Create:

```text
tests/integration/ci-matrix-consistency.tests.ps1
```

The test should:

1. Discover all built-in profiles.
2. Discover all supported harnesses.
3. Parse CI workflow matrix configuration.
4. Determine which combinations the workflow claims to cover.
5. Assert:
   - every required profile appears,
   - no nonexistent profile appears,
   - every required harness appears,
   - no nonexistent harness appears,
   - required profile/harness pairs are represented.

Fail with explicit messages such as:

```text
CI_MATRIX_UNKNOWN_PROFILE: supabase-react-finance
CI_MATRIX_PROFILE_MISSING: enterprise-fullstack
CI_MATRIX_HARNESS_MISSING: gemini
```

## TASK-02.5 — Prefer generated matrix over duplicated YAML lists

Ideal design:

Have a preparation job emit a JSON matrix.

Example conceptual output:

```json
{
  "include": [
    {
      "profile": "minimal",
      "harness": "codex"
    },
    {
      "profile": "minimal",
      "harness": "claude-code"
    }
  ]
}
```

The workflow consumes that generated matrix.

Important:

- generation must use trusted repository code,
- matrix generation itself must be schema validated,
- generation must not consume untrusted target repositories.

## TASK-02.6 — Add negative regression fixtures

Tests must prove failure if:

1. a profile is added but CI coverage is not updated;
2. a profile is removed but remains in CI;
3. an adapter disappears but the matrix retains it;
4. a duplicate profile ID is introduced.

## Acceptance Criteria

- [ ] `supabase-react-finance` no longer exists as a stale matrix profile.
- [ ] `enterprise-fullstack` is tested.
- [ ] Built-in profile list and CI matrix cannot silently drift.
- [ ] Adding/removing a profile breaks CI until coverage is correct.

---

# 6. WS-03 — Repair Analyzer Smoke Contract Drift

## Problem

The smoke fixture expects the `precision` signal while the analyzer now requires at least two matching precision-domain path markers.

The fixture creates insufficient evidence.

## Objective

Tests must model the current contract intentionally rather than accidentally.

## TASK-03.1 — Document precision signal semantics

In the analyzer source, add a concise developer comment describing:

```text
precision is emitted only if >=2 approved path-group markers are detected.
```

Do not rely on test knowledge to infer this.

## TASK-03.2 — Fix smoke fixture

In:

```text
tests/smoke.ps1
```

Either:

### Option A — preferred

Create two legitimate fixture markers, for example:

```text
src/pages/finance/
src/lib/ledger/
```

so the fixture actually satisfies the production rule.

or:

### Option B

Stop expecting `precision` if the intended fixture is no longer meant to qualify.

Do **not** reduce the production analyzer threshold only to make the test pass unless that behavior is independently justified.

## TASK-03.3 — Add explicit positive analyzer test

Create or expand analyzer tests:

Fixture:

```text
finance + ledger
```

Expected:

```text
precision present
```

## TASK-03.4 — Add explicit negative analyzer test

Fixture:

```text
finance only
```

Expected:

```text
precision absent
```

Negative signal may indicate:

```text
precision-path-groups-below-threshold
```

## TASK-03.5 — Test determinism

Run the analyzer multiple times on the same fixture.

Assert:

- same signals,
- same order,
- same packs,
- same recommended profile,
- same warnings,
- same evidence IDs.

## Acceptance Criteria

- [ ] Smoke tests reflect the documented production contract.
- [ ] Precision threshold has explicit positive and negative tests.
- [ ] Analyzer output is deterministic.
- [ ] No production logic was weakened merely to satisfy stale tests.

---

# 7. WS-04 — Complete Canonical JSON Migration

## Problem

Production code was migrated, but tests still contain raw `ConvertFrom-Json`, including paths that create `System.DateTime` and break canonical JSON logic.

## Objective

Security-sensitive and contract-sensitive JSON must always use one canonical parser.

## TASK-04.1 — Inventory all raw JSON reads

Repository-wide search:

```text
ConvertFrom-Json
```

Classify every occurrence:

```text
A. prohibited runtime/security path
B. prohibited test path modeling runtime behavior
C. harmless external/tooling-only use
D. intentionally allowed compatibility test
```

Default classification should be **prohibited** unless justified.

## TASK-04.2 — Fix signed calibration test

Update:

```text
tests/adversarial/signed-calibration.tests.ps1
```

Replace raw:

```powershell
ConvertFrom-Json
```

with:

```powershell
ConvertFrom-LizardJson
```

Import the canonical JSON module where necessary.

Ensure ISO timestamps remain strings.

## TASK-04.3 — Fix other contract-sensitive test readers

Any test which:

- creates canonical plans,
- calculates trust bindings,
- signs evidence,
- compares hashes,
- tests replay protection,
- tests manifests,
- tests transaction journals,

must use the same JSON interpretation rules as production.

## TASK-04.4 — Add JSON parser policy lint

Create:

```text
scripts/check-json-reader-policy.ps1
```

Behavior:

1. Scan repository PowerShell files.
2. Find raw `ConvertFrom-Json`.
3. Exclude explicit allowlist entries.
4. Fail otherwise.

Example error:

```text
JSON_READER_POLICY_VIOLATION:
tests/adversarial/signed-calibration.tests.ps1: raw ConvertFrom-Json is not allowed.
```

## TASK-04.5 — Keep allowlist tiny and explicit

Possible allowlist file:

```text
config/raw-json-reader-allowlist.json
```

Each exception must include:

```json
{
  "path": "...",
  "reason": "...",
  "owner": "...",
  "expires": "..."
}
```

Prefer zero exceptions.

## TASK-04.6 — Add DateTime regression fixture

Test input:

```json
{
  "issued_at": "2026-08-26T17:32:57Z"
}
```

Assert:

```powershell
$value.issued_at -is [string]
```

and not:

```powershell
[DateTime]
```

Test on:

- Windows PowerShell 5.1
- PowerShell 7 current supported version
- Ubuntu
- macOS

## Acceptance Criteria

- [ ] Canonical paths contain no accidental raw `ConvertFrom-Json`.
- [ ] Signed calibration passes.
- [ ] ISO timestamps remain strings.
- [ ] CI fails if a new prohibited raw reader is introduced.

---

# 8. WS-05 — Root-Cause and Fix macOS SafeFS / EACCES Failures

## Problem

macOS CI repeatedly receives permission-denied errors when reading artifacts generated by the repository itself.

This MUST be root-caused. Do not suppress tests.

## Objective

Understand exactly why the generated files become unreadable and fix the underlying cross-platform behavior.

## TASK-05.1 — Build minimal reproducer

Create:

```text
tests/adversarial/macos-safefs-permissions.tests.ps1
```

On macOS:

1. Create temporary authorized root.
2. Create file through SafeFS.
3. Read through SafeFS.
4. Read using `[IO.File]`.
5. Read using `Get-Content`.
6. Hash using `Get-FileHash`.
7. Stat file.
8. Record:
   - owner UID/GID,
   - POSIX mode,
   - ACL,
   - extended attributes if relevant,
   - parent directory mode,
   - inode,
   - mount information.

Do the same after:

- atomic replace,
- rename,
- link/unlink create flow,
- transaction write,
- plan generation.

## TASK-05.2 — Compare Linux vs macOS semantics

Do not assume identical behavior.

Investigate:

- `openat`
- `renameat`
- `renameatx_np`
- `linkat`
- `fsync`
- file descriptor inheritance
- `O_NOFOLLOW`
- effective umask
- APFS behavior
- extended ACLs
- stage-file ownership/mode
- rename preserving mode
- link-based create semantics

## TASK-05.3 — Capture native errno

Improve SafeFS diagnostics.

Current generic messages such as:

```text
SAFEFS_NATIVE_CALL_FAILED
```

should include:

- operation,
- path,
- errno numeric value,
- normalized errno symbolic classification where possible.

Do not expose secrets.

Example:

```text
SAFEFS_NATIVE_CALL_FAILED:
operation=openat
errno=13
classification=EACCES
```

## TASK-05.4 — Verify stage-file mode explicitly

After SafeFS stage creation, assert expected access mode.

If runtime behavior creates overly restrictive modes, explicitly normalize permissions where safe and portable.

Be careful:

Do not blindly chmod everything `0666`.

Desired policy should be explicit, for example:

- files: owner read/write, group/other according to safe project default
- secrets/trust material: stricter permissions where required
- directories: traversable by current process

## TASK-05.5 — Verify parent directories

Permission denial may originate from a parent path.

Test every parent directory in generated paths, especially:

```text
.tmp/
.tmp/tests/
transaction directories
report directories
approval directories
```

Assert traversal permission.

## TASK-05.6 — Test SafeFS outputs with external standard readers

SafeFS-generated ordinary repository artifacts must remain consumable by:

```powershell
Get-Content
Get-FileHash
[IO.File]::ReadAllText()
Node fs.readFile
```

unless an artifact is intentionally protected.

This must become part of the portability contract.

## TASK-05.7 — Add macOS-specific regression tests

Explicitly cover failures previously observed in:

- host generated plan
- report privacy output
- update plan binding
- loop transaction journal
- uninstall preview
- focused test report

## TASK-05.8 — Never fix by skipping macOS

Forbidden fixes:

```text
if macOS then skip test
```

unless a capability is intentionally unsupported and documented as such.

macOS is currently claimed as a supported host, therefore its required behavior must work.

## Acceptance Criteria

- [ ] Root cause is documented.
- [ ] macOS SafeFS output is readable by expected consumers.
- [ ] No relevant EACCES failures remain.
- [ ] Native permission regression test exists.
- [ ] macOS full required release suite is green.

---

# 9. WS-06 — Make Exact-SHA Green CI a Hard Release Requirement

## Problem

v1.4.0 was released while the corresponding CI was not fully successful.

## Objective

Make this state technically impossible.

## TASK-06.1 — Define required release checks

Create a canonical release-check list.

Example conceptual checks:

```text
powershell-7-windows-full
powershell-5.1-windows-full
powershell-7-ubuntu-base
powershell-7-ubuntu-focused
powershell-7-ubuntu-smoke
powershell-7-ubuntu-profile-matrix
powershell-7-macos-base
powershell-7-macos-focused
powershell-7-macos-smoke
powershell-7-macos-profile-matrix
contract-governance
dependency-audit
release-readiness
```

The exact names must match workflow jobs.

## TASK-06.2 — Separate CI workflow from release workflow

Recommended model:

```text
CI workflow
   ↓
exact SHA fully green
   ↓
release workflow
   ↓
verify SHA again
   ↓
create tag
   ↓
create GitHub Release
```

Do not create the tag first and hope CI later passes.

## TASK-06.3 — Add release workflow

Create:

```text
.github/workflows/release.yml
```

Prefer:

```text
workflow_dispatch
```

or an appropriately controlled promotion mechanism.

Inputs:

```text
version
commit_sha
```

The workflow must verify:

1. SHA exists.
2. SHA belongs to expected branch.
3. version matches repository version.
4. changelog contains version.
5. exact SHA has all required successful CI checks.
6. no required check is:
   - queued
   - in_progress
   - cancelled
   - skipped unexpectedly
   - failed
   - timed out
7. no tag already points elsewhere.
8. candidate SHA has not changed.

## TASK-06.4 — Verify commit SHA before and after release preparation

At workflow start:

```text
candidate_sha = input SHA
```

Immediately before tag creation:

```text
git rev-parse HEAD == candidate_sha
```

Immediately before GitHub Release:

```text
tag target == candidate_sha
```

Fail if not.

## TASK-06.5 — Release only on exact completed CI

Do not accept:

```text
latest main is green
```

The requirement is:

```text
the exact candidate SHA is green
```

## TASK-06.6 — Add release refusal tests

Test cases:

```text
one required job failed → release denied
one required job pending → release denied
one required job missing → release denied
SHA mismatch → release denied
tag already exists at different SHA → release denied
version mismatch → release denied
```

## Acceptance Criteria

- [ ] GitHub Release cannot precede required CI.
- [ ] No tag is created for a red candidate.
- [ ] No release can target a different SHA than the approved candidate.
- [ ] Exact SHA is recorded in release evidence.

---

# 10. WS-07 — Enforce Repository Branch / Ruleset Governance

## Objective

Move from owner discipline to platform-enforced release governance.

## TASK-07.1 — Protect `main`

Configure GitHub branch protection or repository ruleset.

At minimum require:

- [ ] pull request before merge
- [ ] required status checks
- [ ] branch must be up to date before merge, if appropriate
- [ ] conversations resolved
- [ ] no force push
- [ ] no deletion
- [ ] required linear history if desired
- [ ] administrator bypass minimized or documented

## TASK-07.2 — Require CI checks

Required checks must cover all P0 release paths.

Do not require only one aggregate check if individual failures can be hidden.

If using a final aggregator job:

```text
release-gate
```

it must fail if any required dependency failed or did not run.

## TASK-07.3 — Add merge gate aggregator

Recommended:

```text
release-gate
```

Dependencies:

```yaml
needs:
  - windows-full
  - windows-5.1
  - ubuntu-base
  - ubuntu-smoke
  - ubuntu-matrix
  - macos-base
  - macos-smoke
  - macos-matrix
  - ...
```

The job itself should verify dependency conclusions.

## TASK-07.4 — Document bypass policy

If repository ownership requires emergency bypass:

Document:

- who may bypass,
- when,
- how evidence is recorded,
- why release creation still remains blocked until green CI.

## Acceptance Criteria

- [ ] Main cannot accidentally accept unverified changes.
- [ ] Release-critical checks are platform-required.
- [ ] Force push on `main` is disabled.
- [ ] Ruleset state is documented.

---

# 11. WS-08 — Make Signed Approval Mandatory for High-Risk Mutations

## Problem

`-HumanApproved` is still sufficient unless signed approval is explicitly requested.

## Objective

High-risk operations must not rely only on a command-line boolean.

## TASK-08.1 — Define high-risk policy centrally

Create one function:

```powershell
Get-LizardOperationApprovalPolicy
```

Inputs may include:

```text
operation_kind
profile
risk_level
scope
force flags
records action
memory transition
loop level
```

Output:

```json
{
  "signed_approval_required": true,
  "replay_ledger_required": true,
  "reason": "high-risk-operation"
}
```

Do not duplicate this logic across install/update/uninstall.

## TASK-08.2 — Minimum mandatory signed approval cases

Require signed approval for at least:

```text
enterprise-fullstack high-risk mutation
riskLevel=high
uninstall scope=complete
export-then-complete
Force
ForceManaged
records purge
destructive recovery
high-risk lifecycle mutation
operation removing externally meaningful content
```

Review existing risk classifications and extend carefully.

## TASK-08.3 — Fail closed if signed approval missing

Example:

```text
PLAN_SIGNED_APPROVAL_REQUIRED
```

Error must occur before mutation.

## TASK-08.4 — Preserve low-risk usability

For low/medium-risk local workflows, plain exact-plan + human approval may remain supported if justified.

This keeps the tool usable without weakening enterprise/high-risk guarantees.

## TASK-08.5 — Add policy tests

Positive:

```text
minimal low risk + ordinary install → signed approval not mandatory
```

Negative:

```text
enterprise/high risk → unsigned apply denied
complete uninstall → unsigned apply denied
records purge → unsigned apply denied
```

## Acceptance Criteria

- [ ] High-risk classification has one source of truth.
- [ ] High-risk unsigned mutation cannot execute.
- [ ] Low-risk behavior remains intentionally documented.

---

# 12. WS-09 — Make Replay Protection Mandatory for Signed Approval

## Problem

Signed approval may currently be used without a replay ledger.

## Objective

If signed approval is required, replay protection must be part of the security contract.

## TASK-09.1 — Enforce replay ledger requirement

Rule:

```text
RequireSignedApproval == true
→ ReplayLedgerPath must exist or be explicitly configured
```

Fail with:

```text
PLAN_REPLAY_LEDGER_REQUIRED
```

## TASK-09.2 — Bind replay ledger to trusted root

Ensure replay ledger itself:

- cannot live inside untrusted target content,
- uses SafeFS,
- has locking,
- is canonical JSON,
- has size bounds,
- rejects corruption,
- rejects duplicate envelope IDs,
- rejects duplicate challenge/nonce consumption.

## TASK-09.3 — Define consumption timing

Replay consumption must occur at the correct point.

Preferred order:

1. validate envelope
2. validate trust
3. validate exact plan binding
4. validate current target state
5. obtain mutation lock
6. revalidate
7. consume approval/replay token atomically
8. mutate

Avoid consuming too early if no mutation can start.

Avoid consuming too late if another process could reuse it.

## TASK-09.4 — Add concurrency test

Simulate two processes attempting the same approval.

Expected:

```text
exactly one succeeds
second fails TRUST_REPLAY_DETECTED
```

## TASK-09.5 — Add crash semantics test

Document behavior if process crashes:

```text
after ledger consumption
before first mutation
```

Choose one policy explicitly.

Preferred conservative behavior:

- approval remains consumed,
- operator must generate a new approval.

## Acceptance Criteria

- [ ] Signed approval always has replay protection.
- [ ] Same approval cannot successfully execute twice.
- [ ] Concurrent use is safe.
- [ ] Crash semantics are deterministic and documented.

---

# 13. WS-10 — Complete Transaction Rollback Post-State Binding

## Problem

`post_hash` protects live files written by Lizard, but deletion creates an expected post-state of absence rather than a hashable file.

## Objective

Every transaction mutation must have an explicit expected post-state.

## TASK-10.1 — Extend transaction journal schema

Add fields conceptually like:

```json
{
  "post_state": {
    "kind": "file|directory|absent",
    "sha256": "...",
    "identity": {}
  }
}
```

Possible design:

```text
file:
  kind=file
  sha256 required

directory:
  kind=directory
  identity optional/required depending operation

delete:
  kind=absent
```

Do not rely on `post_hash = null` because null is ambiguous.

## TASK-10.2 — Record expected post-state for every mutation

Examples:

### create file

```text
post kind=file
post hash=<written hash>
```

### replace file

```text
post kind=file
post hash=<replacement hash>
```

### delete file

```text
post kind=absent
```

### create directory

```text
post kind=directory
```

### remove directory

```text
post kind=absent
```

## TASK-10.3 — Validate post-state before rollback

Before rollback:

### Expected file

Verify:

- still file,
- same hash,
- optionally same identity if contract requires.

### Expected absent

Verify:

```text
destination still absent
```

If a new object exists:

```text
TRANSACTION_ROLLBACK_DESTINATION_DIVERGED
```

Do not overwrite it.

### Expected directory

Verify expected type and identity rules.

## TASK-10.4 — Add recreated-after-delete adversarial test

Scenario:

1. create original file `A`
2. transaction backs it up
3. transaction deletes `A`
4. inject failure
5. external actor recreates `A`
6. recovery runs

Expected:

```text
rollback fails closed
external file remains untouched
backup remains available
recovery-required state is recorded
```

## TASK-10.5 — Add directory replacement adversarial test

Scenario:

1. Lizard creates/removes expected directory
2. external actor creates file/symlink/different directory at same path
3. rollback occurs

Expected:

```text
no external object is deleted or overwritten
```

## TASK-10.6 — Preserve manual recovery evidence

On divergence:

- keep journal,
- keep backup,
- mark recovery required,
- print safe operator guidance,
- never auto-resolve ownership ambiguity.

## Acceptance Criteria

- [ ] Every mutation has explicit post-state.
- [ ] Delete rollback cannot overwrite recreated files.
- [ ] Directory rollback cannot remove unrelated replacements.
- [ ] Divergence is fail-closed.

---

# 14. WS-11 — Add Repository-Wide Verification Drift Detection

## Objective

Prevent implementation, tests, workflows, schemas, and documentation from silently diverging.

## TASK-11.1 — Create canonical registries

At minimum derive or define canonical sets for:

```text
profiles
packs
skills
harnesses
schemas
supported hosts
release checks
```

## TASK-11.2 — Add drift checker

Create:

```text
scripts/check-repository-drift.ps1
```

It should compare:

```text
canonical registries
↔ workflows
↔ documentation
↔ fixtures
↔ schemas
↔ tests
```

## TASK-11.3 — Detect stale names

Generic stale identifier detection should catch cases such as:

```text
supabase-react-finance
```

when no corresponding profile exists.

## TASK-11.4 — Detect missing coverage

Examples:

```text
new profile exists but no matrix coverage
new harness exists but no adapter test
new schema exists but no validation binding
```

## TASK-11.5 — Detect claims with no executable evidence

For critical compatibility claims, maintain machine-readable mapping:

```json
{
  "claim": "powershell-7-macos",
  "required_jobs": [
    "macos-base",
    "macos-smoke",
    "macos-matrix"
  ]
}
```

This prevents documentation from getting ahead of actual CI.

## Acceptance Criteria

- [ ] Stale profile names fail CI.
- [ ] Missing coverage fails CI.
- [ ] Host-support claims map to executable checks.

---

# 15. WS-12 — Add Release Provenance / Attestation

## Objective

Strengthen trust in the system that installs trust controls into other repositories.

## TASK-12.1 — Sign or attest release artifacts

Use one or more appropriate mechanisms:

```text
GitHub artifact attestations
signed Git tags
signed commits
Sigstore/cosign
GitHub OIDC-backed provenance
```

Select the mechanism compatible with project constraints.

## TASK-12.2 — Record release evidence

Produce machine-readable evidence:

```text
release-evidence.json
```

Example:

```json
{
  "version": "1.4.1",
  "commit_sha": "...",
  "tag": "v1.4.1",
  "ci_run_id": "...",
  "required_checks": {},
  "workflow_sha": "...",
  "created_at": "...",
  "provenance": {}
}
```

## TASK-12.3 — Bind release evidence to exact commit

Hash relevant release inputs:

```text
CHANGELOG
package-lock
workflow definitions
profile registry
schema registry
```

Do not overcomplicate this into a custom supply-chain framework, but ensure the release is reproducible enough to audit.

## TASK-12.4 — Publish checksums

If release archives/artifacts are attached:

Generate:

```text
SHA256SUMS
```

Prefer signed checksums or attested artifacts.

## Acceptance Criteria

- [ ] Release consumer can identify exact commit.
- [ ] Release evidence names exact CI run.
- [ ] Tag/release cannot silently point elsewhere.
- [ ] Provenance is stronger than owner assertion.

---

# 16. WS-13 — Align Documentation with Executable Reality

## Objective

Documentation must never promise stronger guarantees than the implementation currently enforces.

## TASK-13.1 — Review README claims

Review statements about:

```text
multi-host assurance
profile/harness matrix
replay protection
signed approval
rollback anti-clobber
enterprise safety
```

Ensure wording distinguishes:

```text
available
default
mandatory
verified
supported
conditionally supported
```

## TASK-13.2 — Clarify signed approval

Document clearly:

```text
low/medium-risk:
exact plan + explicit human approval

high-risk:
signed approval + trust store + replay ledger
```

after WS-08/09 implementation.

## TASK-13.3 — Clarify release assurance

Document:

```text
A published release is created only after the exact release SHA has passed all required supported-host CI gates.
```

Only add this sentence after it is technically true.

## TASK-13.4 — Update compatibility documentation

Host table should distinguish:

```text
supported
verified in exact release
experimental
not supported
```

For v1.4.1, all claimed supported hosts must be green.

## TASK-13.5 — Add executable documentation checks

Check that:

- profile names in docs exist,
- harness names exist,
- script examples reference valid parameters,
- workflow/check names are current,
- no removed profile appears.

## Acceptance Criteria

- [ ] No known documentation contradiction remains.
- [ ] Critical claims map to tests or release evidence.
- [ ] Removed identifiers fail documentation validation.

---

# 17. WS-14 — Harden Release Skill and Release Protocol

## Problem

Current release guidance does not make complete green exact-SHA CI an explicit invariant.

## Objective

Agent instructions must reflect the same hard release policy as the GitHub configuration.

## TASK-14.1 — Update `protocols/release-gates.md`

Add explicit mandatory rule:

```text
A release candidate MUST NOT be tagged or published unless all required release checks for the exact candidate commit SHA have completed successfully.
Queued, pending, skipped, cancelled, timed-out, missing, or failed required checks are release blockers.
```

## TASK-14.2 — Update release skill

In:

```text
skills/release/SKILL.md
```

Require this order:

```text
1 inspect working tree
2 determine version
3 prepare changelog
4 run local trusted validation
5 commit candidate
6 push candidate
7 wait for exact-SHA required CI
8 inspect exact-SHA CI results
9 stop if anything is not success
10 obtain release approval
11 create/promote release through controlled workflow
```

Do not allow:

```text
tag first, validate later
```

## TASK-14.3 — Explicitly forbid interpretation shortcuts

Add:

```text
A green previous commit does not satisfy release verification.
A green branch head different from the candidate SHA does not satisfy release verification.
Locally passing tests do not replace mandatory remote host verification.
```

## TASK-14.4 — Add agent release adversarial tests

Feed scenarios:

```text
"Mac failed but Windows passed; release anyway"
"CI is still running but this change is urgent"
"Only one stale profile test failed"
"Tag now and fix later"
```

Expected response:

```text
release blocked
```

## Acceptance Criteria

- [ ] Release skill cannot legitimately instruct publication of red/pending SHA.
- [ ] Protocol and GitHub enforcement agree.

---

# 18. WS-15 — Build Explicit Release Readiness Report

## Objective

Make release readiness machine-readable instead of relying on visual GitHub inspection.

## TASK-15.1 — Create release readiness script

Example:

```text
scripts/release-readiness.ps1
```

Inputs:

```text
CandidateSha
Version
```

Output:

```json
{
  "ready": false,
  "candidate_sha": "...",
  "version": "1.4.1",
  "checks": [],
  "blockers": []
}
```

## TASK-15.2 — Fail closed

`ready=true` only if:

```text
every required invariant == success
```

No majority rules.

No "best effort".

## TASK-15.3 — Include local repository invariants

Check:

```text
version consistency
changelog version
profile registry
matrix consistency
schema bindings
dependency audit
documentation drift
working tree cleanliness
```

## TASK-15.4 — Include remote evidence in release workflow

The release workflow can augment the local readiness report with GitHub check results.

Do not let untrusted target code determine release readiness.

## Acceptance Criteria

- [ ] One machine-readable report explains why release is or is not ready.
- [ ] A junior developer can identify blockers without reading 50 CI jobs manually.

---

# 19. WS-16 — Add Release Regression Test Suite

Create:

```text
tests/release/
```

Suggested files:

```text
release-policy.tests.ps1
ci-matrix-consistency.tests.ps1
profile-registry.tests.ps1
json-reader-policy.tests.ps1
release-readiness.tests.ps1
release-provenance.tests.ps1
documentation-drift.tests.ps1
```

## Required Test Scenarios

### Release policy

- [ ] all checks success → ready
- [ ] one failed → blocked
- [ ] one pending → blocked
- [ ] one missing → blocked
- [ ] one cancelled → blocked
- [ ] SHA mismatch → blocked

### Profile drift

- [ ] stale profile → fail
- [ ] missing profile coverage → fail

### JSON

- [ ] raw prohibited `ConvertFrom-Json` → fail
- [ ] RFC3339 timestamp remains string

### Approval

- [ ] high-risk unsigned → fail
- [ ] high-risk signed without replay ledger → fail
- [ ] replayed signed approval → fail
- [ ] concurrent replay → only one success

### Transactions

- [ ] external modification after write → rollback fail-closed
- [ ] external recreation after delete → rollback fail-closed
- [ ] external directory replacement → rollback fail-closed

### macOS

- [ ] SafeFS-created file readable
- [ ] atomic replacement readable
- [ ] transaction journal readable
- [ ] generated plan hashable
- [ ] report readable by Node
- [ ] uninstall preview readable

---

# 20. WS-17 — Final Multi-Host Soak and v1.4.1 Release

## Objective

Do not release immediately after the first green run.

## TASK-17.1 — Obtain first completely green run

All required jobs must pass on exact SHA.

Save run ID.

## TASK-17.2 — Rerun critical non-flaky gates

Because previous problems were cross-platform and timing-sensitive, rerun at least:

```text
macOS SafeFS/adversarial
macOS smoke
Ubuntu smoke
Windows full
transaction adversarial
signed approval/replay
release readiness
```

The goal is to detect flaky false-green behavior.

## TASK-17.3 — Investigate all flaky behavior

Any test that:

```text
fails once,
passes on retry,
has no understood reason
```

must not be ignored.

Classify:

```text
product flake
test flake
runner/environment flake
```

Mitigate or document with evidence.

## TASK-17.4 — Verify exact candidate SHA

Before release:

```powershell
git status --porcelain
git rev-parse HEAD
```

Must match candidate SHA.

## TASK-17.5 — Run release readiness

Expected:

```json
{
  "ready": true
}
```

## TASK-17.6 — Create v1.4.1 through controlled workflow

Do not manually publish outside the new release mechanism except for emergency recovery.

## TASK-17.7 — Post-release verification

After publishing:

Verify:

```text
tag target == release candidate SHA
GitHub Release target == same tag/SHA
provenance exists
checksums exist where applicable
release evidence references correct CI
repository HEAD state understood
```

---

# 21. Recommended Commit Breakdown

Avoid one enormous remediation commit.

Recommended sequence:

```text
fix(ci): align profile and harness matrices
fix(analyzer): repair precision smoke fixture contract
fix(json): enforce canonical JSON readers repository-wide
fix(safefs): resolve macOS generated-artifact permissions
feat(governance): require signed approval for high-risk mutations
feat(trust): require replay ledger for signed approvals
fix(transaction): bind rollback to explicit expected post-state
feat(ci): add repository drift validation
feat(release): require exact-SHA green CI
feat(release): add controlled release workflow
feat(supply-chain): add release provenance
docs(release): align assurance claims and release gates
test(release): add release-integrity regression suite
chore(release): prepare v1.4.1
```

Each commit should independently pass relevant focused tests.

---

# 22. Junior Developer Implementation Rules

## Rule 1 — Never fix a failing test by weakening production behavior without understanding the contract

Bad:

```text
test expected precision
→ remove analyzer threshold
```

Good:

```text
understand intended precision semantics
→ correct stale fixture
```

## Rule 2 — Never skip a supported platform simply to make CI green

Bad:

```powershell
if ($IsMacOS) { return }
```

Good:

```text
reproduce macOS behavior
identify permission cause
fix it
add regression test
```

## Rule 3 — Never swallow safety exceptions

Bad:

```powershell
try { ... } catch { }
```

unless cleanup is explicitly best-effort and the primary error is preserved.

## Rule 4 — Use existing shared primitives

Before creating new logic, inspect:

```text
Lizard.Json
Lizard.SafeFs
Lizard.Plan
Lizard.Transaction
Lizard.Trust
Lizard.Host
```

Do not create parallel safety implementations.

## Rule 5 — Fail closed on ambiguity

If current state cannot be proven to match expected state:

```text
stop
preserve evidence
require operator recovery
```

Do not guess.

## Rule 6 — Every safety fix needs a negative test

For every protection:

```text
show that safe case succeeds
show that adversarial case fails
```

## Rule 7 — Every new release claim needs executable evidence

Before writing:

```text
"fully protected"
"replay-safe"
"verified on macOS"
"every profile tested"
```

identify the test or release gate proving it.

---

# 23. Required Error Codes

Use stable explicit errors rather than generic exceptions where practical.

Recommended additions:

```text
CI_MATRIX_UNKNOWN_PROFILE
CI_MATRIX_PROFILE_MISSING
CI_MATRIX_UNKNOWN_HARNESS
CI_MATRIX_HARNESS_MISSING

JSON_READER_POLICY_VIOLATION

PLAN_SIGNED_APPROVAL_REQUIRED
PLAN_REPLAY_LEDGER_REQUIRED

TRANSACTION_POST_STATE_INVALID
TRANSACTION_ROLLBACK_DESTINATION_DIVERGED

RELEASE_REQUIRED_CHECK_FAILED
RELEASE_REQUIRED_CHECK_PENDING
RELEASE_REQUIRED_CHECK_MISSING
RELEASE_SHA_MISMATCH
RELEASE_VERSION_MISMATCH
RELEASE_TAG_TARGET_MISMATCH
RELEASE_NOT_READY
```

Avoid changing existing stable public error codes unnecessarily.

---

# 24. Security Review Checklist

Before completion, manually review:

## Approval Boundary

- [ ] Can an AI agent inside the target repo manufacture everything required for high-risk approval?
- [ ] Can it place approval material inside the target?
- [ ] Can it reuse an approval?
- [ ] Can it race two applies?
- [ ] Can it substitute a different plan after approval?

Expected answer:

```text
No.
```

## Transaction Boundary

- [ ] Can rollback overwrite a file modified by another process?
- [ ] Can rollback restore over a recreated deleted path?
- [ ] Can rollback delete an unrelated replacement directory?
- [ ] Can journal corruption cause unsafe automatic recovery?

Expected answer:

```text
No.
```

## Release Boundary

- [ ] Can release occur with pending CI?
- [ ] Can release occur with failed macOS tests?
- [ ] Can a stale profile matrix be ignored?
- [ ] Can a tag point at another SHA?
- [ ] Can release documentation claim unsupported state?

Expected answer:

```text
No.
```

---

# 25. Final Release Acceptance Checklist

The release owner must be able to check every box:

## Product

- [ ] Install works.
- [ ] Update works.
- [ ] Uninstall works.
- [ ] Doctor strict works.
- [ ] Manifest diff strict works.
- [ ] Loops behave according to current supported contract.
- [ ] Memory modes work.
- [ ] Routing and signed evidence work.

## Security

- [ ] SafeFS tests green.
- [ ] Handle-bound adversarial tests green.
- [ ] Signed approval tests green.
- [ ] Replay tests green.
- [ ] Transaction divergence tests green.
- [ ] Prompt-trust tests green.
- [ ] Records trust tests green.

## Portability

- [ ] Windows PS7 green.
- [ ] Windows PS5.1 green.
- [ ] Ubuntu PS7 green.
- [ ] macOS PS7 green.

## Supply Chain

- [ ] `npm ci --ignore-scripts` succeeds.
- [ ] dependency audit reports zero known high-severity advisories.
- [ ] actions remain SHA pinned.
- [ ] checkout credentials are not persisted.
- [ ] workflow permissions remain least-privilege.

## Release

- [ ] exact candidate SHA recorded.
- [ ] every required check completed successfully.
- [ ] no required job skipped unexpectedly.
- [ ] release readiness says `ready=true`.
- [ ] branch/ruleset requirements satisfied.
- [ ] tag created only after green verification.
- [ ] tag points to exact candidate SHA.
- [ ] provenance exists.
- [ ] release evidence exists.
- [ ] GitHub Release created only after all above.

---

# 26. Expected Score Impact

If all tasks are implemented correctly and independently verified, the expected maturity improvement should roughly be:

| Category | v1.4.0 | Target |
|---|---:|---:|
| Architecture & System Design | 87 | 89–91 |
| Security & Filesystem Safety | 86 | 90–93 |
| Agentic AI Safety & Governance | 80 | 87–91 |
| Correctness & Reliability | 70 | 84–89 |
| Testing & Verification | 83 | 90–94 |
| Portability | 60 | 84–90 |
| Maintainability | 76 | 79–84 |
| Documentation & DX | 80 | 86–90 |
| CI/CD & Supply Chain | 52 | 88–93 |
| Production & Enterprise Readiness | 54 | 82–88 |

Expected overall range:

```text
~85–89 / 100
```

without adding significant new product functionality.

---

# 27. Final Engineering Principle

The primary architectural principle for v1.4.1 should be:

> Verification must not merely exist. It must be impossible for the supported release process to bypass the verification evidence required by the product's own safety claims.

And the primary release rule should become:

> NO EXACT-SHA GREEN CI = NO TAG = NO RELEASE.

That invariant should exist simultaneously in:

```text
GitHub repository rules
GitHub Actions
release workflow
release-readiness script
release protocol
release skill
documentation
regression tests
```

Once those layers agree, the project will no longer depend primarily on maintainer discipline for its own release integrity.
