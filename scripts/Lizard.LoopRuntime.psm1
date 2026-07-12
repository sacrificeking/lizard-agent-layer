Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.LoopEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.Transaction.psm1')

function New-LizardLoopRuntimeException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['loop_runtime_code'] = $Code
  return $exception
}

function ConvertTo-LizardLoopUtc {
  param([string]$NowUtc)
  if ([string]::IsNullOrWhiteSpace($NowUtc)) { return (Get-Date).ToUniversalTime() }
  $parsed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse($NowUtc, [ref]$parsed)) {
    throw (New-LizardLoopRuntimeException -Code 'LOOP_CLOCK_INVALID' -Message "NowUtc is not a valid timestamp: $NowUtc")
  }
  return $parsed.UtcDateTime
}

function Read-LizardLoopJson {
  param([string]$Path, [string]$Code)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw (New-LizardLoopRuntimeException -Code $Code -Message "File is missing: $Path")
  }
  try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
  catch { throw (New-LizardLoopRuntimeException -Code $Code -Message $_.Exception.Message) }
}

function Resolve-LizardLoopRuntimeContext {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$TargetPath, [string]$Pattern)
  $targetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
  $manifestPath = Resolve-SafeTargetDestination -AuthorizedRoot $targetRoot -DestinationPath (Join-Path $targetRoot '.agent\loops\lizard-agent-layer.loop-install.json')
  $manifest = Read-LizardLoopJson -Path $manifestPath -Code 'LOOP_MANIFEST_INVALID'
  $patternName = if ([string]::IsNullOrWhiteSpace($Pattern)) { [string]$manifest.pattern } else { $Pattern }
  if ([string]::IsNullOrWhiteSpace($patternName) -or $patternName -ne [string]$manifest.pattern) {
    throw (New-LizardLoopRuntimeException -Code 'LOOP_PATTERN_MISMATCH' -Message "Installed pattern is '$($manifest.pattern)', requested '$patternName'.")
  }
  $required = @('runtime_budget_file', 'runtime_state_file', 'runtime_events_file', 'runtime_lease_file')
  foreach ($field in $required) {
    if (-not ($manifest.PSObject.Properties.Name -contains $field) -or [string]::IsNullOrWhiteSpace([string]$manifest.$field)) {
      throw (New-LizardLoopRuntimeException -Code 'LOOP_RUNTIME_NOT_INITIALIZED' -Message "Manifest field '$field' is missing. Run loop-sync.ps1 -Apply after updating the layer.")
    }
  }
  function Resolve-ManifestPath([string]$Relative, [string]$Label) {
    if ([System.IO.Path]::IsPathRooted($Relative) -or $Relative -match '^[A-Za-z]:' -or $Relative.Replace('/', '\') -match '(^|\\)\.\.($|\\)') {
      throw (New-LizardLoopRuntimeException -Code 'LOOP_RUNTIME_PATH_INVALID' -Message "$Label must be a safe target-relative path: $Relative")
    }
    return Resolve-SafeTargetDestination -AuthorizedRoot $targetRoot -DestinationPath (Join-Path $targetRoot $Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
  }
  [pscustomobject][ordered]@{
    target_root = $targetRoot
    manifest_path = $manifestPath
    manifest = $manifest
    pattern = $patternName
    readiness_level = [string]$manifest.readiness_level
    budget_path = Resolve-ManifestPath ([string]$manifest.runtime_budget_file) 'runtime_budget_file'
    state_path = Resolve-ManifestPath ([string]$manifest.runtime_state_file) 'runtime_state_file'
    events_path = Resolve-ManifestPath ([string]$manifest.runtime_events_file) 'runtime_events_file'
    lease_path = Resolve-ManifestPath ([string]$manifest.runtime_lease_file) 'runtime_lease_file'
  }
}

function Get-LizardLoopRuntimeDocuments {
  param($Context)
  $budget = Read-LizardLoopJson -Path $Context.budget_path -Code 'LOOP_BUDGET_INVALID'
  $state = Read-LizardLoopJson -Path $Context.state_path -Code 'LOOP_STATE_INVALID'
  $lease = Read-LizardLoopJson -Path $Context.lease_path -Code 'LOOP_LEASE_INVALID'
  if ([string]$state.pattern -ne [string]$Context.pattern -or [string]$lease.pattern -ne [string]$Context.pattern) {
    throw (New-LizardLoopRuntimeException -Code 'LOOP_RUNTIME_PATTERN_INVALID' -Message 'Runtime state or lease belongs to another pattern.')
  }
  if ([int]$budget.schema_version -ne 1 -or [int]$state.schema_version -ne 1 -or [int]$lease.schema_version -ne 1) { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUNTIME_SCHEMA_UNSUPPORTED' -Message 'Runtime documents must use schema version 1.') }
  if ([int]$budget.daily_token_cap -lt 1 -or [int]$budget.max_runs_per_day -lt 1 -or [int]$budget.max_attempts_per_item -lt 1 -or [int]$budget.lease_minutes -lt 1) { throw (New-LizardLoopRuntimeException -Code 'LOOP_BUDGET_INVALID' -Message 'Runtime budget limits must be positive.') }
  if ([string]$budget.on_exceed -ne 'pause') { throw (New-LizardLoopRuntimeException -Code 'LOOP_BUDGET_POLICY_INVALID' -Message "Unsupported on_exceed policy '$($budget.on_exceed)'.") }
  if ([string]$state.status -notin @('idle', 'running', 'paused') -or [int]$state.revision -lt 0) { throw (New-LizardLoopRuntimeException -Code 'LOOP_STATE_INVALID' -Message 'Runtime state status or revision is invalid.') }
  if ([string]$lease.status -notin @('available', 'active', 'released', 'recovered')) { throw (New-LizardLoopRuntimeException -Code 'LOOP_LEASE_INVALID' -Message "Unsupported lease status '$($lease.status)'.") }
  if (([string]$lease.status -eq 'active') -ne (-not [string]::IsNullOrWhiteSpace([string]$state.active_run_id))) { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUNTIME_ATOMICITY_INVALID' -Message 'State and lease disagree about whether a run is active.') }
  if ([string]$lease.status -eq 'active' -and [string]$lease.run_id -ne [string]$state.active_run_id) { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUNTIME_ATOMICITY_INVALID' -Message 'State and lease active run IDs differ.') }
  [pscustomobject]@{ budget = $budget; state = $state; lease = $lease }
}

function Get-LizardLoopEvents {
  param($Context)
  if (-not (Test-Path -LiteralPath $Context.events_path -PathType Leaf)) {
    throw (New-LizardLoopRuntimeException -Code 'LOOP_EVENTS_MISSING' -Message "Event log is missing: $($Context.events_path)")
  }
  $events = New-Object System.Collections.Generic.List[object]
  $lineNumber = 0
  foreach ($line in @(Get-Content -LiteralPath $Context.events_path)) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
    try { $events.Add(($line | ConvertFrom-Json)) | Out-Null }
    catch { throw (New-LizardLoopRuntimeException -Code 'LOOP_EVENT_JSON_INVALID' -Message "Line $lineNumber is invalid JSON.") }
  }
  return @($events.ToArray())
}

function Test-LizardLoopEventChain {
  [CmdletBinding()]
  param($Context)
  $events = @(Get-LizardLoopEvents -Context $Context)
  $previous = $null
  $expectedSequence = 1
  foreach ($event in $events) {
    if ([int]$event.sequence -ne $expectedSequence) {
      throw (New-LizardLoopRuntimeException -Code 'LOOP_EVENT_SEQUENCE_INVALID' -Message "Expected event $expectedSequence, got $($event.sequence).")
    }
    if ([string]$event.pattern -ne [string]$Context.pattern) { throw (New-LizardLoopRuntimeException -Code 'LOOP_EVENT_PATTERN_INVALID' -Message "Event $expectedSequence belongs to another pattern.") }
    $declaredPrevious = if ($null -eq $event.previous_hash) { $null } else { [string]$event.previous_hash }
    if ($declaredPrevious -ne $previous) {
      throw (New-LizardLoopRuntimeException -Code 'LOOP_EVENT_CHAIN_BROKEN' -Message "Previous hash mismatch at event $expectedSequence.")
    }
    $payload = [ordered]@{
      schema_version = [int]$event.schema_version
      sequence = [int]$event.sequence
      run_id = [string]$event.run_id
      pattern = [string]$event.pattern
      event_type = [string]$event.event_type
      occurred_at = [string]$event.occurred_at
      actor = [string]$event.actor
      item_id = if ($null -eq $event.item_id) { $null } else { [string]$event.item_id }
      tokens = [int]$event.tokens
      previous_hash = $declaredPrevious
      details = $event.details
    }
    $actual = Get-LizardEvidencePayloadHash -Payload $payload
    if ($actual -ne [string]$event.event_hash) {
      throw (New-LizardLoopRuntimeException -Code 'LOOP_EVENT_HASH_MISMATCH' -Message "Event hash mismatch at event $expectedSequence.")
    }
    $previous = [string]$event.event_hash
    $expectedSequence++
  }
  $state = Read-LizardLoopJson -Path $Context.state_path -Code 'LOOP_STATE_INVALID'
  if ([int]$state.revision -ne $events.Count) { throw (New-LizardLoopRuntimeException -Code 'LOOP_EVENT_STATE_DIVERGED' -Message "State revision $($state.revision) does not match event count $($events.Count).") }
  [pscustomobject]@{ count = $events.Count; last_hash = $previous; events = $events }
}

function New-LizardLoopEvent {
  param($Context, [string]$RunId, [string]$EventType, [DateTime]$Now, [string]$Actor, [string]$ItemId, [int]$Tokens, $Details)
  $chain = Test-LizardLoopEventChain -Context $Context
  $payload = [ordered]@{
    schema_version = 1
    sequence = [int]$chain.count + 1
    run_id = $RunId
    pattern = [string]$Context.pattern
    event_type = $EventType
    occurred_at = $Now.ToString('o')
    actor = $Actor
    item_id = if ([string]::IsNullOrWhiteSpace($ItemId)) { $null } else { $ItemId }
    tokens = $Tokens
    previous_hash = $chain.last_hash
    details = $Details
  }
  $event = [ordered]@{}
  foreach ($key in $payload.Keys) { $event[$key] = $payload[$key] }
  $event['event_hash'] = Get-LizardEvidencePayloadHash -Payload $payload
  return [pscustomobject]$event
}

function Get-LizardLoopItem {
  param($State, [string]$ItemId, [switch]$Create)
  $item = @($State.items | Where-Object { [string]$_.id -eq $ItemId } | Select-Object -First 1)
  if ($item.Count -gt 0) { return $item[0] }
  if (-not $Create) { return $null }
  $newItem = [pscustomobject][ordered]@{ id = $ItemId; consecutive_attempts = 0; total_attempts = 0; failures = 0; status = 'ready'; last_run_id = $null }
  $State.items = @(@($State.items) + $newItem)
  return $newItem
}

function Reset-LizardLoopBudgetWindow {
  param($State, [DateTime]$Now)
  $date = $Now.ToString('yyyy-MM-dd')
  if ([string]$State.budget_window.date -ne $date) {
    $State.budget_window.date = $date
    $State.budget_window.runs_started = 0
    $State.budget_window.tokens_used = 0
  }
}

function Assert-LizardLoopLeaseAvailable {
  param($Lease, [DateTime]$Now)
  if ([string]$Lease.status -ne 'active') { return }
  $expires = [DateTimeOffset]::Parse([string]$Lease.expires_at).UtcDateTime
  if ($expires -le $Now) {
    throw (New-LizardLoopRuntimeException -Code 'LOOP_LEASE_STALE_RECOVERY_REQUIRED' -Message "Run '$($Lease.run_id)' owns a stale lease. Use loop-recover.ps1 with human approval.")
  }
  throw (New-LizardLoopRuntimeException -Code 'LOOP_LEASE_HELD' -Message "Run '$($Lease.run_id)' owns the lease until $($Lease.expires_at).")
}

function Invoke-LizardLoopStart {
  [CmdletBinding()]
  param($Context, [string]$RunId, [string]$ItemId, [string]$Owner, [int]$TokenEstimate, [string]$OperationId, [DateTime]$Now, [int]$FailAfterMutation = 0)
  if ([string]::IsNullOrWhiteSpace($RunId) -or $RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUN_ID_INVALID' -Message 'RunId is required and must be portable.') }
  if ([string]::IsNullOrWhiteSpace($ItemId)) { throw (New-LizardLoopRuntimeException -Code 'LOOP_ITEM_ID_REQUIRED' -Message 'ItemId is required.') }
  if ([string]::IsNullOrWhiteSpace($Owner)) { throw (New-LizardLoopRuntimeException -Code 'LOOP_OWNER_REQUIRED' -Message 'Owner is required.') }
  if ($TokenEstimate -lt 1) { throw (New-LizardLoopRuntimeException -Code 'LOOP_TOKEN_ESTIMATE_INVALID' -Message 'TokenEstimate must be positive.') }
  if ([string]$Context.readiness_level -eq 'L2' -and [string]::IsNullOrWhiteSpace($OperationId)) { throw (New-LizardLoopRuntimeException -Code 'LOOP_L2_OPERATION_REQUIRED' -Message 'L2 runs must bind to a worktree lifecycle operation ID.') }
  $documents = Get-LizardLoopRuntimeDocuments -Context $Context
  Test-LizardLoopEventChain -Context $Context | Out-Null
  Assert-LizardLoopLeaseAvailable -Lease $documents.lease -Now $Now
  $state = $documents.state
  $budget = $documents.budget
  Reset-LizardLoopBudgetWindow -State $state -Now $Now
  if (@($state.runs | Where-Object { [string]$_.run_id -eq $RunId }).Count -gt 0) { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUN_DUPLICATE' -Message "RunId '$RunId' already exists.") }
  if ([int]$state.budget_window.runs_started -ge [int]$budget.max_runs_per_day) { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUN_BUDGET_EXHAUSTED' -Message 'Daily run limit is exhausted.') }
  if (([int]$state.budget_window.tokens_used + $TokenEstimate) -gt [int]$budget.daily_token_cap) { throw (New-LizardLoopRuntimeException -Code 'LOOP_TOKEN_BUDGET_EXHAUSTED' -Message 'Daily token budget is exhausted.') }
  $item = Get-LizardLoopItem -State $state -ItemId $ItemId -Create
  if ([int]$item.consecutive_attempts -ge [int]$budget.max_attempts_per_item) { throw (New-LizardLoopRuntimeException -Code 'LOOP_ATTEMPT_BUDGET_EXHAUSTED' -Message "Item '$ItemId' reached its attempt limit.") }
  $startedAt = $Now.ToString('o')
  $expiresAt = $Now.AddMinutes([int]$budget.lease_minutes).ToString('o')
  $item.consecutive_attempts = [int]$item.consecutive_attempts + 1
  $item.total_attempts = [int]$item.total_attempts + 1
  $item.status = 'running'
  $item.last_run_id = $RunId
  $state.revision = [int]$state.revision + 1
  $state.status = 'running'
  $state.active_run_id = $RunId
  $state.updated_at = $startedAt
  $state.budget_window.runs_started = [int]$state.budget_window.runs_started + 1
  $state.budget_window.tokens_used = [int]$state.budget_window.tokens_used + $TokenEstimate
  $run = [pscustomobject][ordered]@{ run_id = $RunId; item_id = $ItemId; owner = $Owner; operation_id = if ([string]::IsNullOrWhiteSpace($OperationId)) { $null } else { $OperationId }; status = 'running'; started_at = $startedAt; completed_at = $null; token_estimate = $TokenEstimate; actual_tokens = $null; verifier_evidence_hash = $null }
  $state.runs = @(@($state.runs) + $run)
  $lease = [ordered]@{ schema_version = 1; pattern = [string]$Context.pattern; status = 'active'; run_id = $RunId; owner = $Owner; acquired_at = $startedAt; expires_at = $expiresAt; released_at = $null }
  $event = New-LizardLoopEvent -Context $Context -RunId $RunId -EventType 'started' -Now $Now -Actor $Owner -ItemId $ItemId -Tokens $TokenEstimate -Details ([pscustomobject][ordered]@{ operation_id = $run.operation_id; lease_expires_at = $expiresAt })
  $transaction = Start-LizardTransaction -TargetRoot $Context.target_root -OperationName 'loop-run-start' -FailAfterMutation $FailAfterMutation
  try {
    Set-LizardTransactionalContent -Path $Context.state_path -Value ($state | ConvertTo-Json -Depth 20)
    Set-LizardTransactionalContent -Path $Context.lease_path -Value ($lease | ConvertTo-Json -Depth 10)
    Add-LizardTransactionalContent -Path $Context.events_path -Value ($event | ConvertTo-Json -Depth 12 -Compress)
    Complete-LizardTransaction | Out-Null
  } catch {
    $caught = $_
    if (Test-Path -LiteralPath (Join-Path $Context.target_root '.lizard-agent-layer.lock')) { try { Undo-LizardTransaction | Out-Null } catch {} }
    throw $caught
  }
  [pscustomobject]@{ status = 'started'; run_id = $RunId; state_revision = $state.revision; lease_expires_at = $expiresAt; event_hash = $event.event_hash }
}

function Invoke-LizardLoopFinish {
  [CmdletBinding()]
  param($Context, [ValidateSet('completed', 'failed')][string]$Outcome, [string]$RunId, [string]$Actor, [int]$ActualTokens, [string]$Summary, [string]$VerifierEvidencePath, [DateTime]$Now, [int]$FailAfterMutation = 0)
  if ([string]::IsNullOrWhiteSpace($Actor)) { throw (New-LizardLoopRuntimeException -Code 'LOOP_ACTOR_REQUIRED' -Message 'Actor is required.') }
  $documents = Get-LizardLoopRuntimeDocuments -Context $Context
  Test-LizardLoopEventChain -Context $Context | Out-Null
  $state = $documents.state
  $lease = $documents.lease
  if ([string]$lease.status -ne 'active' -or [string]$lease.run_id -ne $RunId -or [string]$state.active_run_id -ne $RunId) { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUN_NOT_ACTIVE' -Message "Run '$RunId' does not own the active state and lease.") }
  $run = @($state.runs | Where-Object { [string]$_.run_id -eq $RunId } | Select-Object -First 1)
  if ($run.Count -eq 0 -or [string]$run[0].status -ne 'running') { throw (New-LizardLoopRuntimeException -Code 'LOOP_RUN_STATE_INVALID' -Message "Run '$RunId' is not running.") }
  $run = $run[0]
  $verifierHash = $null
  if ($Outcome -eq 'completed' -and [string]$Context.readiness_level -eq 'L2') {
    if ([string]::IsNullOrWhiteSpace($VerifierEvidencePath)) { throw (New-LizardLoopRuntimeException -Code 'LOOP_VERIFIER_REQUIRED' -Message 'L2 completion requires verifier evidence.') }
    $envelope = Read-LizardEvidenceEnvelope -Path $VerifierEvidencePath -SchemaVersion 1
    if ([string]$envelope.payload.effective_status -ne 'PASS') { throw (New-LizardLoopRuntimeException -Code 'LOOP_VERIFIER_REJECTED' -Message "Verifier status is '$($envelope.payload.effective_status)', expected PASS.") }
    if ([string]$envelope.payload.operation_id -ne [string]$run.operation_id) { throw (New-LizardLoopRuntimeException -Code 'LOOP_VERIFIER_OPERATION_MISMATCH' -Message 'Verifier evidence belongs to another lifecycle operation.') }
    $evidenceRoot = [System.IO.Path]::GetFullPath([string]$envelope.payload.target_root)
    if (-not $evidenceRoot.Equals([string]$Context.target_root, (Get-LizardPathComparison))) { throw (New-LizardLoopRuntimeException -Code 'LOOP_VERIFIER_TARGET_MISMATCH' -Message 'Verifier evidence belongs to another target.') }
    if ([bool]$envelope.payload.auto_merge -or -not [bool]$envelope.payload.human_merge_review_required) { throw (New-LizardLoopRuntimeException -Code 'LOOP_VERIFIER_POLICY_INVALID' -Message 'Verifier evidence violates no-auto-merge policy.') }
    $verifierHash = [string]$envelope.payload_hash
  }
  $actual = if ($ActualTokens -lt 0) { 0 } else { $ActualTokens }
  $state.budget_window.tokens_used = [Math]::Max(0, [int]$state.budget_window.tokens_used - [int]$run.token_estimate + $actual)
  $run.status = $Outcome
  $run.completed_at = $Now.ToString('o')
  $run.actual_tokens = $actual
  $run.verifier_evidence_hash = $verifierHash
  $item = Get-LizardLoopItem -State $state -ItemId ([string]$run.item_id)
  if ($Outcome -eq 'completed') { $item.consecutive_attempts = 0; $item.status = 'completed' }
  else { $item.failures = [int]$item.failures + 1; $item.status = if ([int]$item.consecutive_attempts -ge [int]$documents.budget.max_attempts_per_item) { 'blocked' } else { 'ready' } }
  $state.revision = [int]$state.revision + 1
  $state.active_run_id = $null
  $state.last_run_id = $RunId
  $state.updated_at = $Now.ToString('o')
  $state.status = if ([int]$state.budget_window.tokens_used -gt [int]$documents.budget.daily_token_cap -or [string]$item.status -eq 'blocked') { 'paused' } else { 'idle' }
  $lease.status = 'released'
  $lease.released_at = $Now.ToString('o')
  $event = New-LizardLoopEvent -Context $Context -RunId $RunId -EventType $Outcome -Now $Now -Actor $Actor -ItemId ([string]$run.item_id) -Tokens $actual -Details ([pscustomobject][ordered]@{ summary = $Summary; verifier_evidence_hash = $verifierHash })
  $transaction = Start-LizardTransaction -TargetRoot $Context.target_root -OperationName "loop-run-$Outcome" -FailAfterMutation $FailAfterMutation
  try {
    Set-LizardTransactionalContent -Path $Context.state_path -Value ($state | ConvertTo-Json -Depth 20)
    Set-LizardTransactionalContent -Path $Context.lease_path -Value ($lease | ConvertTo-Json -Depth 10)
    Add-LizardTransactionalContent -Path $Context.events_path -Value ($event | ConvertTo-Json -Depth 12 -Compress)
    Complete-LizardTransaction | Out-Null
  } catch {
    $caught = $_
    if (Test-Path -LiteralPath (Join-Path $Context.target_root '.lizard-agent-layer.lock')) { try { Undo-LizardTransaction | Out-Null } catch {} }
    throw $caught
  }
  [pscustomobject]@{ status = $Outcome; run_id = $RunId; state_revision = $state.revision; runtime_status = $state.status; event_hash = $event.event_hash }
}

function Invoke-LizardLoopRecovery {
  [CmdletBinding()]
  param($Context, [string]$RunId, [string]$Actor, [DateTime]$Now, [int]$FailAfterMutation = 0)
  if ([string]::IsNullOrWhiteSpace($Actor)) { throw (New-LizardLoopRuntimeException -Code 'LOOP_ACTOR_REQUIRED' -Message 'Actor is required.') }
  $documents = Get-LizardLoopRuntimeDocuments -Context $Context
  Test-LizardLoopEventChain -Context $Context | Out-Null
  $state = $documents.state
  $lease = $documents.lease
  if ([string]$lease.status -ne 'active' -or [string]$lease.run_id -ne $RunId) { throw (New-LizardLoopRuntimeException -Code 'LOOP_RECOVERY_NOT_AVAILABLE' -Message "Run '$RunId' has no active lease.") }
  if ([DateTimeOffset]::Parse([string]$lease.expires_at).UtcDateTime -gt $Now) { throw (New-LizardLoopRuntimeException -Code 'LOOP_LEASE_NOT_STALE' -Message "Lease remains active until $($lease.expires_at).") }
  $run = @($state.runs | Where-Object { [string]$_.run_id -eq $RunId } | Select-Object -First 1)
  if ($run.Count -eq 0 -or [string]$run[0].status -ne 'running') { throw (New-LizardLoopRuntimeException -Code 'LOOP_RECOVERY_STATE_INVALID' -Message 'Active lease has no matching running state.') }
  $run = $run[0]
  $run.status = 'recovered'
  $run.completed_at = $Now.ToString('o')
  $item = Get-LizardLoopItem -State $state -ItemId ([string]$run.item_id)
  $item.failures = [int]$item.failures + 1
  $item.status = if ([int]$item.consecutive_attempts -ge [int]$documents.budget.max_attempts_per_item) { 'blocked' } else { 'ready' }
  $state.revision = [int]$state.revision + 1
  $state.active_run_id = $null
  $state.last_run_id = $RunId
  $state.updated_at = $Now.ToString('o')
  $state.status = if ([string]$item.status -eq 'blocked') { 'paused' } else { 'idle' }
  $lease.status = 'recovered'
  $lease.released_at = $Now.ToString('o')
  $event = New-LizardLoopEvent -Context $Context -RunId $RunId -EventType 'recovered' -Now $Now -Actor $Actor -ItemId ([string]$run.item_id) -Tokens 0 -Details ([pscustomobject][ordered]@{ stale_since = [string]$lease.expires_at; human_approved = $true })
  $transaction = Start-LizardTransaction -TargetRoot $Context.target_root -OperationName 'loop-run-recover' -FailAfterMutation $FailAfterMutation
  try {
    Set-LizardTransactionalContent -Path $Context.state_path -Value ($state | ConvertTo-Json -Depth 20)
    Set-LizardTransactionalContent -Path $Context.lease_path -Value ($lease | ConvertTo-Json -Depth 10)
    Add-LizardTransactionalContent -Path $Context.events_path -Value ($event | ConvertTo-Json -Depth 12 -Compress)
    Complete-LizardTransaction | Out-Null
  } catch {
    $caught = $_
    if (Test-Path -LiteralPath (Join-Path $Context.target_root '.lizard-agent-layer.lock')) { try { Undo-LizardTransaction | Out-Null } catch {} }
    throw $caught
  }
  [pscustomobject]@{ status = 'recovered'; run_id = $RunId; state_revision = $state.revision; event_hash = $event.event_hash }
}

Export-ModuleMember -Function @(
  'ConvertTo-LizardLoopUtc', 'Get-LizardLoopRuntimeDocuments', 'Invoke-LizardLoopFinish',
  'Invoke-LizardLoopRecovery', 'Invoke-LizardLoopStart', 'Resolve-LizardLoopRuntimeContext',
  'Test-LizardLoopEventChain'
)
