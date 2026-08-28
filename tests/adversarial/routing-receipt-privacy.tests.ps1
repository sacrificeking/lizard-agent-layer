param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeReport.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Trust.psm1') -Force
Import-Module (Join-Path $LayerRoot 'tests\TestTrustHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
$fixture = Join-Path $testRoot ("routing-receipt-privacy-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$routingRoot = Join-Path $target '.agent\routing'
$decisionRoot = Join-Path $routingRoot 'receipts\decisions'
$routeScript = Join-Path $LayerRoot 'scripts\route-task.ps1'
$executionScript = Join-Path $LayerRoot 'scripts\record-execution.ps1'

$canaries = @(
  'password=SuperSecretCanary-7788',
  'alice.customer@example.test',
  'C:\private\customer-7788.txt',
  'powershell -Command Get-SecretValue',
  "line-one`nline-two-private",
  'Kundennummer-äöü-7788',
  ('oversized-' + ('x' * 2100))
)

try {
  New-Item -ItemType Directory -Path $decisionRoot -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $LayerRoot 'routing-policies\staged-balanced.json') -Destination (Join-Path $routingRoot 'policy.json')
  Set-Content -LiteralPath (Join-Path $target '.agent\project-profile.json') -Value (([ordered]@{ profile = 'minimal'; routingPolicy = 'staged-balanced'; modelMode = 'inherit-current' }) | ConvertTo-Json -Depth 5)

  $probe = [ordered]@{
    artifact_kind = 'privacy-probe'
    sensitivity = 'metadata-only'
    purpose = 'test'
    audience = @('auditors')
    retention_class = 'ephemeral-test'
    content_policy = 'identifiers-only'
    report = $canaries
    journal = $canaries
    redaction = $null
  }
  $safe = Protect-LizardReportDocument -Document $probe
  $safeJson = $safe | ConvertTo-Json -Depth 8
  Assert-Equal 'applied' ([string]$safe.redaction.status) 'Shared report serializer must record deterministic redaction.'
  Assert-Equal 14 @($safe.redaction.fields).Count 'Every report and journal canary field must be recorded as redacted.'
  foreach ($canary in $canaries) { Assert-False ($safeJson.Contains($canary)) 'Serialized report/journal output must not contain a raw privacy canary.' }
  $safePath = Join-Path $fixture 'safe-report.json'
  Set-Content -LiteralPath $safePath -Value $safeJson
  $fileText = Get-Content -LiteralPath $safePath -Raw
  foreach ($canary in $canaries) { Assert-False ($fileText.Contains($canary)) 'Written safe-report file must not contain a raw privacy canary.' }

  foreach ($canary in $canaries) {
    $console = Protect-LizardConsoleText -Text $canary
    Assert-False ($console.Contains($canary)) 'Console protection must not return a raw privacy canary.'
  }

  $signalCanary = $canaries[0]
  $routeError = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments @('-TargetPath', $target, '-Signals', $signalCanary, '-DataClass', 'secrets', '-Apply', '-ReceiptId', 'invalid-signal', '-Json')
  Assert-False ($routeError.exit_code -eq 0) 'Free-form signal text must be rejected before a receipt is written.'
  Assert-True ($routeError.output -match 'ROUTE_SIGNAL_INVALID') 'Invalid signal rejection must use a stable error code.'
  Assert-False ($routeError.output.Contains($signalCanary)) 'Invalid signal error output must not echo the rejected value.'
  Assert-False (Test-Path -LiteralPath (Join-Path $decisionRoot 'invalid-signal.json')) 'Rejected signal must not create a receipt.'

  $evidenceCanary = $canaries[1]
  $executionError = Invoke-TestPowerShell -ScriptPath $executionScript -Arguments @('-TargetPath', $target, '-RouteDecisionId', 'missing', '-ActualModel', 'model-1', '-ActualProvider', 'provider-1', '-Harness', 'codex', '-StartedAt', '2026-08-22T10:00:00Z', '-EvidenceRef', $evidenceCanary, '-Json')
  Assert-False ($executionError.exit_code -eq 0) 'Free-form execution evidence text must be rejected.'
  Assert-True ($executionError.output -match 'EXECUTION_EVIDENCE_REF_INVALID') 'Invalid evidence rejection must use a stable error code.'
  Assert-False ($executionError.output.Contains($evidenceCanary)) 'Invalid evidence error output must not echo the rejected value.'

  $routeBase = @('-TargetPath', $target, '-Phase', 'execution', '-TaskClass', 'implementation', '-RiskLevel', 'medium', '-DataClass', 'internal-code', '-Signals', 'plan-deviation', '-ReceiptId', 'valid-metadata', '-RouterId', 'privacy-router', '-Json')
  $routePreview = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments $routeBase
  Assert-Equal 0 $routePreview.exit_code "Route trust preview failed: $($routePreview.output)"
  $routePreviewDoc = $routePreview.output | ConvertFrom-LizardJson
  $routeTrust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'route-trust') -BindingSha256 ([string]$routePreviewDoc.trust_binding_sha256) -Subject 'valid-metadata' -Now ([DateTimeOffset]::UtcNow) -PrincipalId 'privacy-router' -Roles @('router') -Purpose 'routing' -PayloadKind 'route-decision'
  $valid = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments ($routeBase + @('-Apply', '-TrustChallengePath', $routeTrust.challenge_path, '-TrustChallengeSha256', $routeTrust.challenge_sha256, '-RouterPrivateKeyPath', $routeTrust.private_key_path, '-RouterPrivateKeySha256', $routeTrust.private_key_sha256))
  Assert-Equal 0 $valid.exit_code "Valid enumerated signal route must succeed: $($valid.output)"
  $receipt = $valid.output | ConvertFrom-LizardJson
  Assert-Equal 'metadata-only' ([string]$receipt.sensitivity) 'Route receipt must carry typed sensitivity.'
  Assert-Equal 'route-decision-audit' ([string]$receipt.purpose) 'Route receipt must carry typed purpose.'
  Assert-Equal 'organization-policy-required' ([string]$receipt.retention_class) 'Route receipt must carry typed retention.'
  Assert-Equal 'identifiers-only' ([string]$receipt.content_policy) 'Route receipt must enforce identifier-only content.'
  Assert-Equal 'not-required' ([string]$receipt.redaction.status) 'Benign enumerated receipt must not require redaction.'

  $advancedTarget = Join-Path $fixture 'advanced-target'
  $advancedRouting = Join-Path $advancedTarget '.agent\routing'
  $advancedDecisions = Join-Path $advancedRouting 'receipts\decisions'
  $advancedExecutions = Join-Path $advancedRouting 'receipts\executions'
  New-Item -ItemType Directory -Path $advancedDecisions, $advancedExecutions -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $advancedTarget '.agent\project-profile.json') -Value (([ordered]@{ modelMode = 'inventory-routing'; modelRuntime = '.agent/routing/runtime.json' }) | ConvertTo-Json -Depth 5)
  $runtime = [ordered]@{
    status = 'ready'; selection = 'per-call'; actual_model_reporting = $true; attestation = 'observed'
    executor_id = 'privacy-runtime-v1'; configuration_fingerprint = 'privacy-runtime-v1'; capability_source = 'privacy-runtime-api'
    harnesses = @('codex'); expires_at = '2027-08-22T10:00:00Z'
  }
  Set-Content -LiteralPath (Join-Path $advancedRouting 'runtime.json') -Value ($runtime | ConvertTo-Json -Depth 5)
  $decision = [ordered]@{
    schema_version = 1; receipt_id = 'advanced-route'; router_id = 'privacy-runtime-v1'; request_sha256 = ('1' * 64); policy_sha256 = ('2' * 64); runtime_source_sha256 = ('3' * 64); inventory_sha256 = ('4' * 64)
    artifact_kind = 'route-decision'; decision = 'route'; recommended_model = 'model/opaque@1'; recommended_provider = 'provider-1'
    runtime_executor = 'privacy-runtime-v1'; runtime_configuration_fingerprint = 'privacy-runtime-v1'; runtime_attestation = 'observed'; reasoning_setting = 'normal'
  }
  $advancedRouteBinding = Get-LizardRouteTrustBinding -TargetRoot $advancedTarget -ReceiptId 'advanced-route' -RouterId 'privacy-runtime-v1' -RequestSha256 $decision.request_sha256 -PolicySha256 $decision.policy_sha256 -RuntimeSourceSha256 $decision.runtime_source_sha256 -InventorySha256 $decision.inventory_sha256
  $decision.trust_binding_sha256 = $advancedRouteBinding
  $advancedRouteTrust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'advanced-route-trust') -BindingSha256 $advancedRouteBinding -Subject 'advanced-route' -Now ([DateTimeOffset]::UtcNow) -PrincipalId 'privacy-runtime-v1' -Roles @('router') -Purpose 'routing' -PayloadKind 'route-decision'
  $decisionEnvelope = New-LizardSignedEvidenceEnvelope -Payload ([pscustomobject]$decision) -PayloadKind route-decision -Purpose routing -Subject advanced-route -BindingSha256 $advancedRouteBinding -ChallengePath $advancedRouteTrust.challenge_path -ChallengeSha256 $advancedRouteTrust.challenge_sha256 -PrivateKeyPath $advancedRouteTrust.private_key_path -PrivateKeySha256 $advancedRouteTrust.private_key_sha256
  Set-Content -LiteralPath (Join-Path $advancedDecisions 'advanced-route.json') -Value ($decisionEnvelope | ConvertTo-Json -Depth 12)
  $executionBinding = Get-LizardExecutionTrustBinding -TargetRoot $advancedTarget -ReceiptId 'execution-valid' -RouteDecisionId 'advanced-route' -RoutePayloadSha256 $decisionEnvelope.payload_sha256 -ExecutorId 'privacy-runtime-v1' -ConfigurationFingerprint 'privacy-runtime-v1' -ActualModel 'model/opaque@1' -ActualProvider 'provider-1'
  $runtimeTrust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'runtime-trust') -BindingSha256 $executionBinding -Subject 'execution-valid' -Now ([DateTimeOffset]::UtcNow) -PrincipalId 'privacy-runtime-v1' -Roles @('runtime') -Purpose 'execution-attestation' -PayloadKind 'execution-receipt'
  $execution = Invoke-TestPowerShell -ScriptPath $executionScript -Arguments @('-TargetPath', $advancedTarget, '-RouteDecisionId', 'advanced-route', '-ActualModel', 'model/opaque@1', '-ActualProvider', 'provider-1', '-Harness', 'codex', '-StartedAt', '2026-08-22T10:00:00Z', '-CompletedAt', '2026-08-22T10:01:00Z', '-EvidenceRef', 'evidence-opaque-123', '-ReceiptId', 'execution-valid', '-RouteTrustStorePath', $advancedRouteTrust.trust_store_path, '-RouteTrustStoreSha256', $advancedRouteTrust.trust_store_sha256, '-RouteTrustChallengePath', $advancedRouteTrust.challenge_path, '-RouteTrustChallengeSha256', $advancedRouteTrust.challenge_sha256, '-RouteReplayLedgerPath', $advancedRouteTrust.replay_ledger_path, '-TrustChallengePath', $runtimeTrust.challenge_path, '-TrustChallengeSha256', $runtimeTrust.challenge_sha256, '-RuntimePrivateKeyPath', $runtimeTrust.private_key_path, '-RuntimePrivateKeySha256', $runtimeTrust.private_key_sha256, '-Apply', '-Json')
  Assert-Equal 0 $execution.exit_code "Valid opaque execution receipt must succeed: $($execution.output)"
  $executionReceipt = $execution.output | ConvertFrom-LizardJson
  Assert-Equal 'metadata-only' ([string]$executionReceipt.sensitivity) 'Execution receipt must carry typed sensitivity.'
  Assert-Equal 'execution-attestation-audit' ([string]$executionReceipt.purpose) 'Execution receipt must carry typed purpose.'
  Assert-Equal 'not-required' ([string]$executionReceipt.redaction.status) 'Opaque execution receipt must not require redaction.'
  Assert-True (Test-Path -LiteralPath (Join-Path $advancedExecutions 'execution-valid.json')) 'Valid execution receipt must be written inside the execution receipt root.'
  $sealedExecution = Get-Content -LiteralPath (Join-Path $advancedExecutions 'execution-valid.json') -Raw | ConvertFrom-LizardJson
  Assert-Equal 2 ([int]$sealedExecution.schema_version) 'Persisted execution receipt must be signed.'
  Assert-Equal 'privacy-runtime-v1' ([string]$sealedExecution.principal_id) 'Execution signer must be the authenticated runtime.'

  $allFiles = @(Get-ChildItem -LiteralPath $fixture -Recurse -File)
  foreach ($file in $allFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($canary in $canaries) { Assert-False ($text.Contains($canary)) "Fixture file must not contain raw canary: $($file.FullName)" }
  }
  Write-Host 'PASS tests\adversarial\routing-receipt-privacy.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
