param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.Json.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.LoopEvidence.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.Trust.psm1') -Force
Import-Module (Join-Path $RepoRoot 'tests\TestTrustHelpers.psm1') -Force
$testRoot = Join-Path $RepoRoot '.tmp\tests'
$fixture = Join-Path $testRoot ("loop-runtime-{0}" -f ([Guid]::NewGuid().ToString('N')))
$runScript = Join-Path $RepoRoot 'scripts\loop-run.ps1'
$recoverScript = Join-Path $RepoRoot 'scripts\loop-recover.ps1'
$initScript = Join-Path $RepoRoot 'scripts\loop-init.ps1'
$syncScript = Join-Path $RepoRoot 'scripts\loop-sync.ps1'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$clockOutside = Join-Path (Join-Path $RepoRoot '.tmp') ("loop-clock-outside-{0}" -f ([Guid]::NewGuid().ToString('N')))
$script:reportIndex = 0

function Invoke-LoopRun {
  param([string]$Target, [string[]]$Arguments)
  $script:reportIndex++
  Invoke-TestPowerShell -ScriptPath $runScript -Arguments (@('-LayerRoot', $RepoRoot, '-TargetPath', $Target, '-OutputDir', (Join-Path $fixture ("report-{0:D3}" -f $script:reportIndex))) + $Arguments)
}
function Initialize-LoopTarget {
  param([string]$Name, [string]$Pattern = 'daily-triage')
  $target = Join-Path $fixture $Name
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  $result = Invoke-TestPowerShell -ScriptPath $initScript -Arguments @('-LayerRoot', $RepoRoot, '-TargetPath', $target, '-Pattern', $Pattern, '-Apply', '-OutputDir', (Join-Path $fixture "init-$Name"))
  Assert-Equal 0 $result.exit_code "Loop init failed for $Name`: $($result.output)"
  return $target
}
function Get-RuntimePaths {
  param([string]$Target)
  $manifest = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath (Join-Path $Target '.agent\loops\lizard-agent-layer.loop-install.json') -Raw)
  [pscustomobject]@{
    state = Join-Path $Target ([string]$manifest.runtime_state_file).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    budget = Join-Path $Target ([string]$manifest.runtime_budget_file).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    events = Join-Path $Target ([string]$manifest.runtime_events_file).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    lease = Join-Path $Target ([string]$manifest.runtime_lease_file).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
  }
}
function Write-VerifierEvidence {
  param([string]$Path, [string]$Target, [string]$OperationId, [string]$Status, [DateTimeOffset]$Now, [switch]$Signed)
  $payload = [pscustomobject][ordered]@{
    operation_id = $OperationId; lifecycle_path = 'fixture'; lifecycle_hash = ('b' * 64)
    requested_status = $Status; effective_status = $Status; verifier = 'independent-verifier'; implementer = 'implementation-agent'
    verified_at = '2026-07-12T08:05:00Z'; head_sha = ('c' * 40); git_state_hash = ('d' * 64)
    verification_plan_id = ('e' * 32); verification_plan_sha256 = ('f' * 64); verification_runner_id = 'lizard-constrained-verifier-v1'
    commands = @([pscustomobject]@{ command_id = 'git-head'; started_at = '2026-07-12T08:04:00Z'; completed_at = '2026-07-12T08:04:01Z'; exit_code = if ($Status -eq 'PASS') { 0 } else { 1 }; expected_exit_codes = @(0); timed_out = $false; output_sha256 = ('a' * 64); output_bytes = 41 }); evidence_files = @()
    auto_merge = $false; human_merge_review_required = $true; target_root = [System.IO.Path]::GetFullPath($Target)
  }
  $trust = $null
  if ($Signed) {
    $worktree = Join-Path $fixture ("lifecycle-worktree-{0}" -f ([Guid]::NewGuid().ToString('N'))); New-Item -ItemType Directory -Path $worktree -Force | Out-Null
    $baseSha = ('9' * 40)
    $lifecycleBinding = Get-LizardLifecycleTrustBinding -OperationId $OperationId -TargetRoot $Target -WorktreeRoot $worktree -Branch 'lizard/runtime-test' -BaseSha $baseSha
    $lifecycleTrust = New-LizardTestTrustMaterial -Root (Join-Path $fixture ("lifecycle-trust-{0}" -f ([Guid]::NewGuid().ToString('N')))) -BindingSha256 $lifecycleBinding -Subject $OperationId -Now $Now -PrincipalId 'implementation-agent' -Roles @('implementer') -Purpose 'worktree-registration' -PayloadKind 'worktree-lifecycle'
    $lifecyclePayload = [pscustomobject][ordered]@{ operation_id = $OperationId; status = 'CREATED'; target_root = [IO.Path]::GetFullPath($Target); worktree_root = [IO.Path]::GetFullPath($worktree); branch = 'lizard/runtime-test'; base_sha = $baseSha; auto_merge = $false }
    $lifecycleEnvelope = New-LizardSignedEvidenceEnvelope -Payload $lifecyclePayload -PayloadKind worktree-lifecycle -Purpose worktree-registration -Subject $OperationId -BindingSha256 $lifecycleBinding -ChallengePath $lifecycleTrust.challenge_path -ChallengeSha256 $lifecycleTrust.challenge_sha256 -PrivateKeyPath $lifecycleTrust.private_key_path -PrivateKeySha256 $lifecycleTrust.private_key_sha256 -Now $Now
    $lifecyclePath = Join-Path $fixture ("lifecycle-{0}.json" -f ([Guid]::NewGuid().ToString('N'))); [IO.File]::WriteAllText($lifecyclePath, ($lifecycleEnvelope | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    $payload.lifecycle_path = $lifecyclePath; $payload.lifecycle_hash = [string]$lifecycleEnvelope.payload_sha256
    $payload | Add-Member -NotePropertyName authenticated_implementer -NotePropertyValue 'implementation-agent'
    $binding = Get-LizardVerifierTrustBinding -OperationId $OperationId -LifecycleHash $payload.lifecycle_hash -VerificationPlanSha256 $payload.verification_plan_sha256 -TargetRoot $Target
    $trust = New-LizardTestTrustMaterial -Root (Join-Path $fixture ("trust-{0}" -f ([Guid]::NewGuid().ToString('N')))) -BindingSha256 $binding -Subject $OperationId -Now $Now -PrincipalId 'independent-verifier'
    $envelope = New-LizardSignedEvidenceEnvelope -Payload $payload -PayloadKind verifier-evidence -Purpose loop-completion -Subject $OperationId -BindingSha256 $binding -ChallengePath $trust.challenge_path -ChallengeSha256 $trust.challenge_sha256 -PrivateKeyPath $trust.private_key_path -PrivateKeySha256 $trust.private_key_sha256 -Now $Now
    $trust | Add-Member -NotePropertyName lifecycle_trust_store_path -NotePropertyValue $lifecycleTrust.trust_store_path
    $trust | Add-Member -NotePropertyName lifecycle_trust_store_sha256 -NotePropertyValue $lifecycleTrust.trust_store_sha256
    $trust | Add-Member -NotePropertyName lifecycle_challenge_path -NotePropertyValue $lifecycleTrust.challenge_path
    $trust | Add-Member -NotePropertyName lifecycle_challenge_sha256 -NotePropertyValue $lifecycleTrust.challenge_sha256
  } else { $envelope = New-LizardEvidenceEnvelope -SchemaVersion 1 -Payload $payload }
  [System.IO.File]::WriteAllText($Path, ($envelope | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
  return $trust
}

try {
  # Valid lifecycle, preview immutability, active lease, duplicate ID, and executable schemas.
  $happy = Initialize-LoopTarget 'happy'
  $paths = Get-RuntimePaths $happy
  $before = (Get-FileHash -LiteralPath $paths.state -Algorithm SHA256).Hash
  $preview = Invoke-LoopRun $happy @('-Action', 'Start', '-RunId', 'preview-1', '-ItemId', 'item-1', '-Owner', 'cheap-agent', '-TokenEstimate', '100')
  Assert-Equal 0 $preview.exit_code "Preview failed: $($preview.output)"
  Assert-Equal $before (Get-FileHash -LiteralPath $paths.state -Algorithm SHA256).Hash 'Preview must not mutate runtime state.'
  $start = Invoke-LoopRun $happy @('-Action', 'Start', '-RunId', 'run-1', '-ItemId', 'item-1', '-Owner', 'cheap-agent', '-TokenEstimate', '100', '-TestNowUtc', '2026-07-12T08:00:00Z', '-Apply')
  Assert-Equal 0 $start.exit_code "Valid start failed: $($start.output)"
  $state = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $paths.state -Raw)
  $lease = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $paths.lease -Raw)
  Assert-Equal 'running' ([string]$state.status) 'Start must mark runtime running.'
  Assert-Equal 'active' ([string]$lease.status) 'Start must acquire one active lease.'
  Assert-Equal 1 ([int]$state.budget_window.runs_started) 'Start must consume one run.'
  Assert-Equal 100 ([int]$state.budget_window.tokens_used) 'Start must reserve tokens once.'
  $held = Invoke-LoopRun $happy @('-Action', 'Start', '-RunId', 'run-2', '-ItemId', 'item-2', '-Owner', 'agent', '-TokenEstimate', '20', '-TestNowUtc', '2026-07-12T08:01:00Z', '-Apply')
  Assert-False ($held.exit_code -eq 0) 'A second active run must fail.'
  Assert-True ($held.output -match 'LOOP_LEASE_HELD') "Active lease failure must be explicit. Output: $($held.output)"
  $complete = Invoke-LoopRun $happy @('-Action', 'Complete', '-RunId', 'run-1', '-Owner', 'cheap-agent', '-ActualTokens', '80', '-TestNowUtc', '2026-07-12T08:02:00Z', '-Apply')
  Assert-Equal 0 $complete.exit_code "Completion failed: $($complete.output)"
  $state = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $paths.state -Raw)
  $lease = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $paths.lease -Raw)
  Assert-Equal 'idle' ([string]$state.status) 'Completion must return to idle.'
  Assert-Equal 'released' ([string]$lease.status) 'Completion must release lease.'
  Assert-Equal 80 ([int]$state.budget_window.tokens_used) 'Completion must reconcile token usage.'
  Assert-Equal 2 @((Get-Content -LiteralPath $paths.events) | Where-Object { $_ }).Count 'A valid run needs exactly two events.'
  Assert-JsonSchemaValid $RepoRoot 'schemas/loop-runtime-report.schema.json' (Join-Path $fixture 'report-004\loop-run-report.json') 'Generated runtime report must satisfy schema.'
  $duplicate = Invoke-LoopRun $happy @('-Action', 'Start', '-RunId', 'run-1', '-ItemId', 'item-1', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', '2026-07-12T08:03:00Z', '-Apply')
  Assert-False ($duplicate.exit_code -eq 0) 'RunId reuse must fail.'
  Assert-True ($duplicate.output -match 'LOOP_RUN_DUPLICATE') 'RunId reuse must expose stable code.'
  Assert-JsonSchemaValid $RepoRoot 'schemas/loop-runtime-state.schema.json' $paths.state 'Generated runtime state must satisfy schema.'
  Assert-JsonSchemaValid $RepoRoot 'schemas/loop-runtime-lease.schema.json' $paths.lease 'Generated runtime lease must satisfy schema.'
  $eventIndex = 0
  foreach ($line in @(Get-Content -LiteralPath $paths.events | Where-Object { $_ })) {
    $eventIndex++; $eventPath = Join-Path $fixture "event-$eventIndex.json"
    [System.IO.File]::WriteAllText($eventPath, $line, (New-Object System.Text.UTF8Encoding($false)))
    Assert-JsonSchemaValid $RepoRoot 'schemas/loop-runtime-event.schema.json' $eventPath 'Generated event must satisfy schema.'
  }

  New-Item -ItemType Directory -Path $clockOutside -Force | Out-Null
  $outsideInit = Invoke-TestPowerShell $initScript @('-LayerRoot', $RepoRoot, '-TargetPath', $clockOutside, '-Pattern', 'daily-triage', '-Apply', '-OutputDir', (Join-Path $fixture 'clock-outside-init'))
  Assert-Equal 0 $outsideInit.exit_code "Clock-boundary fixture init failed: $($outsideInit.output)"
  $clockBypass = Invoke-LoopRun $clockOutside @('-Action', 'Start', '-RunId', 'clock-bypass', '-ItemId', 'item', '-Owner', 'agent', '-TokenEstimate', '1', '-TestNowUtc', '2099-01-01T00:00:00Z', '-Apply')
  Assert-False ($clockBypass.exit_code -eq 0) 'Synthetic time must be unavailable to production targets.'
  Assert-True ($clockBypass.output -match 'LOOP_TEST_CLOCK_FORBIDDEN') 'Test clock boundary must expose stable error.'

  # Additive migration for installations created before executable runtime fields existed.
  $legacy = Initialize-LoopTarget 'legacy'; $legacyPaths = Get-RuntimePaths $legacy
  Remove-Item -LiteralPath @($legacyPaths.state, $legacyPaths.budget, $legacyPaths.events, $legacyPaths.lease) -Force
  $legacyManifestPath = Join-Path $legacy '.agent\loops\lizard-agent-layer.loop-install.json'
  $legacyManifest = ConvertFrom-LizardJson -InputObject (Get-Content $legacyManifestPath -Raw)
  foreach ($name in @('runtime_budget_file', 'runtime_state_file', 'runtime_events_file', 'runtime_lease_file')) { $legacyManifest.PSObject.Properties.Remove($name) }
  $legacyManifest | ConvertTo-Json -Depth 12 | Set-Content $legacyManifestPath -Encoding UTF8
  $sync = Invoke-TestPowerShell $syncScript @('-LayerRoot', $RepoRoot, '-TargetPath', $legacy, '-Apply', '-OutputDir', (Join-Path $fixture 'legacy-sync'))
  Assert-Equal 0 $sync.exit_code "Legacy runtime sync failed: $($sync.output)"
  $migrated = ConvertFrom-LizardJson -InputObject (Get-Content $legacyManifestPath -Raw)
  foreach ($name in @('runtime_budget_file', 'runtime_state_file', 'runtime_events_file', 'runtime_lease_file')) {
    Assert-True ($migrated.PSObject.Properties.Name -contains $name) "Sync must add $name."
    Assert-True (Test-Path (Join-Path $legacy ([string]$migrated.$name).Replace('/', [System.IO.Path]::DirectorySeparatorChar))) "Sync must create $name."
  }

  # Atomic transition rollback.
  $fault = Initialize-LoopTarget 'fault'; $faultPaths = Get-RuntimePaths $fault
  $hashes = @((Get-FileHash $faultPaths.state -Algorithm SHA256).Hash, (Get-FileHash $faultPaths.lease -Algorithm SHA256).Hash, (Get-FileHash $faultPaths.events -Algorithm SHA256).Hash)
  $faulted = Invoke-LoopRun $fault @('-Action', 'Start', '-RunId', 'fault-1', '-ItemId', 'item', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', '2026-07-12T08:00:00Z', '-Apply', '-TestFailAfterMutation', '2')
  Assert-False ($faulted.exit_code -eq 0) 'Fault injection must fail.'
  Assert-Equal $hashes[0] (Get-FileHash $faultPaths.state -Algorithm SHA256).Hash 'Rollback must restore state.'
  Assert-Equal $hashes[1] (Get-FileHash $faultPaths.lease -Algorithm SHA256).Hash 'Rollback must restore lease.'
  Assert-Equal $hashes[2] (Get-FileHash $faultPaths.events -Algorithm SHA256).Hash 'Rollback must restore events.'
  Assert-False (Test-Path (Join-Path $fault '.lizard-agent-layer.lock')) 'Rollback must remove transaction lock.'

  # Run/token budgets.
  $budgetTarget = Initialize-LoopTarget 'budget'; $budgetPaths = Get-RuntimePaths $budgetTarget
  $budget = ConvertFrom-LizardJson -InputObject (Get-Content $budgetPaths.budget -Raw); $budget.max_runs_per_day = 1; $budget.daily_token_cap = 50; $budget | ConvertTo-Json | Set-Content $budgetPaths.budget -Encoding UTF8
  Assert-Equal 0 (Invoke-LoopRun $budgetTarget @('-Action', 'Start', '-RunId', 'budget-1', '-ItemId', 'item', '-Owner', 'agent', '-TokenEstimate', '50', '-TestNowUtc', '2026-07-12T08:00:00Z', '-Apply')).exit_code 'First budgeted start must pass.'
  Assert-Equal 0 (Invoke-LoopRun $budgetTarget @('-Action', 'Complete', '-RunId', 'budget-1', '-Owner', 'agent', '-ActualTokens', '50', '-TestNowUtc', '2026-07-12T08:01:00Z', '-Apply')).exit_code 'Budgeted completion must pass.'
  $exhausted = Invoke-LoopRun $budgetTarget @('-Action', 'Start', '-RunId', 'budget-2', '-ItemId', 'item-2', '-Owner', 'agent', '-TokenEstimate', '1', '-TestNowUtc', '2026-07-12T08:02:00Z', '-Apply')
  Assert-False ($exhausted.exit_code -eq 0) 'Exhausted run budget must fail.'
  Assert-True ($exhausted.output -match 'LOOP_RUN_BUDGET_EXHAUSTED') 'Budget failure must be explicit.'

  # Crash/restart and stale-lease recovery.
  $recovery = Initialize-LoopTarget 'recovery'
  Assert-Equal 0 (Invoke-LoopRun $recovery @('-Action', 'Start', '-RunId', 'crash-1', '-ItemId', 'item', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', '2026-07-12T08:00:00Z', '-Apply')).exit_code 'Crash fixture start must pass.'
  $stale = Invoke-LoopRun $recovery @('-Action', 'Start', '-RunId', 'crash-2', '-ItemId', 'other', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', '2026-07-12T09:00:00Z', '-Apply')
  Assert-False ($stale.exit_code -eq 0) 'Stale lease must fail closed.'
  Assert-True ($stale.output -match 'LOOP_LEASE_STALE_RECOVERY_REQUIRED') "Stale lease must require recovery. Output: $($stale.output)"
  $previewRecovery = Invoke-TestPowerShell $recoverScript @('-LayerRoot', $RepoRoot, '-TargetPath', $recovery, '-RunId', 'crash-1', '-TestNowUtc', '2026-07-12T09:00:00Z', '-OutputDir', (Join-Path $fixture 'recover-preview'), '-Json')
  Assert-Equal 0 $previewRecovery.exit_code "Recovery preview failed: $($previewRecovery.output)"
  Assert-True ($previewRecovery.output -match 'recovery-available') 'Recovery preview must find stale lease.'
  $noApproval = Invoke-TestPowerShell $recoverScript @('-LayerRoot', $RepoRoot, '-TargetPath', $recovery, '-RunId', 'crash-1', '-TestNowUtc', '2026-07-12T09:00:00Z', '-OutputDir', (Join-Path $fixture 'recover-denied'), '-Apply')
  Assert-False ($noApproval.exit_code -eq 0) 'Recovery apply must require human approval.'
  Assert-True ($noApproval.output -match 'LOOP_RECOVERY_HUMAN_APPROVAL_REQUIRED') 'Recovery gate must be explicit.'
  $approved = Invoke-TestPowerShell $recoverScript @('-LayerRoot', $RepoRoot, '-TargetPath', $recovery, '-RunId', 'crash-1', '-Actor', 'operator', '-TestNowUtc', '2026-07-12T09:00:00Z', '-OutputDir', (Join-Path $fixture 'recover-apply'), '-Apply', '-HumanApproved')
  Assert-Equal 0 $approved.exit_code "Approved recovery failed: $($approved.output)"
  Assert-Equal 0 (Invoke-LoopRun $recovery @('-Action', 'Start', '-RunId', 'crash-2', '-ItemId', 'other', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', '2026-07-12T09:01:00Z', '-Apply')).exit_code 'Recovered runtime must accept a new run.'

  # Repeated failure accounting.
  $attempts = Initialize-LoopTarget 'attempts'; $attemptPaths = Get-RuntimePaths $attempts
  $attemptBudget = ConvertFrom-LizardJson -InputObject (Get-Content $attemptPaths.budget -Raw); $attemptBudget.max_attempts_per_item = 2; $attemptBudget | ConvertTo-Json | Set-Content $attemptPaths.budget -Encoding UTF8
  foreach ($n in 1..2) {
    Assert-Equal 0 (Invoke-LoopRun $attempts @('-Action', 'Start', '-RunId', "attempt-$n", '-ItemId', 'unstable', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', "2026-07-12T08:0${n}:00Z", '-Apply')).exit_code "Attempt $n start must pass."
    Assert-Equal 0 (Invoke-LoopRun $attempts @('-Action', 'Fail', '-RunId', "attempt-$n", '-Owner', 'agent', '-ActualTokens', '10', '-TestNowUtc', "2026-07-12T08:1${n}:00Z", '-Apply')).exit_code "Attempt $n failure must record."
  }
  $blocked = Invoke-LoopRun $attempts @('-Action', 'Start', '-RunId', 'attempt-3', '-ItemId', 'unstable', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', '2026-07-12T08:30:00Z', '-Apply')
  Assert-False ($blocked.exit_code -eq 0) 'Max attempts must block another run.'
  Assert-True ($blocked.output -match 'LOOP_ATTEMPT_BUDGET_EXHAUSTED') 'Attempt exhaustion must be explicit.'

  # L2 completion requires a PASS envelope bound to the lifecycle operation and target.
  $l2 = Initialize-LoopTarget 'l2' 'minimal-fix-assist'
  $l2Operation = ('1' * 32)
  Assert-Equal 0 (Invoke-LoopRun $l2 @('-Action', 'Start', '-RunId', 'l2-run', '-ItemId', 'fix-1', '-Owner', 'implementation-agent', '-OperationId', $l2Operation, '-TokenEstimate', '100', '-TestNowUtc', '2026-07-12T08:00:00Z', '-Apply')).exit_code 'L2 start must bind an operation.'
  $missingVerifier = Invoke-LoopRun $l2 @('-Action', 'Complete', '-RunId', 'l2-run', '-Owner', 'implementation-agent', '-ActualTokens', '90', '-TestNowUtc', '2026-07-12T08:05:00Z', '-Apply')
  Assert-False ($missingVerifier.exit_code -eq 0) 'L2 completion without evidence must fail.'
  Assert-True ($missingVerifier.output -match 'LOOP_VERIFIER_REQUIRED') 'Missing L2 verifier must be explicit.'
  $rejectPath = Join-Path $fixture 'verifier-reject.json'; Write-VerifierEvidence $rejectPath $l2 $l2Operation 'FAIL' ([DateTimeOffset]'2026-07-12T08:06:00Z') | Out-Null
  $rejected = Invoke-LoopRun $l2 @('-Action', 'Complete', '-RunId', 'l2-run', '-Owner', 'implementation-agent', '-ActualTokens', '90', '-VerifierEvidencePath', $rejectPath, '-TestNowUtc', '2026-07-12T08:06:00Z', '-Apply')
  Assert-False ($rejected.exit_code -eq 0) 'Rejected verifier must fail completion.'
  Assert-True ($rejected.output -match 'LOOP_VERIFIER_REJECTED') 'Verifier rejection must be explicit.'
  $syntheticPassPath = Join-Path $fixture 'verifier-synthetic-pass.json'; Write-VerifierEvidence $syntheticPassPath $l2 $l2Operation 'PASS' ([DateTimeOffset]'2026-07-12T08:07:00Z') | Out-Null
  $syntheticPass = Invoke-LoopRun $l2 @('-Action', 'Complete', '-RunId', 'l2-run', '-Owner', 'implementation-agent', '-ActualTokens', '90', '-VerifierEvidencePath', $syntheticPassPath, '-TestNowUtc', '2026-07-12T08:07:00Z', '-Apply')
  Assert-False ($syntheticPass.exit_code -eq 0) 'An unkeyed synthetic PASS envelope must fail closed.'
  Assert-True ($syntheticPass.output -match 'LOOP_TRUST_INPUT_REQUIRED') 'Synthetic PASS rejection must require the external trust contract.'
  $passPath = Join-Path $fixture 'verifier-pass.json'; $l2Trust = Write-VerifierEvidence $passPath $l2 $l2Operation 'PASS' ([DateTimeOffset]'2026-07-12T08:07:00Z') -Signed
  $verified = Invoke-LoopRun $l2 @('-Action', 'Complete', '-RunId', 'l2-run', '-Owner', 'implementation-agent', '-ActualTokens', '90', '-VerifierEvidencePath', $passPath, '-TrustStorePath', $l2Trust.trust_store_path, '-TrustStoreSha256', $l2Trust.trust_store_sha256, '-TrustChallengePath', $l2Trust.challenge_path, '-TrustChallengeSha256', $l2Trust.challenge_sha256, '-LifecycleTrustStorePath', $l2Trust.lifecycle_trust_store_path, '-LifecycleTrustStoreSha256', $l2Trust.lifecycle_trust_store_sha256, '-LifecycleChallengePath', $l2Trust.lifecycle_challenge_path, '-LifecycleChallengeSha256', $l2Trust.lifecycle_challenge_sha256, '-ReplayLedgerPath', $l2Trust.replay_ledger_path, '-TestNowUtc', '2026-07-12T08:07:00Z', '-Apply')
  Assert-Equal 0 $verified.exit_code "Valid verifier must complete L2: $($verified.output)"
  $l2State = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath (Get-RuntimePaths $l2).state -Raw)
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$l2State.runs[0].verifier_evidence_hash)) 'L2 state must retain verifier evidence hash.'

  # Append-only event integrity.
  $tamper = Initialize-LoopTarget 'tamper'; $tamperPaths = Get-RuntimePaths $tamper
  Assert-Equal 0 (Invoke-LoopRun $tamper @('-Action', 'Start', '-RunId', 'tamper-1', '-ItemId', 'item', '-Owner', 'agent', '-TokenEstimate', '10', '-TestNowUtc', '2026-07-12T08:00:00Z', '-Apply')).exit_code 'Tamper fixture start must pass.'
  $event = ConvertFrom-LizardJson -InputObject (Get-Content $tamperPaths.events -Raw); $event.tokens = 999; $event | ConvertTo-Json -Compress | Set-Content $tamperPaths.events -Encoding UTF8
  $tampered = Invoke-LoopRun $tamper @('-Action', 'Status')
  Assert-False ($tampered.exit_code -eq 0) 'Tampered event chain must fail closed.'
  Assert-True ($tampered.output -match 'LOOP_EVENT_HASH_MISMATCH') 'Tamper failure must identify hash mismatch.'

  Write-Host 'PASS tests\integration\loop-runtime.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
  if (Test-Path -LiteralPath $clockOutside) { Clear-TestDirectory -Path $clockOutside -AllowedRoot (Join-Path $RepoRoot '.tmp') }
}
