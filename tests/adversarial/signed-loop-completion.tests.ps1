param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'tests/TestTrustHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.LoopEvidence.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Trust.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp/tests'
$fixture = Join-Path $testRoot ("signed-loop-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'; $operation = ('1' * 32); $now = [DateTimeOffset]'2026-08-22T10:00:00Z'
function Invoke-Run { param([string[]]$Arguments, [string]$Name) Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts/loop-run.ps1') -Arguments (@('-LayerRoot', $LayerRoot, '-TargetPath', $target, '-OutputDir', (Join-Path $fixture $Name)) + $Arguments) }
try {
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  $init = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts/loop-init.ps1') -Arguments @('-LayerRoot', $LayerRoot, '-TargetPath', $target, '-Pattern', 'minimal-fix-assist', '-Apply', '-OutputDir', (Join-Path $fixture 'init'))
  Assert-Equal 0 $init.exit_code "Loop init failed: $($init.output)"
  $start = Invoke-Run @('-Action','Start','-RunId','signed-1','-ItemId','fix','-Owner','implementer-01','-OperationId',$operation,'-TokenEstimate','10','-TestNowUtc',$now.ToString('o'),'-Apply') 'start'
  Assert-Equal 0 $start.exit_code "Signed loop start failed: $($start.output)"
  $worktree = Join-Path $fixture 'worktree'; New-Item -ItemType Directory -Path $worktree -Force | Out-Null
  $baseSha = ('b' * 40); $planHash = ('f' * 64)
  $lifecycleBinding = Get-LizardLifecycleTrustBinding -OperationId $operation -TargetRoot $target -WorktreeRoot $worktree -Branch 'lizard/test' -BaseSha $baseSha
  $lifecycleTrust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'lifecycle-trust') -BindingSha256 $lifecycleBinding -Subject $operation -Now $now -PrincipalId 'implementer-01' -Roles @('implementer') -Purpose 'worktree-registration' -PayloadKind 'worktree-lifecycle'
  $lifecyclePayload = [pscustomobject][ordered]@{ operation_id = $operation; status = 'CREATED'; target_root = (Resolve-Path $target).Path; worktree_root = (Resolve-Path $worktree).Path; branch = 'lizard/test'; base_sha = $baseSha; auto_merge = $false }
  $lifecycleEnvelope = New-LizardSignedEvidenceEnvelope -Payload $lifecyclePayload -PayloadKind worktree-lifecycle -Purpose worktree-registration -Subject $operation -BindingSha256 $lifecycleBinding -ChallengePath $lifecycleTrust.challenge_path -ChallengeSha256 $lifecycleTrust.challenge_sha256 -PrivateKeyPath $lifecycleTrust.private_key_path -PrivateKeySha256 $lifecycleTrust.private_key_sha256 -Now $now
  $lifecyclePath = Join-Path $fixture 'lifecycle.json'; [IO.File]::WriteAllText($lifecyclePath, ($lifecycleEnvelope | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  $lifecycleHash = [string]$lifecycleEnvelope.payload_sha256
  $binding = Get-LizardVerifierTrustBinding -OperationId $operation -LifecycleHash $lifecycleHash -VerificationPlanSha256 $planHash -TargetRoot $target
  $trust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'trust') -BindingSha256 $binding -Subject $operation -Now $now -PrincipalId 'verifier-01'
  $payload = [pscustomobject][ordered]@{
    operation_id = $operation; lifecycle_path = $lifecyclePath; lifecycle_hash = $lifecycleHash; requested_status = 'PASS'; effective_status = 'PASS'
    verifier = 'verifier-01'; implementer = 'implementer-01'; authenticated_implementer = 'implementer-01'; verified_at = $now.ToString('o'); target_root = (Resolve-Path $target).Path
    head_sha = ('c' * 40); git_state_hash = ('d' * 64); verification_plan_id = ('e' * 32); verification_plan_sha256 = $planHash
    verification_runner_id = 'lizard-constrained-verifier-v1'; commands = @([pscustomobject][ordered]@{ command_id = 'git-head'; started_at = $now.ToString('o'); completed_at = $now.ToString('o'); exit_code = 0; expected_exit_codes = @(0); timed_out = $false; output_sha256 = ('a' * 64); output_bytes = 41 })
    evidence_files = @(); auto_merge = $false; human_merge_review_required = $true
  }
  $envelope = New-LizardSignedEvidenceEnvelope -Payload $payload -PayloadKind verifier-evidence -Purpose loop-completion -Subject $operation -BindingSha256 $binding -ChallengePath $trust.challenge_path -ChallengeSha256 $trust.challenge_sha256 -PrivateKeyPath $trust.private_key_path -PrivateKeySha256 $trust.private_key_sha256 -Now $now
  $evidencePath = Join-Path $fixture 'verifier.evidence.json'; [IO.File]::WriteAllText($evidencePath, ($envelope | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  $args = @('-Action','Complete','-RunId','signed-1','-Owner','implementer-01','-ActualTokens','9','-VerifierEvidencePath',$evidencePath,'-TrustStorePath',$trust.trust_store_path,'-TrustStoreSha256',$trust.trust_store_sha256,'-TrustChallengePath',$trust.challenge_path,'-TrustChallengeSha256',$trust.challenge_sha256,'-LifecycleTrustStorePath',$lifecycleTrust.trust_store_path,'-LifecycleTrustStoreSha256',$lifecycleTrust.trust_store_sha256,'-LifecycleChallengePath',$lifecycleTrust.challenge_path,'-LifecycleChallengeSha256',$lifecycleTrust.challenge_sha256,'-ReplayLedgerPath',$trust.replay_ledger_path,'-TestNowUtc',$now.ToString('o'),'-Apply')
  $complete = Invoke-Run $args 'complete'
  Assert-Equal 0 $complete.exit_code "Authentic signed PASS must complete L2: $($complete.output)"
  Assert-True (Test-Path -LiteralPath $trust.replay_ledger_path) 'Completion must consume the challenge nonce in an external replay ledger.'

  $secondStart = Invoke-Run @('-Action','Start','-RunId','signed-2','-ItemId','fix-2','-Owner','implementer-01','-OperationId',$operation,'-TokenEstimate','10','-TestNowUtc',$now.AddMinutes(1).ToString('o'),'-Apply') 'start-2'
  Assert-Equal 0 $secondStart.exit_code "Second run start failed: $($secondStart.output)"
  $replayArgs = @($args); $replayArgs[3] = 'signed-2'; $timeIndex = [Array]::IndexOf($replayArgs, '-TestNowUtc'); $replayArgs[$timeIndex + 1] = $now.AddMinutes(1).ToString('o')
  $replay = Invoke-Run $replayArgs 'replay'
  Assert-False ($replay.exit_code -eq 0) 'A consumed signed PASS must not complete another run.'
  Assert-True ($replay.output -match 'TRUST_REPLAY_DETECTED') "Replay rejection must be explicit: $($replay.output)"

  $forged = $envelope | ConvertTo-Json -Depth 20 | ConvertFrom-LizardJson; $forged.payload.head_sha = ('9' * 40)
  $forgedPath = Join-Path $fixture 'forged.json'; [IO.File]::WriteAllText($forgedPath, ($forged | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  $forgedArgs = @($replayArgs); $evidenceIndex = [Array]::IndexOf($forgedArgs, '-VerifierEvidencePath'); $forgedArgs[$evidenceIndex + 1] = $forgedPath
  $forgedResult = Invoke-Run $forgedArgs 'forged'
  Assert-False ($forgedResult.exit_code -eq 0) 'Tampered signed evidence must fail closed.'
  Assert-True ($forgedResult.output -match 'TRUST_PAYLOAD_HASH_MISMATCH') "Tamper rejection must identify the payload hash boundary: $($forgedResult.output)"
  Write-Host 'PASS tests\adversarial\signed-loop-completion.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
