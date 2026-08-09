# Remediation Claim Ledger

Status vocabulary: `OPEN_CONFIRMED`, `OPEN_CHANGED`, `ALREADY_FIXED_UNVERIFIED`, `CLOSED_WITH_EVIDENCE`, `SUPERSEDED`, and `NOT_REPRODUCIBLE`.

The baseline is commit `1797097d8a1c5ab5444ac82e83786ac1ccc841f6`. A finding is closed only when its complete measurable exit condition has executable evidence on every claimed host.

| ID | Current status | Current evidence or change | Evidence still required for closure |
| --- | --- | --- | --- |
| H-01 | `OPEN_CHANGED` | WP-03 requires canonical immutable install/update plans, independently supplied SHA-256 values, explicit human approval, actual Git-HEAD and executed-source binding, rederived target action/ownership/intended hashes, nested update/install binding, pre-lock checks, post-lock/pre-mutation revalidation, and applied-plan receipts; local Windows PowerShell 5.1 evidence passes 18/18 focused suites, smoke, 18/18 profile/harness combinations, and all nine full-CI gates (`.tmp/ci/ci-report-20260802091602.json`) | Independent PowerShell 7 and Unix verification of the full source/overlay/inventory/runtime/target/CLI drift matrix; authenticated approver identity remains H-09 and physical race resistance remains H-03 |
| H-02 | `OPEN_CHANGED` | WP-02 adds strict v2 validation, lock/journal/root binding, canonical backups, immediate rollback checkpoints, stop-first-error replay, retry skipping, and terminal cleanup; the focused hostile/crash suite passes locally | Authenticated evidence boundary for target-local forgery (H-09), v1 migration decision, and supported-host matrix |
| H-03 | `OPEN_CHANGED` | WP-01A adds protected read/metadata/hash primitives and migrates loop-evidence reads. WP-01B adds fail-closed current-namespace Unix mount identity enforcement: Linux distinguishes same-device bind mounts from cross-device mounts through mount ID and device identity; macOS combines mounted-root and device identity. Synthetic policy, 20/20 focused suites, smoke, 18/18 profile/harness combinations, governance, drift, documentation, and public-readiness gates pass locally | Actual privileged Ubuntu bind/`tmpfs` CI execution, macOS runtime evidence, terminal links on all claimed hosts, and WP-01C handle-bound/TOCTOU mutation evidence |
| H-04 | `OPEN_CHANGED` | WP-04 manifest v4 retains deselected records as plan-bound `retired-present` or `retired-missing` evidence without deletion, preserves ownership and installed identity, supports idempotent contraction/reactivation, and has local Windows PowerShell 5.1 lifecycle, strict-reader, smoke, and 18/18 profile/harness evidence | WP-05 executable canonical-plan-bound transactional uninstall, including reversible/resumable/idempotent deletion, reappeared paths, interruption recovery, deletion receipts, and supported-host evidence |
| H-05 | `OPEN_CONFIRMED` | Memory artifacts and adapter references remain unconditional | Full `curated`, `private-episodic`, and `off` lifecycle matrix |
| H-06 | `OPEN_CONFIRMED` | Regulated data alone does not force organization-owned approval | Missing, stale, revoked and mismatched approval matrix |
| H-07 | `OPEN_CONFIRMED` | Free-form durable fields remain beside hard-coded privacy labels | Shared serializer and secret/personal-data canaries across every output channel |
| H-08 | `OPEN_CONFIRMED` | Target prose and arbitrary verifier command strings remain unconstrained | Prompt-trust and constrained-runner hostile fixtures |
| H-09 | `OPEN_CONFIRMED` | Evidence identity and attestation remain self-asserted | Approved trust model plus forgery, replay, principal and revocation tests |
| M-01 | `OPEN_CONFIRMED` | Analyzer has not yet adopted the protected traversal/read contract | Linked-target, calibration and deterministic-order matrix |
| M-02 | `OPEN_CONFIRMED` | Generated plans still hard-code Windows PowerShell | Emitted-command tests on every supported host |
| M-03 | `OPEN_CONFIRMED` | Skill version, permission, dependency, migration and removal contracts remain incomplete | Executable end-to-end skill lifecycle |
| M-04 | `OPEN_CONFIRMED` | No general retention, legal-hold, purge or deletion-receipt lifecycle exists | Boundary-time, hold, export, purge, interruption and deletion evidence |
| M-05 | `OPEN_CHANGED` | Doctor now deterministically classifies active, recovery-required, cleanup-required, invalid, and orphan transaction metadata | Target-local report residue and cross-command lifecycle consistency tests |
| M-06 | `OPEN_CONFIRMED` | CI still installs without `--ignore-scripts` | Lifecycle-script canary and hardened workflow assertions |
| M-07 | `OPEN_CONFIRMED` | Sensitive metadata lacks consistent sensitivity and retention fields | Cross-artifact metadata/redaction canaries |
| M-08 | `OPEN_CONFIRMED` | Repository protocols do not constrain the IDE or agent host | External host-enforcement evidence or narrower documented claims |
| L-01 | `OPEN_CONFIRMED` | Git refs remain inconsistently validated against option confusion | Invalid/option-like ref and base-reference negative tests |

## Supported WP-01A claims

The following narrow claims are supported locally on Windows PowerShell 5.1:

- Ordinary contained files can be read and hashed through the shared safe-filesystem module.
- Existing linked ancestors are rejected before loop evidence metadata or hashes are accepted.
- A linked evidence failure cannot replace an already sealed verifier packet.

These claims do not imply mount-aware containment, race-free mutation, sandboxing, Unix assurance, or full H-03 closure.

## Supported WP-01B claims

The following narrow claims are supported by local Windows PowerShell 5.1 policy and regression evidence:

- Strict synthetic Linux mountinfo records distinguish a nested same-device mount ID from a cross-device mount and reject both with stable `SAFEFS_*` codes.
- Synthetic macOS mounted-root/device records apply the same fail-closed nested-boundary policy.
- SafeFs invokes the mount-boundary guard before returning a resolved target or authorized root, while Windows takes the non-mount path.
- The Ubuntu workflow contains an explicitly enabled, cleanup-enforcing bind-mount and `tmpfs` fixture before the longer CI gates.

These claims do not assert that the privileged Ubuntu fixture or macOS runtime enumeration has executed. They also do not eliminate a synchronized mount, link, or ancestor swap after validation; that remains WP-01C scope.
