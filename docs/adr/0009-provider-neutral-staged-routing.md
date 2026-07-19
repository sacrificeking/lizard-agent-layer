# ADR 0009: Provider-Neutral Staged Execution

- Status: Accepted
- Date: 2026-07-19

## Context

The 10-80-10 idea describes how work is divided into strategy, execution, and verification. It does not imply that an IDE can discover or change models while a task is running. Generic repository instructions cannot reliably inspect a user's model entitlements, operate every IDE model picker, or attest which model actually executed a phase. Hard-coded model catalogs become stale and can turn a useful workflow into fragile ceremony.

## Decision

The portable default is `modelMode: inherit-current`. The model already selected in the active harness completes all three phases. Logical route roles describe responsibilities, never providers. Agents must not interrupt a task to ask a user to change a model picker. Verification defaults to a fresh self-review pass against acceptance criteria and evidence.

Concrete routing is an explicit Advanced mode named `inventory-routing`. Its target-local inventory may contain any provider or model identifier, but selection is allowed only when:

- a separate, non-expired runtime capability document attests automatic per-call or subagent selection and actual-model reporting for every installed harness;
- availability and approval are declared;
- data and required capabilities match;
- role evaluation evidence is `calibrated`, non-expired, and bound to the runtime configuration fingerprint; and
- every policy route and data class has an eligible candidate or fallback.

Unknown and future models begin `uncalibrated` and are ineligible. Different-model or different-provider verification is preferred where available, not required. Missing Advanced preconditions fail closed and direct the operator back to an `inherit-current` profile; they never create a manual mid-task switch request.

Route decisions and execution receipts are separate contracts. A route decision recommends a model but never proves a switch. Only an external executor that reports the actual model may write an execution receipt, and it must match the decision's executor, fingerprint, harness, model, and provider. Both are metadata-only, require explicit apply, remain private by default, and contain no raw prompts, secrets, chain of thought, or private source excerpts. Existing target files remain user-owned and are not clobbered.

## Consequences

The default works unchanged in VS Code, IntelliJ, Copilot, Codex, Claude, Gemini, DeepSeek, local tools, and future harnesses. A single-model installation receives the complete staged workflow. Organizations with a real routing API can add runtime capability, calibrated inventory data, and execution attestation without changing the portable policy. The layer intentionally ships no fake universal IDE switcher and refuses to present a recommendation as an executed switch.
