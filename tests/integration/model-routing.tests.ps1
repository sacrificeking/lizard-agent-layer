param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Manifest.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("staged-execution-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$advancedTarget = Join-Path $fixture 'advanced-target'
$missingInventoryTarget = Join-Path $fixture 'missing-inventory-target'
$missingRuntimeTarget = Join-Path $fixture 'missing-runtime-target'
$canaryTarget = Join-Path $fixture 'canary-target'
$installScript = Join-Path $LayerRoot 'scripts\install.ps1'
$routeScript = Join-Path $LayerRoot 'scripts\route-task.ps1'
$recordExecutionScript = Join-Path $LayerRoot 'scripts\record-execution.ps1'
$calibrateModelScript = Join-Path $LayerRoot 'scripts\calibrate-model.ps1'
$doctorScript = Join-Path $LayerRoot 'scripts\doctor.ps1'
foreach ($path in @($target, $advancedTarget, $missingInventoryTarget, $missingRuntimeTarget, $canaryTarget)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }

function Invoke-Route {
  param([string]$Root, [string[]]$Arguments)
  $result = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments (@('-TargetPath', $Root, '-Json') + $Arguments)
  Assert-Equal 0 $result.exit_code "Route command failed: $($result.output)"
  return ($result.output | ConvertFrom-Json)
}

try {
  $preview = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $target, '-Profile', 'standard', '-Harnesses', 'codex')
  Assert-Equal 0 $preview.exit_code 'Staged execution install preview must succeed.'
  Assert-True ($preview.output -match 'Daily use: Submit normal task prompts; keep the current IDE model') 'Install preview must explain everyday use without routing jargon.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent')) 'Install preview must not mutate the target.'

  $apply = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $target, '-Profile', 'standard', '-Harnesses', 'codex', '-Apply')
  Assert-Equal 0 $apply.exit_code "Staged execution install apply must succeed: $($apply.output)"
  foreach ($relative in @(
    '.agent\routing\policy.json',
    '.agent\protocols\staged-execution.md',
    '.agent\protocols\context-hygiene.md',
    '.agent\skills\staged-execution\SKILL.md'
  )) { Assert-True (Test-Path -LiteralPath (Join-Path $target $relative)) "Expected installed staged execution artifact $relative." }
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent\routing\models')) 'Portable install must not create a stale built-in model catalog.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent\routing\inventory.json')) 'Portable install must not fabricate model availability.'

  $manifestPath = Join-Path $target '.agent\lizard-agent-layer.install.json'
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  Assert-Equal 'staged-balanced' ([string]$manifest.routing_policy) 'Manifest must record the staged execution policy.'
  Assert-Equal 'inherit-current' ([string]$manifest.model_mode) 'Portable manifest must inherit the active model.'
  Assert-Equal 0 @($manifest.routing_models).Count 'Portable manifest must not claim installed models.'
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/install-manifest.schema.json' -InstancePath $manifestPath -Message 'Staged execution install manifest must satisfy schema.'
  $portableDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $target, '-Strict')
  Assert-Equal 0 $portableDoctor.exit_code "Portable staged execution doctor must pass: $($portableDoctor.output)"

  $policyPath = Join-Path $target '.agent\routing\policy.json'
  $policyHash = Get-LizardSha256 $policyPath
  $rerun = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $target, '-Profile', 'standard', '-Harnesses', 'codex', '-Apply')
  Assert-Equal 0 $rerun.exit_code 'Staged execution install rerun must succeed.'
  Assert-Equal $policyHash (Get-LizardSha256 $policyPath) 'Staged execution install rerun must be idempotent.'

  $strategy = Invoke-Route -Root $target -Arguments @('-Phase', 'strategy', '-TaskClass', 'architecture', '-RiskLevel', 'medium', '-DataClass', 'internal-code', '-ReceiptId', 'strategy')
  Assert-Equal 'route' ([string]$strategy.decision) 'Strategy must route.'
  Assert-Equal 'strategist' ([string]$strategy.selected_role) 'Strategy must expose a logical responsibility.'
  Assert-True ($null -eq $strategy.recommended_model) 'Portable strategy must not invent a model identity.'

  foreach ($case in @(
    @{ task = 'implementation'; role = 'standardExecutor'; id = 'standard' },
    @{ task = 'formatting'; role = 'bulkExecutor'; id = 'bulk' },
    @{ task = 'research'; role = 'researchExecutor'; id = 'research' }
  )) {
    $route = Invoke-Route -Root $target -Arguments @('-Phase', 'execution', '-TaskClass', $case.task, '-RiskLevel', 'medium', '-DataClass', 'internal-code', '-ReceiptId', $case.id)
    Assert-Equal 'inherit-current' ([string]$route.model_mode) 'Portable route must inherit the current model.'
    Assert-Equal $case.role ([string]$route.selected_role) 'Portable route must select the expected logical role.'
    Assert-True ($null -eq $route.recommended_provider) 'Portable route must remain provider-neutral.'
    Assert-Equal $false ([bool]$route.model_switch_required) 'Portable route must never require a model picker interruption.'
  }

  $verification = Invoke-Route -Root $target -Arguments @('-Phase', 'verification', '-TaskClass', 'implementation', '-RiskLevel', 'high', '-DataClass', 'internal-code', '-PreviousModel', 'anything', '-PreviousProvider', 'anything', '-ReceiptId', 'verification')
  Assert-Equal 'self-review' ([string]$verification.verification_mode) 'Portable verification must use a fresh self-review pass.'
  Assert-True ($null -eq $verification.recommended_model) 'Portable verification must not claim an independent model.'

  $escalated = Invoke-Route -Root $target -Arguments @('-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'medium', '-DataClass', 'internal-code', '-Signals', 'plan-deviation', '-ReceiptId', 'escalated')
  Assert-Equal 'strategy' ([string]$escalated.phase) 'Plan deviation must return work to strategy.'
  Assert-Equal 'strategist' ([string]$escalated.selected_role) 'Strategy escalation must expose the strategist responsibility.'

  $human = Invoke-Route -Root $target -Arguments @('-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'high', '-DataClass', 'internal-code', '-Signals', 'uncertain-ownership', '-ReceiptId', 'human')
  Assert-Equal 'human-review' ([string]$human.decision) 'Human-review signals must stop automatic execution.'
  Assert-True ($null -eq $human.recommended_model) 'Human-review stop must not recommend a model.'

  $friendlyReady = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments @('-TargetPath', $target, '-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'medium', '-DataClass', 'internal-code')
  Assert-Equal 0 $friendlyReady.exit_code "Friendly portable route must succeed: $($friendlyReady.output)"
  Assert-True ($friendlyReady.output -match 'Routing result: READY') 'Human-readable routing must lead with a clear ready state.'
  Assert-True ($friendlyReady.output -match 'No model-picker change is needed') 'Human-readable portable routing must give a no-switch next action.'
  Assert-False ($friendlyReady.output -match 'Re-run with -Apply') 'Human-readable routing must not imply that an audit receipt is required.'

  $friendlyHuman = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments @('-TargetPath', $target, '-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'high', '-DataClass', 'internal-code', '-Signals', 'uncertain-ownership')
  Assert-True ($friendlyHuman.output -match 'PAUSE FOR HUMAN REVIEW') 'Human-review output must clearly tell a beginner to pause.'
  Assert-False ($friendlyHuman.output -match '(?m)^Model:') 'Human-review output must not display a model as though execution will continue.'

  $secrets = Invoke-Route -Root $target -Arguments @('-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'high', '-DataClass', 'secrets', '-ReceiptId', 'secrets')
  Assert-Equal 'block' ([string]$secrets.decision) 'Secrets must be blocked before staged execution.'
  $friendlyBlock = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments @('-TargetPath', $target, '-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'high', '-DataClass', 'secrets')
  Assert-True ($friendlyBlock.output -match 'Routing result: BLOCKED') 'Blocked output must clearly tell a beginner that execution stopped.'
  Assert-False ($friendlyBlock.output -match '(?m)^Model:') 'Blocked output must not display a model as though execution will continue.'

  $receipt = Invoke-Route -Root $target -Arguments @('-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'medium', '-DataClass', 'internal-code', '-ReceiptId', 'persisted', '-Apply')
  $receiptPath = Join-Path $target '.agent\routing\receipts\decisions\persisted.json'
  Assert-True (Test-Path -LiteralPath $receiptPath) 'Apply must write a metadata-only receipt.'
  Assert-Equal $false ([bool]$receipt.raw_prompt_stored) 'Receipts must never claim to store raw prompts.'
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/route-receipt.schema.json' -InstancePath $receiptPath -Message 'Persisted route receipt must satisfy schema.'

  $escape = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments @('-TargetPath', $target, '-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'medium', '-DataClass', 'internal-code', '-ReceiptId', 'escape', '-OutputPath', '..\escape.json', '-Apply')
  Assert-False ($escape.exit_code -eq 0) 'Receipt traversal outside the receipts root must fail.'

  $missingInventory = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $missingInventoryTarget, '-Profile', 'standard', '-ModelMode', 'inventory-routing')
  Assert-False ($missingInventory.exit_code -eq 0) 'Advanced install must fail closed when its target inventory is missing.'
  Assert-True ($missingInventory.output -match 'Recommended for normal IDE use') 'Missing Advanced configuration must explain the beginner-friendly fallback.'
  Assert-False (Test-Path -LiteralPath (Join-Path $missingInventoryTarget '.agent')) 'Failed Advanced preflight must not mutate the target.'

  $advancedRoutingRoot = Join-Path $advancedTarget '.agent\routing'
  New-Item -ItemType Directory -Path $advancedRoutingRoot -Force | Out-Null
  $inventoryPath = Join-Path $advancedRoutingRoot 'inventory.json'
  @'
{
  "schema_version": 1,
  "name": "arbitrary-vendor-fixture",
  "models": [
    {
      "id": "vendor-zeta/build-plus@2026-07", "provider": "vendor-zeta", "available": true, "approved": true,
      "capabilities": ["implementation", "independent-review"],
      "allowed_data_classes": ["public", "internal-code", "internal-docs", "confidential", "regulated"], "cost_tier": "balanced",
      "reasoning": { "light": "quick", "balanced": "normal", "deep": "careful", "maximum": null },
      "evidence": { "state": "calibrated", "suite": "fixture-v1", "evaluated_at": "2026-07-19T12:00:00Z", "expires_at": "2027-07-19T12:00:00Z", "configuration_fingerprint": "fixture-codex-config-v1", "role_scores": { "standardExecutor": 0.91, "verifier": 0.42 } }
    },
    {
      "id": "lab-alpha/think-x", "provider": "lab-alpha", "available": true, "approved": true,
      "capabilities": ["architecture", "task-decomposition", "deep-reasoning", "implementation", "research", "large-context", "independent-review"],
      "allowed_data_classes": ["public", "internal-code", "internal-docs", "confidential", "regulated"], "cost_tier": "premium",
      "reasoning": { "light": "1", "balanced": "2", "deep": "3", "maximum": "4" },
      "evidence": { "state": "calibrated", "suite": "fixture-v1", "evaluated_at": "2026-07-19T12:00:00Z", "expires_at": "2027-07-19T12:00:00Z", "configuration_fingerprint": "fixture-codex-config-v1", "role_scores": { "strategist": 0.93, "deepExecutor": 0.99, "standardExecutor": 0.72, "researchExecutor": 0.94, "verifier": 0.95 } }
    },
    {
      "id": "edge-runtime/mechanical", "provider": "edge-runtime", "available": true, "approved": true,
      "capabilities": ["mechanical-execution"],
      "allowed_data_classes": ["public", "internal-code", "internal-docs"], "cost_tier": "budget",
      "reasoning": { "light": "fast", "balanced": null, "deep": null, "maximum": null },
      "evidence": { "state": "calibrated", "suite": "fixture-v1", "evaluated_at": "2026-07-19T12:00:00Z", "expires_at": "2027-07-19T12:00:00Z", "configuration_fingerprint": "fixture-codex-config-v1", "role_scores": { "bulkExecutor": 0.9 } }
    },
    {
      "id": "future-provider/unseen-perfect", "provider": "future-provider", "available": true, "approved": true,
      "capabilities": ["implementation", "independent-review"],
      "allowed_data_classes": ["public", "internal-code"], "cost_tier": "local",
      "reasoning": { "light": "a", "balanced": "b", "deep": "c", "maximum": "d" },
      "evidence": { "state": "uncalibrated", "suite": null, "evaluated_at": null, "role_scores": { "standardExecutor": 1.0, "verifier": 1.0 } }
    },
    {
      "id": "wrong-runtime/misleading-perfect", "provider": "wrong-runtime", "available": true, "approved": true,
      "capabilities": ["implementation", "independent-review"],
      "allowed_data_classes": ["public", "internal-code"], "cost_tier": "local",
      "reasoning": { "light": "a", "balanced": "b", "deep": "c", "maximum": "d" },
      "evidence": { "state": "calibrated", "suite": "other-runtime-suite", "evaluated_at": "2026-07-19T12:00:00Z", "expires_at": "2027-07-19T12:00:00Z", "configuration_fingerprint": "different-runtime-config", "role_scores": { "standardExecutor": 1.0, "verifier": 1.0 } }
    },
    {
      "id": "expired-provider/old-perfect", "provider": "expired-provider", "available": true, "approved": true,
      "capabilities": ["implementation", "independent-review"],
      "allowed_data_classes": ["public", "internal-code"], "cost_tier": "local",
      "reasoning": { "light": "a", "balanced": "b", "deep": "c", "maximum": "d" },
      "evidence": { "state": "calibrated", "suite": "old-suite", "evaluated_at": "2025-01-01T00:00:00Z", "expires_at": "2025-02-01T00:00:00Z", "configuration_fingerprint": "fixture-codex-config-v1", "role_scores": { "standardExecutor": 1.0, "verifier": 1.0 } }
    }
  ]
}
'@ | Set-Content -LiteralPath $inventoryPath -Encoding UTF8
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/model-inventory.schema.json' -InstancePath $inventoryPath -Message 'Arbitrary-provider inventory must satisfy schema.'

  $missingRuntimeRoot = Join-Path $missingRuntimeTarget '.agent\routing'
  New-Item -ItemType Directory -Path $missingRuntimeRoot -Force | Out-Null
  Copy-Item -LiteralPath $inventoryPath -Destination (Join-Path $missingRuntimeRoot 'inventory.json')
  $missingRuntime = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $missingRuntimeTarget, '-Profile', 'standard', '-Harnesses', 'codex', '-ModelMode', 'inventory-routing')
  Assert-False ($missingRuntime.exit_code -eq 0) 'Advanced install must fail closed when runtime capability evidence is missing.'
  Assert-False (Test-Path -LiteralPath (Join-Path $missingRuntimeTarget '.agent\project-profile.json')) 'Missing runtime preflight must not install target artifacts.'

  $runtimePath = Join-Path $advancedRoutingRoot 'runtime.json'
  @'
{
  "schema_version": 1,
  "name": "fixture-codex-runtime",
  "executor_id": "fixture/codex-runtime-v1",
  "harnesses": ["codex"],
  "status": "ready",
  "discovery": "runtime-api",
  "selection": "per-call",
  "actual_model_reporting": true,
  "attestation": "observed",
  "capability_source": "fixture runtime API",
  "configuration_fingerprint": "fixture-codex-config-v1",
  "verified_at": "2026-07-19T12:00:00Z",
  "expires_at": "2027-07-19T12:00:00Z"
}
'@ | Set-Content -LiteralPath $runtimePath -Encoding UTF8
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/routing-runtime.schema.json' -InstancePath $runtimePath -Message 'Automatic runtime capability must satisfy schema.'
  $harnessMismatch = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $advancedTarget, '-Profile', 'standard', '-Harnesses', 'codex,gemini', '-ModelMode', 'inventory-routing')
  Assert-False ($harnessMismatch.exit_code -eq 0) 'Advanced install must require runtime coverage for every selected harness.'
  $advancedPreview = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $advancedTarget, '-Profile', 'standard', '-Harnesses', 'codex', '-ModelMode', 'inventory-routing')
  Assert-Equal 0 $advancedPreview.exit_code "Advanced inventory preview must succeed: $($advancedPreview.output)"
  Assert-False (Test-Path -LiteralPath (Join-Path $advancedTarget '.agent\project-profile.json')) 'Advanced preview must not install target artifacts.'
  $advancedInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $advancedTarget, '-Profile', 'standard', '-Harnesses', 'codex', '-ModelMode', 'inventory-routing', '-Apply')
  Assert-Equal 0 $advancedInstall.exit_code "Advanced inventory install must succeed: $($advancedInstall.output)"
  $advancedDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $advancedTarget, '-Strict')
  Assert-Equal 0 $advancedDoctor.exit_code "Advanced inventory doctor must pass: $($advancedDoctor.output)"

  $advanced = Invoke-Route -Root $advancedTarget -Arguments @('-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'medium', '-DataClass', 'internal-code', '-ReceiptId', 'advanced', '-Apply')
  Assert-Equal 'route-decision' ([string]$advanced.artifact_kind) 'Advanced routing output must identify itself as a decision, not execution proof.'
  Assert-Equal 'vendor-zeta/build-plus@2026-07' ([string]$advanced.recommended_model) 'Advanced routing must recommend by calibrated role evidence, not provider naming.'
  Assert-Equal 'per-call' ([string]$advanced.selection_capability) 'Advanced routing must require automatic execution capability.'
  Assert-Equal 'fixture/codex-runtime-v1' ([string]$advanced.runtime_executor) 'Route decisions must bind the automatic executor.'
  Assert-Equal 'fixture-codex-config-v1' ([string]$advanced.runtime_configuration_fingerprint) 'Route decisions must bind the runtime configuration.'
  Assert-Equal $false ([bool]$advanced.model_switch_required) 'Advanced routing must never become a manual picker request.'
  Assert-False ([string]$advanced.recommended_model -eq 'future-provider/unseen-perfect') 'Uncalibrated future models must remain ineligible.'
  Assert-False ([string]$advanced.recommended_model -eq 'expired-provider/old-perfect') 'Expired calibration evidence must remain ineligible.'
  Assert-False ([string]$advanced.recommended_model -eq 'wrong-runtime/misleading-perfect') 'Calibration from a different runtime configuration must remain ineligible.'

  $execution = Invoke-TestPowerShell -ScriptPath $recordExecutionScript -Arguments @(
    '-TargetPath', $advancedTarget,
    '-RouteDecisionId', 'advanced',
    '-ActualModel', 'vendor-zeta/build-plus@2026-07',
    '-ActualProvider', 'vendor-zeta',
    '-Harness', 'codex',
    '-StartedAt', '2026-07-19T12:00:00Z',
    '-CompletedAt', '2026-07-19T12:01:00Z',
    '-ReceiptId', 'advanced-execution',
    '-Outcome', 'succeeded',
    '-Apply', '-Json'
  )
  Assert-Equal 0 $execution.exit_code "Attesting runtime receipt must succeed: $($execution.output)"
  $executionDoc = $execution.output | ConvertFrom-Json
  Assert-Equal 'execution-receipt' ([string]$executionDoc.artifact_kind) 'Actual execution must be a separate receipt.'
  Assert-Equal 'vendor-zeta/build-plus@2026-07' ([string]$executionDoc.actual_model) 'Execution receipt must contain actual runtime identity.'
  Assert-Equal 'fixture-codex-config-v1' ([string]$executionDoc.configuration_fingerprint) 'Execution receipt must preserve the attested runtime configuration.'
  $executionPath = Join-Path $advancedTarget '.agent\routing\receipts\executions\advanced-execution.json'
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/execution-receipt.schema.json' -InstancePath $executionPath -Message 'Execution receipt must satisfy schema.'

  $mismatchExecution = Invoke-TestPowerShell -ScriptPath $recordExecutionScript -Arguments @('-TargetPath', $advancedTarget, '-RouteDecisionId', 'advanced', '-ActualModel', 'different/model', '-ActualProvider', 'vendor-zeta', '-Harness', 'codex', '-StartedAt', '2026-07-19T12:00:00Z', '-Apply')
  Assert-False ($mismatchExecution.exit_code -eq 0) 'Execution receipt must reject a model identity that differs from the route decision.'

  $advancedVerification = Invoke-Route -Root $advancedTarget -Arguments @('-Phase', 'verification', '-TaskClass', 'implementation', '-RiskLevel', 'high', '-DataClass', 'internal-code', '-PreviousModel', 'vendor-zeta/build-plus@2026-07', '-PreviousProvider', 'vendor-zeta', '-ReceiptId', 'advanced-verification')
  Assert-Equal 'lab-alpha/think-x' ([string]$advancedVerification.recommended_model) 'Calibrated independent verification should prefer a different model and provider.'
  Assert-Equal 'independent-model-preferred' ([string]$advancedVerification.verification_mode) 'A route decision may express an independent-model preference without claiming execution.'

  $evaluationPath = Join-Path $fixture 'future-model-evaluation.json'
  @'
{
  "schema_version": 1,
  "evaluation_id": "future-model-promotion",
  "model_id": "future-provider/unseen-perfect",
  "provider": "future-provider",
  "suite": "fixture-promotion-v1",
  "evaluated_at": "2026-07-19T12:30:00Z",
  "expires_at": "2027-07-19T12:30:00Z",
  "executor_id": "fixture/codex-runtime-v1",
  "configuration_fingerprint": "fixture-codex-config-v1",
  "attestation": "observed",
  "cases": [
    { "id": "standard-1", "role": "standardExecutor", "score": 0.80, "passed": true, "evidence_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
    { "id": "standard-2", "role": "standardExecutor", "score": 0.82, "passed": true, "evidence_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  ],
  "raw_prompts_stored": false
}
'@ | Set-Content -LiteralPath $evaluationPath -Encoding UTF8
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/model-evaluation.schema.json' -InstancePath $evaluationPath -Message 'Model promotion evaluation must satisfy schema.'
  $inventoryHashBeforeCalibration = Get-LizardSha256 $inventoryPath
  $calibrationPreview = Invoke-TestPowerShell -ScriptPath $calibrateModelScript -Arguments @('-TargetPath', $advancedTarget, '-EvaluationPath', $evaluationPath, '-Json')
  Assert-Equal 0 $calibrationPreview.exit_code "Calibration preview must succeed: $($calibrationPreview.output)"
  Assert-Equal $inventoryHashBeforeCalibration (Get-LizardSha256 $inventoryPath) 'Calibration preview must not mutate inventory evidence.'
  $calibrationApply = Invoke-TestPowerShell -ScriptPath $calibrateModelScript -Arguments @('-TargetPath', $advancedTarget, '-EvaluationPath', $evaluationPath, '-Apply', '-Json')
  Assert-Equal 0 $calibrationApply.exit_code "Calibration apply must succeed: $($calibrationApply.output)"
  $promotedInventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
  $promoted = @($promotedInventory.models | Where-Object { [string]$_.id -eq 'future-provider/unseen-perfect' })[0]
  Assert-Equal 'calibrated' ([string]$promoted.evidence.state) 'Attested evaluation must promote the matching inventory model.'
  Assert-Equal 0.81 ([double]$promoted.evidence.role_scores.standardExecutor) 'Calibration must derive the role score from evaluation cases.'
  Assert-Equal 'fixture-codex-config-v1' ([string]$promoted.evidence.configuration_fingerprint) 'Promoted evidence must bind to the runtime configuration.'
  Assert-True (Test-Path -LiteralPath (Join-Path $advancedRoutingRoot 'calibration\future-model-promotion.json')) 'Calibration apply must write a metadata-only audit record.'
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/model-inventory.schema.json' -InstancePath $inventoryPath -Message 'Promoted inventory must remain schema-valid.'

  $canaryPolicyRoot = Join-Path $canaryTarget '.agent\routing'
  New-Item -ItemType Directory -Path $canaryPolicyRoot -Force | Out-Null
  $canaryPolicyPath = Join-Path $canaryPolicyRoot 'policy.json'
  Set-Content -LiteralPath $canaryPolicyPath -Value '{"project":"owned-canary"}' -Encoding UTF8
  $canaryHash = Get-LizardSha256 $canaryPolicyPath
  $canaryInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $canaryTarget, '-Profile', 'minimal', '-Apply')
  Assert-Equal 0 $canaryInstall.exit_code 'Install with existing target routing policy must succeed.'
  Assert-Equal $canaryHash (Get-LizardSha256 $canaryPolicyPath) 'Installer must not clobber an existing target routing policy.'
  $canaryManifest = Get-Content -LiteralPath (Join-Path $canaryTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  $canaryArtifact = @($canaryManifest.artifacts | Where-Object { $_.path -eq '.agent/routing/policy.json' } | Select-Object -First 1)
  Assert-Equal 'user-owned' ([string]$canaryArtifact[0].ownership) 'Existing routing policy must remain user-owned.'

  Write-Host 'PASS staged execution and optional inventory routing integration tests'
} finally {
  Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot
}
