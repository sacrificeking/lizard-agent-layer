param(
  [string]$TargetPath = (Get-Location).Path,
  [Parameter(Mandatory = $true)]
  [string]$EvaluationPath,
  [int]$MinimumCasesPerRole = 2,
  [switch]$Apply,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
if ($MinimumCasesPerRole -lt 1) { throw 'CALIBRATION_MINIMUM_CASES_INVALID: MinimumCasesPerRole must be at least 1.' }

function Set-DocProperty {
  param([object]$Doc, [string]$Name, $Value)
  if ($Doc.PSObject.Properties.Name -contains $Name) { $Doc.$Name = $Value }
  else { $Doc | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

$evaluationFile = (Resolve-Path -LiteralPath $EvaluationPath).Path
$evaluation = Get-Content -LiteralPath $evaluationFile -Raw | ConvertFrom-Json
if ($evaluation.raw_prompts_stored -ne $false) { throw 'CALIBRATION_RAW_PROMPTS_FORBIDDEN: evaluation must not store raw prompts.' }
if ([string]$evaluation.evaluation_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'CALIBRATION_EVALUATION_ID_INVALID: evaluation_id is not a safe identifier.' }
if ([string]::IsNullOrWhiteSpace([string]$evaluation.model_id) -or [string]::IsNullOrWhiteSpace([string]$evaluation.provider) -or [string]::IsNullOrWhiteSpace([string]$evaluation.suite)) { throw 'CALIBRATION_EVALUATION_INVALID: model_id, provider, and suite are required.' }
if (@($evaluation.cases).Count -eq 0) { throw 'CALIBRATION_EVALUATION_INVALID: at least one evaluation case is required.' }
foreach ($case in @($evaluation.cases)) {
  if ([string]$case.id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "CALIBRATION_CASE_INVALID: invalid case id '$($case.id)'." }
  if ([string]$case.role -notmatch '^[A-Za-z][A-Za-z0-9]{0,62}$') { throw "CALIBRATION_CASE_INVALID: invalid role '$($case.role)'." }
  if ([double]$case.score -lt 0 -or [double]$case.score -gt 1) { throw "CALIBRATION_CASE_INVALID: score for '$($case.id)' is outside 0..1." }
  if ([string]$case.evidence_hash -notmatch '^[a-f0-9]{64}$') { throw "CALIBRATION_CASE_INVALID: evidence hash for '$($case.id)' is invalid." }
}

$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw 'CALIBRATION_PROFILE_MISSING: install the layer first.' }
$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
if ([string]$profile.modelMode -ne 'inventory-routing') { throw 'CALIBRATION_INVENTORY_MODE_REQUIRED: calibration requires inventory-routing.' }

$routingRoot = Resolve-SafeRoot -Path (Join-Path $TargetRoot '.agent\routing') -RequireExisting
$inventoryRelative = if ($profile.modelInventory) { [string]$profile.modelInventory } else { '.agent/routing/inventory.json' }
$runtimeRelative = if ($profile.modelRuntime) { [string]$profile.modelRuntime } else { '.agent/routing/runtime.json' }
$inventoryPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $inventoryRelative.Replace('/', '\'))
$runtimePath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $runtimeRelative.Replace('/', '\'))
foreach ($required in @($inventoryPath, $runtimePath)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "CALIBRATION_INPUT_MISSING: $required" } }
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
$runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json

if ([string]$runtime.status -ne 'ready' -or $runtime.actual_model_reporting -ne $true -or [string]$runtime.selection -notin @('subagent', 'per-call')) { throw 'CALIBRATION_RUNTIME_NOT_READY: runtime must select automatically and report actual model identity.' }
if ([string]$runtime.attestation -notin @('observed', 'attested')) { throw 'CALIBRATION_RUNTIME_NOT_READY: runtime attestation is insufficient.' }
if ([DateTimeOffset]::Parse([string]$runtime.expires_at) -le [DateTimeOffset]::UtcNow) { throw 'CALIBRATION_RUNTIME_EXPIRED: runtime capability evidence has expired.' }
if ([string]$runtime.executor_id -ne [string]$evaluation.executor_id) { throw 'CALIBRATION_EXECUTOR_MISMATCH: evaluation executor differs from runtime.' }
if ([string]$runtime.configuration_fingerprint -ne [string]$evaluation.configuration_fingerprint) { throw 'CALIBRATION_CONFIGURATION_MISMATCH: evaluation fingerprint differs from runtime.' }
if ([string]$evaluation.attestation -notin @('observed', 'attested')) { throw 'CALIBRATION_ATTESTATION_REQUIRED: evaluation must be observed or attested.' }
if ([string]$evaluation.attestation -eq 'attested' -and [string]$runtime.attestation -ne 'attested') { throw 'CALIBRATION_ATTESTATION_MISMATCH: evaluation attestation exceeds runtime attestation.' }
$evaluatedAt = [DateTimeOffset]::Parse([string]$evaluation.evaluated_at)
$expiresAt = [DateTimeOffset]::Parse([string]$evaluation.expires_at)
if ($expiresAt -le [DateTimeOffset]::UtcNow -or $expiresAt -le $evaluatedAt) { throw 'CALIBRATION_EXPIRY_INVALID: evaluation evidence is expired or precedes evaluation.' }

$models = @($inventory.models | Where-Object { [string]$_.id -eq [string]$evaluation.model_id })
if ($models.Count -ne 1) { throw "CALIBRATION_MODEL_NOT_UNIQUE: expected exactly one inventory model '$($evaluation.model_id)'." }
$model = $models[0]
if ([string]$model.provider -ne [string]$evaluation.provider) { throw 'CALIBRATION_PROVIDER_MISMATCH: evaluation provider differs from inventory.' }

$roleScores = [ordered]@{}
foreach ($group in @($evaluation.cases | Group-Object { [string]$_.role })) {
  $cases = @($group.Group)
  if ($cases.Count -lt $MinimumCasesPerRole) { throw "CALIBRATION_CASES_INSUFFICIENT: role '$($group.Name)' has $($cases.Count), requires $MinimumCasesPerRole." }
  if (@($cases | Group-Object { [string]$_.id } | Where-Object { $_.Count -gt 1 }).Count -gt 0) { throw "CALIBRATION_CASE_ID_DUPLICATE: role '$($group.Name)' contains duplicate case ids." }
  if (@($cases | Where-Object { $_.passed -ne $true }).Count -gt 0) { throw "CALIBRATION_CASE_FAILED: role '$($group.Name)' contains failed cases." }
  $roleScores[[string]$group.Name] = [Math]::Round([double](($cases | Measure-Object -Property score -Average).Average), 6)
}
if ($roleScores.Count -eq 0) { throw 'CALIBRATION_ROLE_SCORES_EMPTY: no role scores were produced.' }

$summary = [ordered]@{
  schema_version = 1
  evaluation_id = [string]$evaluation.evaluation_id
  model_id = [string]$evaluation.model_id
  provider = [string]$evaluation.provider
  suite = [string]$evaluation.suite
  executor_id = [string]$evaluation.executor_id
  configuration_fingerprint = [string]$evaluation.configuration_fingerprint
  evaluated_at = $evaluatedAt.ToUniversalTime().ToString('o')
  expires_at = $expiresAt.ToUniversalTime().ToString('o')
  attestation = [string]$evaluation.attestation
  case_count = @($evaluation.cases).Count
  role_scores = $roleScores
  applied = $Apply.IsPresent
  raw_prompts_stored = $false
}

if ($Apply) {
  Set-DocProperty -Doc $model.evidence -Name 'state' -Value 'calibrated'
  Set-DocProperty -Doc $model.evidence -Name 'suite' -Value ([string]$evaluation.suite)
  Set-DocProperty -Doc $model.evidence -Name 'evaluated_at' -Value ($evaluatedAt.ToUniversalTime().ToString('o'))
  Set-DocProperty -Doc $model.evidence -Name 'expires_at' -Value ($expiresAt.ToUniversalTime().ToString('o'))
  Set-DocProperty -Doc $model.evidence -Name 'configuration_fingerprint' -Value ([string]$evaluation.configuration_fingerprint)
  Set-DocProperty -Doc $model.evidence -Name 'role_scores' -Value ([pscustomobject]$roleScores)
  $calibrationRoot = Initialize-SafeDirectory -Path (Join-Path $routingRoot 'calibration')
  $calibrationRoot = Resolve-SafeRoot -Path $calibrationRoot -RequireExisting
  $auditPath = Resolve-SafeTargetDestination -AuthorizedRoot $calibrationRoot -DestinationPath (Join-Path $calibrationRoot "$($evaluation.evaluation_id).json")
  Set-SafeContent -AuthorizedRoot $calibrationRoot -Path $auditPath -Value ($summary | ConvertTo-Json -Depth 10)
  Set-SafeContent -AuthorizedRoot $routingRoot -Path $inventoryPath -Value ($inventory | ConvertTo-Json -Depth 12)
}

if ($Json) { $summary | ConvertTo-Json -Depth 10 }
else {
  Write-Host "Calibration $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
  Write-Host "Model: $($evaluation.model_id)"
  foreach ($entry in $roleScores.GetEnumerator()) { Write-Host "  $($entry.Key): $($entry.Value)" }
  if (-not $Apply) { Write-Host 'Preview only. Review scores, then re-run with -Apply to promote the inventory evidence.' }
}
