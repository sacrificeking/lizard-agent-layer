# ADR 0019: Authenticated evidence trust

- Status: Accepted
- Date: 2026-08-22

## Context

Routing, execution, calibration, worktree lifecycle, and verifier evidence previously used target-local identity strings and unkeyed hashes. Those checks detected accidental inconsistency but could not authenticate a principal, reject a handcrafted PASS, consult external revocation state, or stop nonce replay.

## Decision

Evidence that can authorize execution or completion uses a version-2 `signed-evidence` envelope:

- RSA PKCS#1 v1.5 with SHA-256 (`RS256`) signs canonical metadata and the canonical payload SHA-256.
- The signer is identified by organization, issuer, key, and principal IDs from a separately supplied trust store whose exact file digest is required.
- A separately supplied, exact-digest challenge binds purpose, subject, payload kind, operation/decision inputs, external approval reference, a random nonce, and a short validity interval.
- Private JWKs, trust stores, challenges, and replay ledgers remain outside target projects. They are never installed or copied into `.agent`.
- Consumers recompute payload and context hashes, validate signature, role, time, challenge, key status, revocation, and principal relationships before using evidence.
- L2 completion consumes verifier envelope IDs and challenge nonces in an external replay ledger before mutating runtime state.

The authenticated roles are `implementer` for registered worktree lifecycle, `verifier` for PASS evidence, `router` for persisted route decisions, `runtime` for actual-model execution receipts, and `evaluator` for calibration evidence. Implementer and verifier principals must differ. Runtime-reported model/provider IDs are inside the runtime-signed payload. Evaluation scores and case evidence hashes are inside the evaluator-signed payload and the challenge-bound case-set hash.

Preview route decisions and non-authorizing diagnostic output may remain unsigned. Persisted executable route decisions, execution receipts, CREATED lifecycle evidence, verifier verdicts, and accepted calibration input may not.

## Consequences

- Existing unsigned persisted evidence is not accepted by the new authorization paths and must be regenerated.
- Key custody, approval issuance, trust-store publication, and revocation are organization responsibilities. Repository schemas are structural contracts, not authority.
- Trust inputs are digest pinned and external; copying them into a target invalidates the intended trust boundary.
- `RS256` is selected for PowerShell 5.1 and current PowerShell compatibility. A later algorithm migration requires a new envelope version.
- Rich verification remains constrained by ADR 0018; a valid signature cannot authorize an unrepresentable shell command.
