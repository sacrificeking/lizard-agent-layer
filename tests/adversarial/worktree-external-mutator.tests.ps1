param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.LoopEvidence.psm1') -Force
Import-Module (Join-Path $LayerRoot 'tests/TestTrustHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Trust.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp/tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("worktree-external-mutator-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$worktree = Join-Path $fixture 'worktree'
$output = Join-Path $fixture 'output'
$cleanupOutput = Join-Path $fixture 'cleanup-output'
$branch = 'lizard/l2/external-mutator-test'
$worktreeScript = Join-Path $LayerRoot 'scripts/loop-worktree.ps1'
$cleanupScript = Join-Path $LayerRoot 'scripts/loop-worktree-cleanup.ps1'
$operationId = ('2' * 32)

function Assert-GitSuccess {
  param([string[]]$Arguments, [string]$Message)
  $result = & git @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "${Message}: $result" }
}

try {
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Assert-GitSuccess @('-C', $target, 'init', '--quiet') 'git init failed'
  Assert-GitSuccess @('-C', $target, 'config', 'user.email', 'tests@lizard-agent-layer.invalid') 'git email config failed'
  Assert-GitSuccess @('-C', $target, 'config', 'user.name', 'lizard tests') 'git name config failed'
  Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# fixture' -Encoding UTF8
  Assert-GitSuccess @('-C', $target, 'add', 'README.md') 'git add failed'
  Assert-GitSuccess @('-C', $target, 'commit', '--quiet', '-m', 'fixture') 'git commit failed'

  $blocked = Invoke-TestPowerShell -ScriptPath $worktreeScript -Arguments @('-TargetPath', $target, '-Branch', $branch, '-WorktreePath', $worktree, '-OutputDir', $output, '-Apply', '-HumanApproved')
  Assert-False ($blocked.exit_code -eq 0) 'Built-in Git worktree mutation must fail closed.'
  $blockedReport = Get-Content -LiteralPath (Join-Path $output 'loop-worktree-report.json') -Raw | ConvertFrom-LizardJson
  Assert-True ((@($blockedReport.failures) -join ' ') -match 'SAFEFS_EXTERNAL_MUTATOR_UNBOUND') 'Blocked creation must expose the stable external-mutator code.'
  Assert-False (Test-Path -LiteralPath $worktree) 'Blocked creation must not create the worktree path.'

  Assert-GitSuccess @('-C', $target, 'worktree', 'add', '--quiet', '-b', $branch, $worktree, 'HEAD') 'external fixture creation failed'
  $baseSha = [string](& git -C $worktree rev-parse HEAD | Select-Object -First 1)
  $lifecycleBinding = Get-LizardLifecycleTrustBinding -OperationId $operationId -TargetRoot $target -WorktreeRoot $worktree -Branch $branch -BaseSha $baseSha
  $trust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'trust') -BindingSha256 $lifecycleBinding -Subject $operationId -Now ([DateTimeOffset]::UtcNow) -PrincipalId 'implementer-01' -Roles @('implementer') -Purpose 'worktree-registration' -PayloadKind 'worktree-lifecycle'
  $registered = Invoke-TestPowerShell -ScriptPath $worktreeScript -Arguments @('-TargetPath', $target, '-ItemId', 'external-mutator-test', '-OperationId', $operationId, '-Branch', $branch, '-WorktreePath', $worktree, '-OutputDir', $output, '-RegisterExisting', '-Apply', '-HumanApproved', '-TrustChallengePath', $trust.challenge_path, '-TrustChallengeSha256', $trust.challenge_sha256, '-ImplementerPrivateKeyPath', $trust.private_key_path, '-ImplementerPrivateKeySha256', $trust.private_key_sha256)
  Assert-Equal 0 $registered.exit_code "Existing worktree registration failed: $($registered.output)"
  $lifecyclePath = Join-Path $output 'loop-worktree-lifecycle.json'
  $lifecycle = Read-LizardSignedEvidenceFile -Path $lifecyclePath
  Assert-Equal 2 ([int]$lifecycle.schema_version) 'Registered lifecycle must use a signed evidence envelope.'
  Assert-Equal 'implementer-01' ([string]$lifecycle.principal_id) 'Lifecycle identity must come from the signing key.'
  Assert-Equal 'CREATED' ([string]$lifecycle.payload.status) 'Registered lifecycle must be verifier-ready.'
  Assert-Equal 'external-registered' ([string]$lifecycle.payload.mutation_origin) 'Registered lifecycle must disclose its external mutation origin.'
  $report = Get-Content -LiteralPath (Join-Path $output 'loop-worktree-report.json') -Raw | ConvertFrom-LizardJson
  Assert-True ([bool]$report.registered) 'Registration report must identify the read-only registration path.'
  Assert-False ([bool]$report.created) 'Registration report must not claim that the layer created the worktree.'

  $cleanup = Invoke-TestPowerShell -ScriptPath $cleanupScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $lifecyclePath, '-LifecycleTrustStorePath', $trust.trust_store_path, '-LifecycleTrustStoreSha256', $trust.trust_store_sha256, '-LifecycleChallengePath', $trust.challenge_path, '-LifecycleChallengeSha256', $trust.challenge_sha256, '-WorktreePath', $worktree, '-Branch', $branch, '-RemoveBranch', '-Force', '-OutputDir', $cleanupOutput, '-Apply', '-HumanApproved')
  Assert-False ($cleanup.exit_code -eq 0) 'Built-in Git worktree removal must fail closed.'
  $cleanupReport = Get-Content -LiteralPath (Join-Path $cleanupOutput 'loop-worktree-cleanup-report.json') -Raw | ConvertFrom-LizardJson
  Assert-True ((@($cleanupReport.failures) -join ' ') -match 'SAFEFS_EXTERNAL_MUTATOR_UNBOUND') 'Blocked cleanup must expose the stable external-mutator code.'
  Assert-True (Test-Path -LiteralPath $worktree) 'Blocked cleanup must preserve the external worktree.'

  Assert-GitSuccess @('-C', $target, 'worktree', 'remove', '--force', $worktree) 'external fixture cleanup failed'
  Assert-GitSuccess @('-C', $target, 'branch', '-D', $branch) 'external fixture branch cleanup failed'
  Write-Host 'PASS tests\adversarial\worktree-external-mutator.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $worktree) { & git -C $target worktree remove --force $worktree 2>$null | Out-Null }
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
