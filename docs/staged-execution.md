# Provider-Neutral Staged Execution

`lizard-agent-layer` treats 10-80-10 as a workflow:

- strategy: roughly 10% for outcome, constraints, plan, risks, and success criteria;
- execution: roughly 80% for implementation and bounded iteration;
- verification: roughly 10% for a fresh review and risk-proportionate checks.

The percentages are guidance, not token quotas. High-risk work may need a larger strategy or verification share.

## What happens in an IDE

The built-in profiles use `modelMode: inherit-current`. If a user starts a task in VS Code, IntelliJ, Copilot, Codex, Claude, Gemini, DeepSeek, a local tool, or another harness, the selected model completes all phases. The agent does not stop and ask the user to change a picker.

For normal daily use, the user does nothing special: submit the ordinary task such as “implement this validation” and keep working. The installed harness instructions tell the agent to perform strategy, execution, and verification internally. The agent should surface a plan, safety gate, or verification result only when useful; it must not make the user operate the routing scripts or understand role names.

The router chooses a logical responsibility such as `strategist`, `standardExecutor`, or `verifier`. It does not claim to know the active provider or model:

```json
{
  "model_mode": "inherit-current",
  "selected_role": "standardExecutor",
  "recommended_model": null,
  "recommended_provider": null,
  "model_switch_required": false
}
```

Verification is a fresh self-review pass by default. A different context, model, provider, agent, or human can strengthen verification when the harness already supports it, but is not required for the portable workflow.

## Installed artifacts

```text
.agent/
  routing/
    policy.json
    receipts/
      decisions/              # recommendations, not execution proof
      executions/             # runtime-attested actual executions
  protocols/
    staged-execution.md
    context-hygiene.md
  skills/
    staged-execution/SKILL.md
```

No model inventory is generated. The layer cannot infer a user's entitlements from repository files and must not fabricate availability.

## Diagnose or audit a phase

`route-task.ps1` is an administrator/developer diagnostic and audit helper, not the way an ordinary user starts a task. It previews one phase and explains the next action:

```powershell
pwsh -NoProfile -File .\scripts\route-task.ps1 `
  -TargetPath D:\path\to\project `
  -Phase execution `
  -TaskClass implementation `
  -RiskLevel medium `
  -DataClass internal-code `
  -Json
```

Preview is the default. `-Apply` writes only a metadata receipt under `.agent/routing/receipts/`. Receipts never include raw prompts, chain of thought, source excerpts, secrets, or private logs.

## Advanced automatic routing

Use `inventory-routing` only when the harness can select a model automatically per call or subagent:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -TargetPath D:\path\to\project `
  -Profile standard `
  -ModelMode inventory-routing `
  -WritePlan
```

The target must supply two target-owned, gitignored files before preview can succeed:

- `.agent/routing/runtime.json` proves that an external executor can discover/select models automatically, report the actual executed model, and cover every installed harness. Its contract is `schemas/routing-runtime.schema.json`.
- `.agent/routing/inventory.json` contains arbitrary provider/model IDs, approval, data policy, capabilities, cost, reasoning mappings, and evaluation evidence. Its contract is `schemas/model-inventory.schema.json`.

The inventory does not claim that a switch can be executed. That claim belongs only to the runtime capability document. Ordinary IDE users should not maintain either file manually; an organization adapter or routing runtime should discover entitlements and write them. This repository ships the contracts and safe orchestration, but no universal VS Code, IntelliJ, Copilot, Claude, Gemini, Codex, DeepSeek, or vendor-specific executor.

Only non-expired evidence with state `calibrated`, an evaluation suite, timestamp, matching `configuration_fingerprint`, and a role score at or above the policy threshold is eligible. The installer and doctor require coverage for every policy route and data class. New models begin `uncalibrated` regardless of declared scores.

Promote evaluated models preview-first:

```powershell
pwsh -NoProfile -File .\scripts\calibrate-model.ps1 `
  -TargetPath D:\path\to\project `
  -EvaluationPath D:\evidence\model-evaluation.json `
  -Json

pwsh -NoProfile -File .\scripts\calibrate-model.ps1 `
  -TargetPath D:\path\to\project `
  -EvaluationPath D:\evidence\model-evaluation.json `
  -Apply
```

The evaluation must satisfy `schemas/model-evaluation.schema.json`, contain passed cases and evidence hashes, and match the runtime executor and fingerprint. Recalibrate after a material model, harness, system-prompt, tool, or policy change.

`route-task.ps1 -Apply` writes a route decision under `receipts/decisions`; it never proves that a model ran. After execution, the external attesting runtime calls `record-execution.ps1` with the actual identity. That writes a distinct execution receipt under `receipts/executions` and rejects an executor, fingerprint, harness, or model mismatch.

Advanced routing fails closed when the inventory is missing, automatic selection is unavailable, or no calibrated candidate satisfies the route. The user should then keep an `inherit-current` profile; the workflow never turns failure into a manual mid-task picker request.

## Safety rules

- Secrets are blocked before routing.
- Human-review signals stop execution.
- Strategy signals return work to the strategy phase.
- Receipt paths cannot escape `.agent/routing/receipts/`.
- Different-model and provider-diverse verification are preferences, not hidden requirements.
- `observed` and `attested` describe how strongly the runtime knows the actual identity; a route decision must never be presented as execution proof.
- Legacy `modelProfiles` remain readable for compatibility but are deprecated and are not part of the Advanced execution contract.
