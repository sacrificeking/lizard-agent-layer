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
  [string]$OutputPath,
  [switch]$Apply,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting

foreach ($value in @($RouteDecisionId, $ReceiptId)) {
  if ($value -and $value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "EXECUTION_RECEIPT_ID_INVALID: $value" }
}
if ([string]::IsNullOrWhiteSpace($ActualModel) -or [string]::IsNullOrWhiteSpace($ActualProvider)) { throw 'EXECUTION_MODEL_IDENTITY_REQUIRED: actual model and provider are required.' }
if ($EvidenceRef -and $EvidenceRef.Length -gt 500) { throw 'EXECUTION_EVIDENCE_REF_INVALID: evidence reference exceeds 500 characters.' }
if (-not $Apply -and -not [string]::IsNullOrWhiteSpace($OutputPath)) { throw 'EXECUTION_RECEIPT_APPLY_REQUIRED: -OutputPath requires -Apply.' }

$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
$decisionRoot = Resolve-SafeRoot -Path (Join-Path $TargetRoot '.agent\routing\receipts\decisions') -RequireExisting
$executionRoot = Resolve-SafeRoot -Path (Join-Path $TargetRoot '.agent\routing\receipts\executions') -RequireExisting
$decisionPath = Resolve-SafeTargetDestination -AuthorizedRoot $decisionRoot -DestinationPath (Join-Path $decisionRoot "$RouteDecisionId.json")
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw 'EXECUTION_PROFILE_MISSING: project profile is missing.' }
if (-not (Test-Path -LiteralPath $decisionPath -PathType Leaf)) { throw "EXECUTION_ROUTE_DECISION_MISSING: $RouteDecisionId" }

$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
$decision = Get-Content -LiteralPath $decisionPath -Raw | ConvertFrom-Json
if ([string]$profile.modelMode -ne 'inventory-routing') { throw 'EXECUTION_RUNTIME_MODE_REQUIRED: execution receipts require inventory-routing.' }
if ([string]$decision.artifact_kind -ne 'route-decision' -or [string]$decision.decision -ne 'route') { throw 'EXECUTION_ROUTE_DECISION_INVALID: referenced receipt is not an executable route decision.' }
if ([string]$decision.recommended_model -ne $ActualModel -or [string]$decision.recommended_provider -ne $ActualProvider) { throw 'EXECUTION_MODEL_MISMATCH: actual model identity does not match the route decision.' }

$runtimeRelative = if ($profile.modelRuntime) { [string]$profile.modelRuntime } else { '.agent/routing/runtime.json' }
$runtimePath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $runtimeRelative.Replace('/', '\'))
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw 'EXECUTION_RUNTIME_MISSING: runtime capability file is missing.' }
$runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
if ([string]$runtime.status -ne 'ready' -or $runtime.actual_model_reporting -ne $true) { throw 'EXECUTION_RUNTIME_NOT_READY: runtime cannot attest actual model execution.' }
if ([string]$runtime.selection -notin @('subagent', 'per-call')) { throw 'EXECUTION_RUNTIME_NOT_READY: runtime cannot select models automatically.' }
if ([string]$runtime.attestation -notin @('observed', 'attested')) { throw 'EXECUTION_ATTESTATION_INVALID: runtime attestation is insufficient.' }
if ([string]::IsNullOrWhiteSpace([string]$runtime.configuration_fingerprint) -or [string]::IsNullOrWhiteSpace([string]$runtime.capability_source)) { throw 'EXECUTION_RUNTIME_NOT_READY: runtime provenance is incomplete.' }
if ([string]$runtime.executor_id -ne [string]$decision.runtime_executor) { throw 'EXECUTION_RUNTIME_MISMATCH: runtime executor does not match the route decision.' }
if ([string]$runtime.configuration_fingerprint -ne [string]$decision.runtime_configuration_fingerprint) { throw 'EXECUTION_CONFIGURATION_MISMATCH: runtime configuration differs from the route decision.' }
if ([string]$runtime.attestation -ne [string]$decision.runtime_attestation) { throw 'EXECUTION_ATTESTATION_MISMATCH: runtime attestation differs from the route decision.' }
if (@($runtime.harnesses) -notcontains $Harness) { throw "EXECUTION_HARNESS_MISMATCH: runtime does not cover harness '$Harness'." }
if ([DateTimeOffset]::Parse([string]$runtime.expires_at) -le [DateTimeOffset]::UtcNow) { throw 'EXECUTION_RUNTIME_EXPIRED: runtime capability evidence has expired.' }

$started = [DateTimeOffset]::Parse($StartedAt)
$completed = [DateTimeOffset]::Parse($CompletedAt)
if ($completed -lt $started) { throw 'EXECUTION_TIME_INVALID: completed_at precedes started_at.' }
if ([string]::IsNullOrWhiteSpace($ReceiptId)) { $ReceiptId = [Guid]::NewGuid().ToString('N') }

$receipt = [ordered]@{
  schema_version = 1
  artifact_kind = 'execution-receipt'
  receipt_id = $ReceiptId
  route_decision_id = $RouteDecisionId
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
  evidence_ref = if ($EvidenceRef) { $EvidenceRef } else { $null }
  raw_prompt_stored = $false
}

if ($Apply) {
  $destination = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $executionRoot "$ReceiptId.json" } elseif ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $executionRoot $OutputPath }
  $destination = Resolve-SafeTargetDestination -AuthorizedRoot $executionRoot -DestinationPath $destination
  Set-SafeContent -AuthorizedRoot $executionRoot -Path $destination -Value ($receipt | ConvertTo-Json -Depth 10)
}

if ($Json) { $receipt | ConvertTo-Json -Depth 10 }
else {
  Write-Host "Execution receipt: $ReceiptId"
  Write-Host "Route decision: $RouteDecisionId"
  Write-Host "Actual model: $ActualModel"
  Write-Host "Attestation: $($runtime.attestation) via $($runtime.executor_id)"
  if (-not $Apply) { Write-Host 'Preview only. An attesting runtime must re-run with -Apply after execution.' }
}
