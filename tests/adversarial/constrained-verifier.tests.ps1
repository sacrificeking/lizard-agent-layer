param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
if (-not $LayerRoot) { $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (-not $LayerRoot) { $LayerRoot = (Get-Location).Path }
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.ConstrainedRunner.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.LoopEvidence.psm1') -Force
Import-Module (Join-Path $LayerRoot 'tests\TestTrustHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Trust.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
$fixture = Join-Path $testRoot ("constrained-verifier-{0}" -f ([Guid]::NewGuid().ToString('N')))
$worktree = Join-Path $fixture 'worktree'
$otherRoot = Join-Path $fixture 'other-root'
$planRoot = Join-Path $fixture 'plans'
$outsideCanary = Join-Path $fixture 'outside-canary.txt'
$integrationTarget = Join-Path $fixture 'integration-target'
$integrationWorktree = Join-Path $fixture 'integration-worktree'

function Assert-GitSuccess {
  param([string[]]$Arguments)
  $output = & git @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git fixture failed: $output" }
}

function Write-TestPlan {
  param($Plan, [string]$Name)
  $path = Join-Path $planRoot $Name
  Set-Content -LiteralPath $path -Value ($Plan | ConvertTo-Json -Depth 12)
  [pscustomobject]@{ path = $path; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
}

try {
  New-Item -ItemType Directory -Path $worktree, $otherRoot, $planRoot -Force | Out-Null
  Assert-GitSuccess @('-C', $worktree, 'init', '--quiet')
  Assert-GitSuccess @('-C', $worktree, 'config', 'user.email', 'constrained@example.invalid')
  Assert-GitSuccess @('-C', $worktree, 'config', 'user.name', 'Constrained Test')
  Set-Content -LiteralPath (Join-Path $worktree 'README.md') -Value '# constrained fixture'
  Assert-GitSuccess @('-C', $worktree, 'add', 'README.md')
  Assert-GitSuccess @('-C', $worktree, 'commit', '--quiet', '-m', 'fixture')

  $plan = New-LizardVerificationPlan -WorktreeRoot $worktree -CommandIds @('git-head')
  $written = Write-TestPlan -Plan $plan -Name 'approved.json'
  $approved = Read-LizardVerificationPlan -Path $written.path -ExpectedSha256 $written.sha256 -WorktreeRoot $worktree
  $results = @(Invoke-LizardVerificationPlan -ApprovedPlan $approved -WorktreeRoot $worktree)
  Assert-Equal 1 $results.Count 'Approved constrained plan must execute its allowlisted command ID.'
  foreach ($result in $results) {
    Assert-Equal 0 ([int]$result.exit_code) "Allowlisted read-only Git command $($result.command_id) must pass."
    Assert-False ([bool]$result.timed_out) 'Allowlisted command must finish within its bound timeout.'
    Assert-True ([string]$result.output_sha256 -match '^[a-f0-9]{64}$') 'Only an output hash must be retained.'
    Assert-False ($result.PSObject.Properties.Name -contains 'output') 'Raw command output must not be retained.'
  }

  $denied = $false
  try { $null = New-LizardVerificationPlan -WorktreeRoot $worktree -CommandIds @('powershell-command') } catch { $denied = $_.Exception.Message -match 'VERIFICATION_COMMAND_ID_DENIED' }
  Assert-True $denied 'Unknown command IDs must fail closed before plan creation.'

  $digestRejected = $false
  try { $null = Read-LizardVerificationPlan -Path $written.path -ExpectedSha256 ('0' * 64) -WorktreeRoot $worktree } catch { $digestRejected = $_.Exception.Message -match 'VERIFICATION_PLAN_DIGEST_MISMATCH' }
  Assert-True $digestRejected 'Changed command-plan bytes or digest must be rejected.'

  $rootRejected = $false
  try { $null = Read-LizardVerificationPlan -Path $written.path -ExpectedSha256 $written.sha256 -WorktreeRoot $otherRoot } catch { $rootRejected = $_.Exception.Message -match 'VERIFICATION_PLAN_WORKTREE_MISMATCH' }
  Assert-True $rootRejected 'A command plan must not be replayed against another worktree.'

  $weakened = Get-Content -LiteralPath $written.path -Raw | ConvertFrom-LizardJson
  $weakened.restrictions.shell = $true
  $weakenedWritten = Write-TestPlan -Plan $weakened -Name 'weakened.json'
  $restrictionRejected = $false
  try { $null = Read-LizardVerificationPlan -Path $weakenedWritten.path -ExpectedSha256 $weakenedWritten.sha256 -WorktreeRoot $worktree } catch { $restrictionRejected = $_.Exception.Message -match 'VERIFICATION_PLAN_RESTRICTIONS_INVALID' }
  Assert-True $restrictionRejected 'A freshly hashed plan may not weaken shell/network/environment restrictions.'

  Set-Content -LiteralPath $outsideCanary -Value 'unchanged'
  $legacy = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts\loop-verify.ps1') -Arguments @('-TargetPath', $worktree, '-VerificationCommand', "powershell -Command Set-Content '$outsideCanary' compromised")
  Assert-False ($legacy.exit_code -eq 0) 'Legacy arbitrary command-string parameter must be rejected by binding.'
  Assert-Equal 'unchanged' ((Get-Content -LiteralPath $outsideCanary -Raw).Trim()) 'Rejected legacy command text must not modify an outside file.'

  $runnerSource = Get-Content -LiteralPath (Join-Path $LayerRoot 'scripts\Lizard.ConstrainedRunner.psm1') -Raw
  $verifierSource = Get-Content -LiteralPath (Join-Path $LayerRoot 'scripts\loop-verify.ps1') -Raw
  foreach ($forbidden in @('Invoke-Expression', 'ScriptBlock]::Create', '-NoProfile -Command')) {
    Assert-False (($runnerSource + $verifierSource) -match [regex]::Escape($forbidden)) "Verifier implementation must not contain shell-evaluation primitive $forbidden."
  }
  Assert-False ($verifierSource -match '\[string\[\]\]\$VerificationCommand') 'Verifier must not expose the legacy free-form command parameter.'

  New-Item -ItemType Directory -Path $integrationTarget -Force | Out-Null
  Assert-GitSuccess @('-C', $integrationTarget, 'init', '--quiet')
  Assert-GitSuccess @('-C', $integrationTarget, 'config', 'user.email', 'integration@example.invalid')
  Assert-GitSuccess @('-C', $integrationTarget, 'config', 'user.name', 'Integration Test')
  Set-Content -LiteralPath (Join-Path $integrationTarget 'README.md') -Value '# integration fixture'
  Assert-GitSuccess @('-C', $integrationTarget, 'add', 'README.md')
  Assert-GitSuccess @('-C', $integrationTarget, 'commit', '--quiet', '-m', 'fixture')
  $integrationBranch = 'lizard/constrained-integration'
  Assert-GitSuccess @('-C', $integrationTarget, 'worktree', 'add', '--quiet', '-b', $integrationBranch, $integrationWorktree, 'HEAD')
  $targetGitRoot = [string](& git -C $integrationTarget rev-parse --show-toplevel | Select-Object -First 1)
  $targetCommonRaw = [string](& git -C $integrationTarget rev-parse --git-common-dir | Select-Object -First 1)
  $worktreeCommonRaw = [string](& git -C $integrationWorktree rev-parse --git-common-dir | Select-Object -First 1)
  $targetCommon = Get-LizardNormalizedGitPath -Path $targetCommonRaw -BasePath $integrationTarget
  $worktreeCommon = Get-LizardNormalizedGitPath -Path $worktreeCommonRaw -BasePath $integrationWorktree
  $head = [string](& git -C $integrationWorktree rev-parse HEAD | Select-Object -First 1)
  $lifecyclePayload = [pscustomobject][ordered]@{
    operation_id = [Guid]::NewGuid().ToString('N'); status = 'CREATED'; created_at = (Get-Date).ToUniversalTime().ToString('o')
    target_root = (Resolve-Path $integrationTarget).Path; target_git_root = $targetGitRoot; git_common_dir = $targetCommon
    item_id = 'constrained-integration'; branch = $integrationBranch; observed_branch = $integrationBranch; base_ref = 'HEAD'; base_sha = $head; observed_head_sha = $head
    worktree_root = (Resolve-Path $integrationWorktree).Path; worktree_common_dir = $worktreeCommon; mutation_origin = 'external-registered'; human_approved = $true; auto_merge = $false
  }
  $integrationOutput = Join-Path $fixture 'integration-output'
  New-Item -ItemType Directory -Path $integrationOutput -Force | Out-Null
  $lifecyclePath = Join-Path $integrationOutput 'lifecycle.json'
  $trustNow = [DateTimeOffset]::UtcNow
  $lifecycleBinding = Get-LizardLifecycleTrustBinding -OperationId $lifecyclePayload.operation_id -TargetRoot $integrationTarget -WorktreeRoot $integrationWorktree -Branch $integrationBranch -BaseSha $head
  $lifecycleTrust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'lifecycle-trust') -BindingSha256 $lifecycleBinding -Subject $lifecyclePayload.operation_id -Now $trustNow -PrincipalId 'implementer-1' -Roles @('implementer') -Purpose 'worktree-registration' -PayloadKind 'worktree-lifecycle'
  $lifecycleEnvelope = New-LizardSignedEvidenceEnvelope -Payload $lifecyclePayload -PayloadKind worktree-lifecycle -Purpose worktree-registration -Subject $lifecyclePayload.operation_id -BindingSha256 $lifecycleBinding -ChallengePath $lifecycleTrust.challenge_path -ChallengeSha256 $lifecycleTrust.challenge_sha256 -PrivateKeyPath $lifecycleTrust.private_key_path -PrivateKeySha256 $lifecycleTrust.private_key_sha256 -Now $trustNow
  Set-Content -LiteralPath $lifecyclePath -Value ($lifecycleEnvelope | ConvertTo-Json -Depth 12)
  $loopRoot = Join-Path $integrationTarget '.agent\loops'
  New-Item -ItemType Directory -Path $loopRoot -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $loopRoot 'lizard-agent-layer.loop-install.json') -Value '{"pattern":"minimal-fix-assist","verifier_file":".agent/loops/loop-verifier-report.md"}'
  $criteriaDir = Join-Path $fixture 'criteria'
  New-Item -ItemType Directory -Path $criteriaDir -Force | Out-Null
  $criteriaPath = Join-Path $criteriaDir 'criteria.json'
  $criteriaPayload = [ordered]@{
    criteria = @(
      [ordered]@{ id = 'worktree-isolation'; verdict = 'PASS'; ground_truth_ref = 'worktree' }
      [ordered]@{ id = 'scoped-diff'; verdict = 'PASS'; ground_truth_ref = 'diff' }
      [ordered]@{ id = 'verifier-pass'; verdict = 'PASS'; ground_truth_ref = 'verifier' }
      [ordered]@{ id = 'human-approval-gate'; verdict = 'PASS'; ground_truth_ref = 'human' }
    )
  }
  Set-Content -LiteralPath $criteriaPath -Value ($criteriaPayload | ConvertTo-Json -Depth 5)
  $integrationPlan = New-LizardVerificationPlan -WorktreeRoot $integrationWorktree -CommandIds @('git-head')
  $integrationPlanWritten = Write-TestPlan -Plan $integrationPlan -Name 'integration-plan.json'
  $trustBinding = Get-LizardVerifierTrustBinding -OperationId $lifecyclePayload.operation_id -LifecycleHash $lifecycleEnvelope.payload_sha256 -VerificationPlanSha256 $integrationPlanWritten.sha256 -TargetRoot $integrationTarget
  $trust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'trust') -BindingSha256 $trustBinding -Subject $lifecyclePayload.operation_id -Now $trustNow -PrincipalId 'verifier-1'
  $verifyOutput = Join-Path $fixture 'verify-output'
  $verify = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts\loop-verify.ps1') -Arguments @('-TargetPath', $integrationTarget, '-LifecyclePath', $lifecyclePath, '-Verifier', 'verifier-1', '-Implementer', 'implementer-1', '-Status', 'PASS', '-Summary', 'Constrained integration pass.', '-CriteriaPath', $criteriaPath, '-VerificationPlanPath', $integrationPlanWritten.path, '-VerificationPlanSha256', $integrationPlanWritten.sha256, '-HumanApprovedVerificationPlan', '-LifecycleTrustStorePath', $lifecycleTrust.trust_store_path, '-LifecycleTrustStoreSha256', $lifecycleTrust.trust_store_sha256, '-LifecycleChallengePath', $lifecycleTrust.challenge_path, '-LifecycleChallengeSha256', $lifecycleTrust.challenge_sha256, '-TrustChallengePath', $trust.challenge_path, '-TrustChallengeSha256', $trust.challenge_sha256, '-VerifierPrivateKeyPath', $trust.private_key_path, '-VerifierPrivateKeySha256', $trust.private_key_sha256, '-OutputDir', $verifyOutput, '-Apply')
  Assert-Equal 0 $verify.exit_code "loop-verify must accept an exact approved constrained plan: $($verify.output)"
  $verifyReport = Get-Content -LiteralPath (Join-Path $verifyOutput 'loop-verify-report.json') -Raw | ConvertFrom-LizardJson
  Assert-Equal 'PASS' ([string]$verifyReport.status) 'Constrained verifier integration must produce PASS.'
  Assert-Equal ([string]$integrationPlan.plan_id) ([string]$verifyReport.verification_plan_id) 'Verifier report must bind the exact command plan ID.'
  Assert-Equal ([string]$integrationPlanWritten.sha256) ([string]$verifyReport.verification_plan_sha256) 'Verifier report must bind the independently supplied command plan digest.'
  Assert-Equal 'git-head' ([string]$verifyReport.command_results[0].command_id) 'Verifier report must retain only the allowlisted command ID.'
  Assert-True (Test-Path -LiteralPath (Join-Path $loopRoot 'loop-verifier-report.evidence.json')) 'Successful constrained verification must seal target evidence.'
  $signed = Get-Content -LiteralPath (Join-Path $loopRoot 'loop-verifier-report.evidence.json') -Raw | ConvertFrom-LizardJson
  Assert-Equal 2 ([int]$signed.schema_version) 'Verdict evidence must use the signed envelope schema.'
  Assert-Equal 'RS256' ([string]$signed.signature_algorithm) 'Verdict evidence must be asymmetrically signed.'
  Write-Host 'PASS tests\adversarial\constrained-verifier.tests.ps1'
} finally {
  if ((Test-Path -LiteralPath $integrationTarget) -and (Test-Path -LiteralPath $integrationWorktree)) { & git -C $integrationTarget worktree remove --force $integrationWorktree 2>$null | Out-Null }
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
