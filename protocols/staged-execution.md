# Staged Execution Protocol

Use the installed policy as a work-shaping protocol, not as a promise that an IDE can change models.

## Portable default

1. Accept the user's ordinary task prompt and apply the stages internally; do not require routing terminology or a separate launcher command.
2. Keep the model already active in the current harness for strategy, execution, and verification.
3. Spend roughly 10% on strategy, 80% on execution, and 10% on verification. These are guidance bands, not token accounting.
4. Do not pause work to ask the user to operate a model picker.
5. Treat route roles such as `strategist`, `standardExecutor`, and `verifier` as internal responsibilities, not user-facing setup choices or provider names.
6. Verify in a fresh review pass with the original acceptance criteria and changed files in view.

## Advanced inventory routing

Use a concrete model only when the target explicitly sets `modelMode` to `inventory-routing` and provides both `.agent/routing/runtime.json` and `.agent/routing/inventory.json`.

- The harness must support automatic per-call or subagent selection. Advisory-only switching is not sufficient.
- The runtime must cover every installed harness and report actual model identity after execution.
- A candidate must be available, approved, data-compatible, capability-compatible, calibrated for the requested role, and bound to the current runtime fingerprint.
- `uncalibrated`, expired, and rejected models are ineligible even when their declared scores look strong.
- Provider diversity during verification is a preference, never a reason to interrupt the user.
- Treat a route decision as a recommendation. Only the attesting executor records a separate actual-execution receipt.
- Record only routing metadata. Never store raw prompts, secrets, or private logs in receipts.

If any Advanced precondition is missing, fail closed for inventory routing and use the portable `inherit-current` profile instead of pretending a switch occurred.
