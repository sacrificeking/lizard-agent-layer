param(
  [string]$TargetPath = (Get-Location).Path,
  [ValidateSet('strategy', 'execution', 'verification')]
  [string]$Phase = 'execution',
  [string]$TaskClass = 'implementation',
  [ValidateSet('low', 'medium', 'high')]
  [string]$RiskLevel = 'medium',
  [ValidateSet('public', 'internal-code', 'internal-docs', 'confidential', 'regulated', 'secrets')]
  [string]$DataClass = 'internal-code',
  [string[]]$RequiredCapabilities,
  [string[]]$Signals,
  [int]$AttemptCount = 1,
  [Alias('AvailableProfiles')]
  [string[]]$AvailableModels,
  [Alias('PreviousProfile')]
  [string]$PreviousModel,
  [string]$PreviousProvider,
  [string]$ReceiptId,
  [string]$OutputPath,
  [switch]$Apply,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
$policyPath = Join-Path $TargetRoot '.agent\routing\policy.json'

foreach ($requiredPath in @($profilePath, $policyPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "ROUTING_NOT_INSTALLED: Missing $requiredPath" }
}
if ($TaskClass -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "ROUTE_TASK_CLASS_INVALID: $TaskClass" }
if ($AttemptCount -lt 1) { throw 'ROUTE_ATTEMPT_COUNT_INVALID: AttemptCount must be at least 1.' }
if (-not $Apply -and -not [string]::IsNullOrWhiteSpace($OutputPath)) { throw 'ROUTE_RECEIPT_APPLY_REQUIRED: -OutputPath requires -Apply.' }

function Expand-StringList {
  param($Values)
  $list = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in ([string]$value -split ',')) {
      $item = $part.Trim()
      if ($item -and -not $list.Contains($item)) { $list.Add($item) | Out-Null }
    }
  }
  @($list.ToArray())
}

function Get-CostRank {
  param([string]$Tier)
  switch ($Tier) { 'local' { 0 } 'budget' { 1 } 'balanced' { 2 } 'premium' { 3 } 'frontier' { 4 } default { 99 } }
}

function Test-ContainsAll {
  param($Available, $Required)
  foreach ($item in @($Required)) { if (@($Available) -notcontains [string]$item) { return $false } }
  return $true
}

function Get-RoleScore {
  param($Model, [string]$Role)
  $scores = $Model.evidence.role_scores
  if ($null -ne $scores -and $scores.PSObject.Properties.Name -contains $Role) { return [double]$scores.$Role }
  return -1.0
}

function Get-RoleDisplayName {
  param([string]$Role)
  switch ($Role) {
    'strategist' { 'Strategy and planning' }
    'deepExecutor' { 'Complex implementation and debugging' }
    'standardExecutor' { 'Standard implementation' }
    'bulkExecutor' { 'Low-risk mechanical work' }
    'researchExecutor' { 'Research and synthesis' }
    'verifier' { 'Fresh verification' }
    default { if ($Role) { $Role } else { 'Not applicable' } }
  }
}

function Get-ReasoningSetting {
  param($Model, [string]$Effort)
  $normalized = switch ($Effort) { 'low' { 'light' } 'medium' { 'balanced' } 'high' { 'deep' } default { 'balanced' } }
  if ($null -ne $Model.reasoning -and $Model.reasoning.PSObject.Properties.Name -contains $normalized) { return $Model.reasoning.$normalized }
  return $null
}

function Assert-InventoryContract {
  param($Inventory)
  if (@($Inventory.models).Count -eq 0) { throw 'inventory contains no models' }
  foreach ($model in @($Inventory.models)) {
    if ([string]::IsNullOrWhiteSpace([string]$model.id)) { throw 'inventory model id is empty' }
    if ([string]::IsNullOrWhiteSpace([string]$model.provider)) { throw "inventory provider is empty for model $($model.id)" }
    if ([string]$model.evidence.state -notin @('uncalibrated', 'calibrated', 'expired', 'rejected')) { throw "inventory evidence state is invalid for model $($model.id)" }
    foreach ($score in @($model.evidence.role_scores.PSObject.Properties)) {
      if ([double]$score.Value -lt 0 -or [double]$score.Value -gt 1) { throw "inventory role score is outside 0..1 for model $($model.id)" }
    }
    if ([string]$model.evidence.state -eq 'calibrated') {
      if ([string]::IsNullOrWhiteSpace([string]$model.evidence.suite) -or [string]::IsNullOrWhiteSpace([string]$model.evidence.evaluated_at) -or [string]::IsNullOrWhiteSpace([string]$model.evidence.expires_at) -or [string]::IsNullOrWhiteSpace([string]$model.evidence.configuration_fingerprint) -or @($model.evidence.role_scores.PSObject.Properties).Count -eq 0) { throw "calibrated evidence is incomplete for model $($model.id)" }
      $evaluatedAt = [DateTimeOffset]::MinValue
      if (-not [DateTimeOffset]::TryParse([string]$model.evidence.evaluated_at, [ref]$evaluatedAt)) { throw "evaluated_at is invalid for model $($model.id)" }
      if ($model.evidence.expires_at) {
        $expiresAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$model.evidence.expires_at, [ref]$expiresAt)) { throw "expires_at is invalid for model $($model.id)" }
      }
    }
  }
}

function Assert-RuntimeContract {
  param($Runtime)
  if ([string]$Runtime.status -ne 'ready') { throw 'runtime status is not ready' }
  if ([string]$Runtime.selection -notin @('subagent', 'per-call')) { throw 'runtime cannot select automatically per call or subagent' }
  if ($Runtime.actual_model_reporting -ne $true) { throw 'runtime cannot report the actual model' }
  if ([string]$Runtime.attestation -notin @('observed', 'attested')) { throw 'runtime attestation is neither observed nor attested' }
  if ([string]::IsNullOrWhiteSpace([string]$Runtime.executor_id)) { throw 'runtime executor_id is empty' }
  if ([string]::IsNullOrWhiteSpace([string]$Runtime.configuration_fingerprint)) { throw 'runtime configuration_fingerprint is empty' }
  $runtimeExpiry = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse([string]$Runtime.expires_at, [ref]$runtimeExpiry)) { throw 'runtime expires_at is invalid' }
  if ($runtimeExpiry -le [DateTimeOffset]::UtcNow) { throw 'runtime capability evidence has expired' }
}

$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
if ([string]$profile.routingPolicy -ne [string]$policy.name) { throw "ROUTING_POLICY_MISMATCH: Profile '$($profile.routingPolicy)' does not match installed policy '$($policy.name)'." }

$modelMode = if ($profile.PSObject.Properties.Name -contains 'modelMode' -and -not [string]::IsNullOrWhiteSpace([string]$profile.modelMode)) { [string]$profile.modelMode } else { [string]$policy.model_selection.default_mode }
if ($modelMode -notin @('inherit-current', 'inventory-routing')) { throw "ROUTE_MODEL_MODE_INVALID: $modelMode" }
$requiredCapabilityList = Expand-StringList $RequiredCapabilities
$signalList = Expand-StringList $Signals
$availableModelList = Expand-StringList $AvailableModels
$reasons = New-Object System.Collections.Generic.List[string]
$decision = 'route'
$effectivePhase = $Phase

if ($DataClass -eq 'secrets') {
  $decision = 'block'
  $reasons.Add('Secrets are blocked before staged execution.') | Out-Null
}
if ($decision -eq 'route') {
  $humanSignals = @($signalList | Where-Object { @($policy.escalation.human_review_signals) -contains $_ })
  if ($humanSignals.Count -gt 0) {
    $decision = 'human-review'
    $reasons.Add("Human-review signal: $($humanSignals -join ', ').") | Out-Null
  } elseif ($AttemptCount -gt [int]$policy.escalation.max_attempts) {
    $decision = 'human-review'
    $reasons.Add("Attempt count $AttemptCount exceeds policy maximum $($policy.escalation.max_attempts).") | Out-Null
  } else {
    $strategySignals = @($signalList | Where-Object { @($policy.escalation.strategist_signals) -contains $_ })
    if ($strategySignals.Count -gt 0) {
      $effectivePhase = 'strategy'
      $reasons.Add("Returned to strategy for signal: $($strategySignals -join ', ').") | Out-Null
    }
  }
}

$selectedRoute = $null
$selectedRole = $null
$selectedModel = $null
$selectedProvider = $null
$selectedInventoryModel = $null
$selectionCapability = $null
$runtimeAttestation = 'unknown'
$runtimeExecutor = $null
$runtimeConfigurationFingerprint = $null
$reasoningSetting = $null
$costTier = $null
$fallbackUsed = $false
$fallbackReason = $null
$requestedRoles = @()
$effectiveCapabilities = @($requiredCapabilityList)

if ($decision -eq 'route') {
  $matchingRoutes = @($policy.routes | Where-Object {
    [string]$_.phase -eq $effectivePhase -and
    @($_.risk_levels) -contains $RiskLevel -and
    @($_.data_classes) -contains $DataClass -and
    ((@($_.task_classes) -contains '*') -or (@($_.task_classes) -contains $TaskClass))
  } | Sort-Object @{ Expression = { [int]$_.priority }; Descending = $true }, @{ Expression = { [string]$_.id }; Descending = $false })
  if ($matchingRoutes.Count -eq 0) {
    $decision = 'block'
    $reasons.Add('No route matches phase, task class, risk level, and data class.') | Out-Null
  } else {
    $selectedRoute = $matchingRoutes[0]
    $requestedRoles = @($selectedRoute.candidate_roles)
    $effectiveCapabilities = @((@($selectedRoute.required_capabilities) + @($requiredCapabilityList)) | Sort-Object -Unique)

    if ($modelMode -eq 'inherit-current') {
      $selectedRole = [string]$selectedRoute.candidate_roles[0]
      $reasons.Add("Use the model already active in the harness for $(Get-RoleDisplayName -Role $selectedRole).") | Out-Null
      $reasons.Add('Continue through all phases without asking the user to change a model picker.') | Out-Null
    } else {
      $inventoryRelative = if ($profile.PSObject.Properties.Name -contains 'modelInventory' -and -not [string]::IsNullOrWhiteSpace([string]$profile.modelInventory)) { [string]$profile.modelInventory } else { [string]$policy.model_selection.inventory_path }
      $runtimeRelative = if ($profile.PSObject.Properties.Name -contains 'modelRuntime' -and -not [string]::IsNullOrWhiteSpace([string]$profile.modelRuntime)) { [string]$profile.modelRuntime } else { [string]$policy.model_selection.runtime_path }
      try {
        $runtimePath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $runtimeRelative.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw "runtime capability file is missing: $runtimeRelative" }
        $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
        Assert-RuntimeContract -Runtime $runtime
        $selectionCapability = [string]$runtime.selection
        $runtimeAttestation = [string]$runtime.attestation
        $runtimeExecutor = [string]$runtime.executor_id
        $runtimeConfigurationFingerprint = [string]$runtime.configuration_fingerprint
        $inventoryPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $inventoryRelative.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) { throw "inventory file is missing: $inventoryRelative" }
        $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
        Assert-InventoryContract -Inventory $inventory
        $duplicateIds = @($inventory.models | Group-Object { [string]$_.id } | Where-Object { $_.Count -gt 1 })
        if ($duplicateIds.Count -gt 0) { throw "inventory contains duplicate model id: $([string]$duplicateIds[0].Name)" }

        $roleEntries = New-Object System.Collections.Generic.List[object]
        foreach ($role in @($selectedRoute.candidate_roles)) { $roleEntries.Add([pscustomobject]@{ role = [string]$role; fallback = $false }) | Out-Null }
        foreach ($role in @($selectedRoute.fallback_roles)) { $roleEntries.Add([pscustomobject]@{ role = [string]$role; fallback = $true }) | Out-Null }
        $candidates = New-Object System.Collections.Generic.List[object]
        foreach ($roleEntry in @($roleEntries.ToArray())) {
          foreach ($candidate in @($inventory.models)) {
            if ($candidate.available -ne $true -or $candidate.approved -ne $true) { continue }
            if ([string]$candidate.evidence.state -notin @($policy.model_selection.eligible_evidence_states)) { continue }
            if ([string]$candidate.evidence.configuration_fingerprint -ne $runtimeConfigurationFingerprint) { continue }
            if ($candidate.evidence.expires_at -and ([DateTimeOffset]::Parse([string]$candidate.evidence.expires_at) -le [DateTimeOffset]::UtcNow)) { continue }
            if ($availableModelList.Count -gt 0 -and $availableModelList -notcontains [string]$candidate.id) { continue }
            if (@($candidate.allowed_data_classes) -notcontains $DataClass) { continue }
            if (-not (Test-ContainsAll -Available @($candidate.capabilities) -Required $effectiveCapabilities)) { continue }
            if ((Get-CostRank ([string]$candidate.cost_tier)) -gt (Get-CostRank ([string]$selectedRoute.max_cost_tier))) { continue }
            $roleScore = Get-RoleScore -Model $candidate -Role ([string]$roleEntry.role)
            if ($roleScore -lt [double]$policy.model_selection.minimum_role_score) { continue }
            $rank = ($roleScore * 100.0) - (Get-CostRank ([string]$candidate.cost_tier) * 0.25)
            if ([bool]$roleEntry.fallback) { $rank -= 100.0 }
            if ($effectivePhase -eq 'verification' -and @($policy.verification.different_model_preferred_for) -contains $RiskLevel -and $PreviousModel -and [string]$candidate.id -eq $PreviousModel) { $rank -= 20.0 }
            if ($effectivePhase -eq 'verification' -and @($policy.verification.different_provider_preferred_for) -contains $RiskLevel -and $PreviousProvider -and [string]$candidate.provider -eq $PreviousProvider) { $rank -= 5.0 }
            $candidates.Add([pscustomobject]@{ model = $candidate; role = [string]$roleEntry.role; fallback = [bool]$roleEntry.fallback; rank = $rank }) | Out-Null
          }
        }
        $best = @($candidates.ToArray() | Sort-Object @{ Expression = { [double]$_.rank }; Descending = $true }, @{ Expression = { Get-CostRank ([string]$_.model.cost_tier) }; Descending = $false }, @{ Expression = { [string]$_.model.id }; Descending = $false } | Select-Object -First 1)
        if ($best.Count -eq 0) { throw 'no available, approved, calibrated model satisfies the route' }
        $selectedInventoryModel = $best[0].model
        $selectedModel = [string]$selectedInventoryModel.id
        $selectedProvider = [string]$selectedInventoryModel.provider
        $selectedRole = [string]$best[0].role
        $fallbackUsed = [bool]$best[0].fallback
        if ($fallbackUsed) { $fallbackReason = 'No eligible calibrated candidate was available for a primary role.' }
        $reasoningSetting = Get-ReasoningSetting -Model $selectedInventoryModel -Effort ([string]$selectedRoute.effort)
        $costTier = [string]$selectedInventoryModel.cost_tier
        $reasons.Add("Recommended calibrated inventory model $selectedModel for automatic executor $runtimeExecutor and $(Get-RoleDisplayName -Role $selectedRole).") | Out-Null
        if ($fallbackReason) { $reasons.Add($fallbackReason) | Out-Null }
      } catch {
        $decision = 'block'
        $reasons.Add("Inventory routing failed closed: $($_.Exception.Message).") | Out-Null
        $reasons.Add('Use a profile with modelMode inherit-current to continue without model selection.') | Out-Null
      }
    }
  }
}

if ([string]::IsNullOrWhiteSpace($ReceiptId)) { $ReceiptId = [Guid]::NewGuid().ToString('N') }
if ($ReceiptId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "ROUTE_RECEIPT_ID_INVALID: $ReceiptId" }
if ($reasons.Count -eq 0) { $reasons.Add('Staged execution stopped before route selection.') | Out-Null }
$verificationMode = if ($decision -eq 'human-review') { 'human-review' } elseif ($effectivePhase -ne 'verification' -or $decision -ne 'route') { 'not-applicable' } elseif ($modelMode -eq 'inventory-routing' -and $PreviousModel -and $selectedModel -and $selectedModel -ne $PreviousModel) { 'independent-model-preferred' } else { 'self-review' }

$receipt = [ordered]@{
  schema_version = 1
  artifact_kind = 'route-decision'
  receipt_id = $ReceiptId
  created_at = (Get-Date).ToUniversalTime().ToString('o')
  policy = [string]$policy.name
  model_mode = $modelMode
  runtime_executor = if ($runtimeExecutor) { $runtimeExecutor } else { $null }
  runtime_attestation = $runtimeAttestation
  runtime_configuration_fingerprint = if ($runtimeConfigurationFingerprint) { $runtimeConfigurationFingerprint } else { $null }
  model_switch_required = $false
  phase = $effectivePhase
  task_class = $TaskClass
  risk_level = $RiskLevel
  data_class = $DataClass
  decision = $decision
  route_id = if ($selectedRoute) { [string]$selectedRoute.id } else { $null }
  requested_roles = @($requestedRoles)
  selected_role = if ($selectedRole) { $selectedRole } else { $null }
  recommended_model = if ($selectedModel) { $selectedModel } else { $null }
  recommended_provider = if ($selectedProvider) { $selectedProvider } else { $null }
  selection_capability = if ($selectionCapability) { $selectionCapability } else { $null }
  effort = if ($selectedRoute) { [string]$selectedRoute.effort } else { $null }
  reasoning_setting = if ($null -ne $reasoningSetting) { [string]$reasoningSetting } else { $null }
  cost_tier = if ($costTier) { $costTier } else { $null }
  verification_mode = $verificationMode
  fallback_used = $fallbackUsed
  fallback_reason = if ($fallbackReason) { $fallbackReason } else { $null }
  required_capabilities = @($effectiveCapabilities)
  signals = @($signalList)
  reasons = @($reasons.ToArray())
  raw_prompt_stored = $false
}

if ($Apply) {
  $receiptsRootPath = Join-Path $TargetRoot '.agent\routing\receipts\decisions'
  $receiptsRoot = Resolve-SafeRoot -Path $receiptsRootPath -RequireExisting
  $destination = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $receiptsRoot "$ReceiptId.json" } elseif ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $receiptsRoot $OutputPath }
  $destination = Resolve-SafeTargetDestination -AuthorizedRoot $receiptsRoot -DestinationPath $destination
  Set-SafeContent -AuthorizedRoot $receiptsRoot -Path $destination -Value ($receipt | ConvertTo-Json -Depth 12)
}

if ($Json) {
  $receipt | ConvertTo-Json -Depth 12
} else {
  $resultLabel = switch ($decision) { 'route' { 'READY' } 'human-review' { 'PAUSE FOR HUMAN REVIEW' } default { 'BLOCKED' } }
  Write-Host "Routing result: $resultLabel"
  if ($decision -eq 'route' -and $modelMode -eq 'inherit-current') {
    Write-Host 'Next action: Continue with the model already active in your IDE or agent. No model-picker change is needed.'
  } elseif ($decision -eq 'route') {
    Write-Host "Next action: Let the configured automatic runtime execute $selectedModel. Do not change a model picker manually."
  } elseif ($decision -eq 'human-review') {
    Write-Host 'Next action: Pause this task and ask a responsible human to review the scope, ownership, or risk.'
  } else {
    Write-Host 'Next action: Stop. This task is not allowed to proceed under the current routing policy.'
  }
  $stageLabel = (Get-Culture).TextInfo.ToTitleCase($effectivePhase)
  Write-Host "Stage: $stageLabel"
  Write-Host "Work type: $(Get-RoleDisplayName -Role $selectedRole)"
  Write-Host "Technical route: $(if ($selectedRoute) { $selectedRoute.id } else { 'none' })"
  if ($decision -eq 'route') {
    Write-Host "Model: $(if ($selectedModel) { $selectedModel } else { 'current IDE/agent model' })"
  }
  Write-Host 'Reason:'
  foreach ($reason in @($reasons.ToArray())) { Write-Host "  - $reason" }
  if (-not $Apply) { Write-Host 'Audit: no receipt was written. Use -Apply only when you intentionally want a metadata-only audit receipt.' }
}
