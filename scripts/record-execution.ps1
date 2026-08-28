param(
  [string]$TargetPath = (Get-Location).Path,
  [Parameter(Mandatory = $true)]
  [string]$RouteDecisionId,
  [Parameter(Mandatory = $true)]
  [string]$ActualModel,
  [Parameter(Mandatory = $true)]
  [string]$ActualProvider,
  [Parameter(Mandatory = $true)]
  [string]$Harness,
  [Parameter(Mandatory = $true)]
  [string]$StartedAt,
  [string]$CompletedAt = (Get-Date).ToUniversalTime().ToString('o'),
  [ValidateSet('succeeded', 'failed', 'cancelled')]
  [string]$Outcome = 'succeeded',
  [string]$EvidenceRef,
  [string]$ReceiptId,
  [string]$RouteTrustStorePath,
  [string]$RouteTrustStoreSha256,
  [string]$RouteTrustChallengePath,
  [string]$RouteTrustChallengeSha256,
  [string]$RouteReplayLedgerPath,
  [string]$TrustChallengePath,
  [string]$TrustChallengeSha256,
  [string]$RuntimePrivateKeyPath,
  [string]$RuntimePrivateKeySha256,
  [string]$OutputPath,
  [switch]$Apply,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Json.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.SafeReport.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Trust.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting

foreach ($value in @($RouteDecisionId, $ReceiptId)) {
  if ($value -and $value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "EXECUTION_RECEIPT_ID_INVALID: $value" }
}
if ([string]::IsNullOrWhiteSpace($ActualModel) -or [string]::IsNullOrWhiteSpace($ActualProvider)) { throw 'EXECUTION_MODEL_IDENTITY_REQUIRED: actual model and provider are required.' }
Assert-LizardOpaqueIdentifier -Value $EvidenceRef -ErrorCode 'EXECUTION_EVIDENCE_REF_INVALID' -MaximumLength 128 -AllowNull
Assert-LizardOpaqueIdentifier -Value $ActualModel -ErrorCode 'EXECUTION_MODEL_IDENTITY_INVALID' -MaximumLength 200
Assert-LizardOpaqueIdentifier -Value $ActualProvider -ErrorCode 'EXECUTION_PROVIDER_IDENTITY_INVALID' -MaximumLength 200
Assert-LizardOpaqueIdentifier -Value $Harness -ErrorCode 'EXECUTION_HARNESS_INVALID' -MaximumLength 63
if (-not $Apply -and -not [string]::IsNullOrWhiteSpace($OutputPath)) { throw 'EXECUTION_RECEIPT_APPLY_REQUIRED: -OutputPath requires -Apply.' }

$profilePath = Join-Path $TargetRoot '.agent/project-profile.json'
$decisionRoot = Resolve-SafeRoot -Path (Join-Path $TargetRoot '.agent/routing/receipts/decisions') -RequireExisting
$executionRoot = Resolve-SafeRoot -Path (Join-Path $TargetRoot '.agent/routing/receipts/executions') -RequireExisting
$decisionPath = Resolve-SafeTargetDestination -AuthorizedRoot $decisionRoot -DestinationPath (Join-Path $decisionRoot "$RouteDecisionId.json")
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw 'EXECUTION_PROFILE_MISSING: project profile is missing.' }
if (-not (Test-Path -LiteralPath $decisionPath -PathType Leaf)) { throw "EXECUTION_ROUTE_DECISION_MISSING: $RouteDecisionId" }
foreach ($required in @(@{ value = $RouteTrustStorePath; label = 'RouteTrustStorePath' }, @{ value = $RouteTrustStoreSha256; label = 'RouteTrustStoreSha256' }, @{ value = $RouteTrustChallengePath; label = 'RouteTrustChallengePath' }, @{ value = $RouteTrustChallengeSha256; label = 'RouteTrustChallengeSha256' })) { if ([string]::IsNullOrWhiteSpace([string]$required.value)) { throw "EXECUTION_ROUTE_TRUST_REQUIRED: $($required.label) is required." } }

$profile = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $profilePath -Raw)
$decisionEnvelope = Read-LizardSignedEvidenceFile -Path $decisionPath
$decision = $decisionEnvelope.payload
if ([string]$profile.modelMode -ne 'inventory-routing') { throw 'EXECUTION_RUNTIME_MODE_REQUIRED: execution receipts require inventory-routing.' }
if ([string]$decision.artifact_kind -ne 'route-decision' -or [string]$decision.decision -ne 'route') { throw 'EXECUTION_ROUTE_DECISION_INVALID: referenced receipt is not an executable route decision.' }
if ([string]$decision.recommended_model -ne $ActualModel -or [string]$decision.recommended_provider -ne $ActualProvider) { throw 'EXECUTION_MODEL_MISMATCH: actual model identity does not match the route decision.' }
$decisionTime = [DateTimeOffset]$decisionEnvelope.issued_at
$routeTrust = Read-LizardTrustStore -Path $RouteTrustStorePath -ExpectedSha256 $RouteTrustStoreSha256
$routeChallenge = Read-LizardTrustChallenge -Path $RouteTrustChallengePath -ExpectedSha256 $RouteTrustChallengeSha256 -Now $decisionTime
$expectedRouteBinding = Get-LizardRouteTrustBinding -TargetRoot $TargetRoot -ReceiptId ([string]$decision.receipt_id) -RouterId ([string]$decision.router_id) -RequestSha256 ([string]$decision.request_sha256) -PolicySha256 ([string]$decision.policy_sha256) -RuntimeSourceSha256 ([string]$decision.runtime_source_sha256) -InventorySha256 ([string]$decision.inventory_sha256)
if ($expectedRouteBinding -ne [string]$decision.trust_binding_sha256) { throw 'EXECUTION_ROUTE_BINDING_MISMATCH: route decision trust binding is invalid.' }
$verifiedRoute = Test-LizardSignedEvidenceEnvelope -Envelope $decisionEnvelope -TrustStoreRead $routeTrust -ChallengeRead $routeChallenge -ExpectedPayloadKind 'route-decision' -ExpectedPurpose 'routing' -ExpectedSubject $RouteDecisionId -ExpectedBindingSha256 $expectedRouteBinding -RequiredRole 'router' -Now $decisionTime
if ([string]$verifiedRoute.principal_id -ne [string]$decision.router_id) { throw 'EXECUTION_ROUTER_IDENTITY_MISMATCH: route signer does not match router_id.' }

$runtimeRelative = if ($profile.modelRuntime) { [string]$profile.modelRuntime } else { '.agent/routing/runtime.json' }
$runtimePath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $runtimeRelative.Replace('/', '/'))
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw 'EXECUTION_RUNTIME_MISSING: runtime capability file is missing.' }
$runtime = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $runtimePath -Raw)
if ([string]$runtime.status -ne 'ready' -or $runtime.actual_model_reporting -ne $true) { throw 'EXECUTION_RUNTIME_NOT_READY: runtime cannot attest actual model execution.' }
if ([string]$runtime.selection -notin @('subagent', 'per-call')) { throw 'EXECUTION_RUNTIME_NOT_READY: runtime cannot select models automatically.' }
if ([string]$runtime.attestation -notin @('observed', 'attested')) { throw 'EXECUTION_ATTESTATION_INVALID: runtime attestation is insufficient.' }
if ([string]::IsNullOrWhiteSpace([string]$runtime.configuration_fingerprint) -or [string]::IsNullOrWhiteSpace([string]$runtime.capability_source)) { throw 'EXECUTION_RUNTIME_NOT_READY: runtime provenance is incomplete.' }
Assert-LizardOpaqueIdentifier -Value ([string]$runtime.executor_id) -ErrorCode 'EXECUTION_RUNTIME_ID_INVALID' -MaximumLength 128
Assert-LizardOpaqueIdentifier -Value ([string]$runtime.configuration_fingerprint) -ErrorCode 'EXECUTION_RUNTIME_FINGERPRINT_INVALID' -MaximumLength 200
Assert-LizardOpaqueIdentifier -Value ([string]$runtime.capability_source) -ErrorCode 'EXECUTION_ATTESTATION_SOURCE_INVALID' -MaximumLength 128
if ([string]$runtime.executor_id -ne [string]$decision.runtime_executor) { throw 'EXECUTION_RUNTIME_MISMATCH: runtime executor does not match the route decision.' }
if ([string]$runtime.configuration_fingerprint -ne [string]$decision.runtime_configuration_fingerprint) { throw 'EXECUTION_CONFIGURATION_MISMATCH: runtime configuration differs from the route decision.' }
if ([string]$runtime.attestation -ne [string]$decision.runtime_attestation) { throw 'EXECUTION_ATTESTATION_MISMATCH: runtime attestation differs from the route decision.' }
if (@($runtime.harnesses) -notcontains $Harness) { throw "EXECUTION_HARNESS_MISMATCH: runtime does not cover harness '$Harness'." }
if ([DateTimeOffset]::Parse([string]$runtime.expires_at) -le [DateTimeOffset]::UtcNow) { throw 'EXECUTION_RUNTIME_EXPIRED: runtime capability evidence has expired.' }

$started = [DateTimeOffset]::Parse($StartedAt)
$completed = [DateTimeOffset]::Parse($CompletedAt)
if ($completed -lt $started) { throw 'EXECUTION_TIME_INVALID: completed_at precedes started_at.' }
if ([string]::IsNullOrWhiteSpace($ReceiptId)) { $ReceiptId = [Guid]::NewGuid().ToString('N') }
$executionBinding = Get-LizardExecutionTrustBinding -TargetRoot $TargetRoot -ReceiptId $ReceiptId -RouteDecisionId $RouteDecisionId -RoutePayloadSha256 ([string]$decisionEnvelope.payload_sha256) -ExecutorId ([string]$runtime.executor_id) -ConfigurationFingerprint ([string]$runtime.configuration_fingerprint) -ActualModel $ActualModel -ActualProvider $ActualProvider

$receipt = [ordered]@{
  schema_version = 1
  artifact_kind = 'execution-receipt'
  receipt_id = $ReceiptId
  route_decision_id = $RouteDecisionId
  route_payload_sha256 = [string]$decisionEnvelope.payload_sha256
  authenticated_router_id = [string]$verifiedRoute.principal_id
  route_approval_ref = [string]$verifiedRoute.approval_ref
  trust_binding_sha256 = $executionBinding
  created_at = (Get-Date).ToUniversalTime().ToString('o')
  started_at = $started.ToUniversalTime().ToString('o')
  completed_at = $completed.ToUniversalTime().ToString('o')
  executor_id = [string]$runtime.executor_id
  configuration_fingerprint = [string]$runtime.configuration_fingerprint
  harness = $Harness
  actual_model = $ActualModel
  actual_provider = $ActualProvider
  reasoning_setting = if ($null -ne $decision.reasoning_setting) { [string]$decision.reasoning_setting } else { $null }
  attestation = [string]$runtime.attestation
  attestation_source = [string]$runtime.capability_source
  outcome = $Outcome
  sensitivity = 'metadata-only'
  purpose = 'execution-attestation-audit'
  audience = @('operators', 'auditors')
  retention_class = 'organization-policy-required'
  content_policy = 'identifiers-only'
  evidence_ref = if ($EvidenceRef) { $EvidenceRef } else { $null }
  raw_prompt_stored = $false
  redaction = $null
}
$receipt = Protect-LizardReportDocument -Document $receipt
$persistedDocument = $receipt

if ($Apply) {
  foreach ($required in @(@{ value = $TrustChallengePath; label = 'TrustChallengePath' }, @{ value = $TrustChallengeSha256; label = 'TrustChallengeSha256' }, @{ value = $RuntimePrivateKeyPath; label = 'RuntimePrivateKeyPath' }, @{ value = $RuntimePrivateKeySha256; label = 'RuntimePrivateKeySha256' })) { if ([string]::IsNullOrWhiteSpace([string]$required.value)) { throw "EXECUTION_SIGNATURE_REQUIRED: $($required.label) is required to persist an execution receipt." } }
  if ([string]::IsNullOrWhiteSpace($RouteReplayLedgerPath)) { throw 'EXECUTION_ROUTE_REPLAY_LEDGER_REQUIRED: RouteReplayLedgerPath is required to consume a route decision.' }
  foreach ($externalPath in @($RouteTrustStorePath, $RouteTrustChallengePath, $RouteReplayLedgerPath, $TrustChallengePath, $RuntimePrivateKeyPath)) { Assert-PathOutsideRoot -Path $externalPath -ExcludedRoot $TargetRoot -Label 'Execution trust input' }
  $persistedDocument = New-LizardSignedEvidenceEnvelope -Payload $receipt -PayloadKind 'execution-receipt' -Purpose 'execution-attestation' -Subject $ReceiptId -BindingSha256 $executionBinding -ChallengePath $TrustChallengePath -ChallengeSha256 $TrustChallengeSha256 -PrivateKeyPath $RuntimePrivateKeyPath -PrivateKeySha256 $RuntimePrivateKeySha256
  if ([string]$persistedDocument.principal_id -ne [string]$runtime.executor_id) { throw 'EXECUTION_RUNTIME_IDENTITY_MISMATCH: executor_id must equal the authenticated runtime signing principal.' }
  Use-LizardReplayLedger -LedgerPath $RouteReplayLedgerPath -EnvelopeId $verifiedRoute.envelope_id -Nonce $verifiedRoute.nonce -Purpose 'route-execution' | Out-Null
  $destination = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $executionRoot "$ReceiptId.json" } elseif ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $executionRoot $OutputPath }
  $destination = Resolve-SafeTargetDestination -AuthorizedRoot $executionRoot -DestinationPath $destination
  Set-SafeContent -AuthorizedRoot $executionRoot -Path $destination -Value ($persistedDocument | ConvertTo-Json -Depth 14)
}

if ($Json) { $receipt | ConvertTo-Json -Depth 10 }
else {
  Write-Host "Execution receipt: $ReceiptId"
  Write-Host "Route decision: $RouteDecisionId"
  Write-Host "Actual model: $(Protect-LizardConsoleText -Text $ActualModel)"
  Write-Host "Attestation: $($runtime.attestation) via $($runtime.executor_id)"
  if (-not $Apply) { Write-Host 'Preview only. An attesting runtime must re-run with -Apply after execution.' }
}
