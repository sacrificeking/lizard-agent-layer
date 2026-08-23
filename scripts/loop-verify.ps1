param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$LifecyclePath,
  [string]$WorktreePath,
  [string]$Branch,
  [string]$Verifier,
  [string]$Implementer,
  [string]$VerificationPlanPath,
  [string]$VerificationPlanSha256,
  [switch]$HumanApprovedVerificationPlan,
  [string]$TrustChallengePath,
  [string]$TrustChallengeSha256,
  [string]$VerifierPrivateKeyPath,
  [string]$VerifierPrivateKeySha256,
  [string]$LifecycleTrustStorePath,
  [string]$LifecycleTrustStoreSha256,
  [string]$LifecycleChallengePath,
  [string]$LifecycleChallengeSha256,
  [string[]]$EvidenceFile,
  [ValidateSet('NEEDS_REVIEW', 'PASS', 'WARN', 'FAIL')]
  [string]$Status = 'NEEDS_REVIEW',
  [string]$Summary = 'Verifier review pending.',
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputDir,
  [int]$TestFailAfterMutation = 0
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.LoopEvidence.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.ConstrainedRunner.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Trust.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Git.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
if (-not [string]::IsNullOrWhiteSpace($Branch)) { $Branch = Assert-LizardGitBranchName -Branch $Branch }

function Resolve-UserPath {
  param([string]$Path, [string]$Fallback)
  $candidate = if ([string]::IsNullOrWhiteSpace($Path)) { $Fallback } else { $Path }
  if ([System.IO.Path]::IsPathRooted($candidate)) { return [System.IO.Path]::GetFullPath($candidate) }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $candidate))
}
function Same-Path {
  param([string]$A, [string]$B)
  if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
  $left = [System.IO.Path]::GetFullPath($A).TrimEnd([char[]]@('\', '/'))
  $right = [System.IO.Path]::GetFullPath($B).TrimEnd([char[]]@('\', '/'))
  return $left.Equals($right, (Get-LizardPathComparison))
}
function Is-UnderPath {
  param([string]$Path, [string]$Root)
  if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
  if ($full.Equals($rootFull, (Get-LizardPathComparison))) { return $true }
  return $full.StartsWith(($rootFull + [System.IO.Path]::DirectorySeparatorChar), (Get-LizardPathComparison))
}
function Is-SafeRelativePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:') { return $false }
  $segments = $Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar).Split([System.IO.Path]::DirectorySeparatorChar)
  return @($segments | Where-Object { $_ -eq '..' }).Count -eq 0
}
function Add-ResultItem {
  param([string[]]$Array, [string]$Value)
  if ($Value) { return @($Array + $Value) }
  return $Array
}
$failures = @()
$warnings = @()
if ([string]::IsNullOrWhiteSpace($Verifier)) { $failures = Add-ResultItem $failures 'Verifier is required.' }
if ([string]::IsNullOrWhiteSpace($LifecyclePath)) { $failures = Add-ResultItem $failures 'LifecyclePath is required.' }
if ($Status -ne 'NEEDS_REVIEW') {
  if ([string]::IsNullOrWhiteSpace($Implementer)) { $failures = Add-ResultItem $failures 'Implementer is required for a verdict.' }
  elseif (-not [string]::IsNullOrWhiteSpace($Verifier) -and $Implementer.Trim().Equals($Verifier.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) { $failures = Add-ResultItem $failures 'SELF_VERIFICATION_FORBIDDEN: Implementer and verifier must be different identities.' }
  if ([string]::IsNullOrWhiteSpace($VerificationPlanPath) -or [string]::IsNullOrWhiteSpace($VerificationPlanSha256) -or -not $HumanApprovedVerificationPlan) { $failures = Add-ResultItem $failures 'VERIFICATION_PLAN_APPROVAL_REQUIRED: verdicts require an exact digest-bound constrained command plan and explicit approval.' }
  if ([string]::IsNullOrWhiteSpace($TrustChallengePath) -or [string]::IsNullOrWhiteSpace($TrustChallengeSha256) -or [string]::IsNullOrWhiteSpace($VerifierPrivateKeyPath) -or [string]::IsNullOrWhiteSpace($VerifierPrivateKeySha256)) { $failures = Add-ResultItem $failures 'VERIFIER_SIGNATURE_REQUIRED: verdicts require an external digest-bound challenge and verifier private key.' }
  if ([string]::IsNullOrWhiteSpace($LifecycleTrustStorePath) -or [string]::IsNullOrWhiteSpace($LifecycleTrustStoreSha256) -or [string]::IsNullOrWhiteSpace($LifecycleChallengePath) -or [string]::IsNullOrWhiteSpace($LifecycleChallengeSha256)) { $failures = Add-ResultItem $failures 'LIFECYCLE_TRUST_REQUIRED: verdicts require the external trust store and challenge used for the signed worktree lifecycle.' }
}

$effectiveLifecyclePath = if ([string]::IsNullOrWhiteSpace($LifecyclePath)) { $null } else { Resolve-UserPath -Path $LifecyclePath -Fallback $LifecyclePath }
$lifecycleEnvelope = $null
$lifecycle = $null
$authenticatedImplementer = $null
if ($effectiveLifecyclePath) {
  try {
    $lifecycleEnvelope = Read-LizardSignedEvidenceFile -Path $effectiveLifecyclePath
    $lifecycle = $lifecycleEnvelope.payload
    if ([string]$lifecycle.status -ne 'CREATED') { $failures = Add-ResultItem $failures "Lifecycle status must be CREATED, got '$($lifecycle.status)'." }
    if (-not (Same-Path ([string]$lifecycle.target_root) $TargetRoot)) { $failures = Add-ResultItem $failures 'Lifecycle target root does not match TargetPath.' }
    if (-not [string]::IsNullOrWhiteSpace($WorktreePath) -and -not (Same-Path -A $WorktreePath -B ([string]$lifecycle.worktree_root))) { $failures = Add-ResultItem $failures 'WorktreePath does not match lifecycle contract.' }
    else { $WorktreePath = [string]$lifecycle.worktree_root }
    if (-not [string]::IsNullOrWhiteSpace($Branch) -and $Branch -ne [string]$lifecycle.branch) { $failures = Add-ResultItem $failures 'Branch does not match lifecycle contract.' }
    else { $Branch = [string]$lifecycle.branch }
    foreach ($trustPath in @($LifecycleTrustStorePath, $LifecycleChallengePath)) { if ([string]::IsNullOrWhiteSpace($trustPath)) { throw 'LIFECYCLE_TRUST_REQUIRED: lifecycle trust store and challenge paths are required.' }; Assert-PathOutsideRoot -Path $trustPath -ExcludedRoot $TargetRoot -Label 'Lifecycle trust input' }
    $lifecycleTime = [DateTimeOffset]$lifecycleEnvelope.issued_at
    $lifecycleTrust = Read-LizardTrustStore -Path $LifecycleTrustStorePath -ExpectedSha256 $LifecycleTrustStoreSha256
    $lifecycleChallenge = Read-LizardTrustChallenge -Path $LifecycleChallengePath -ExpectedSha256 $LifecycleChallengeSha256 -Now $lifecycleTime
    $lifecycleBinding = Get-LizardLifecycleTrustBinding -OperationId ([string]$lifecycle.operation_id) -TargetRoot $TargetRoot -WorktreeRoot ([string]$lifecycle.worktree_root) -Branch ([string]$lifecycle.branch) -BaseSha ([string]$lifecycle.base_sha)
    $verifiedLifecycle = Test-LizardSignedEvidenceEnvelope -Envelope $lifecycleEnvelope -TrustStoreRead $lifecycleTrust -ChallengeRead $lifecycleChallenge -ExpectedPayloadKind 'worktree-lifecycle' -ExpectedPurpose 'worktree-registration' -ExpectedSubject ([string]$lifecycle.operation_id) -ExpectedBindingSha256 $lifecycleBinding -RequiredRole 'implementer' -Now $lifecycleTime
    $authenticatedImplementer = [string]$verifiedLifecycle.principal_id
    if (-not [string]::IsNullOrWhiteSpace($Implementer) -and $authenticatedImplementer -ne $Implementer) { throw 'IMPLEMENTER_IDENTITY_MISMATCH: Implementer must equal the authenticated lifecycle signer.' }
  } catch {
    $failures = Add-ResultItem $failures "Lifecycle contract rejected: $($_.Exception.Message)"
  }
}

if (-not [string]::IsNullOrWhiteSpace($Branch)) { $Branch = Assert-LizardGitBranchName -Branch $Branch }
$EffectiveWorktreePath = if ([string]::IsNullOrWhiteSpace($WorktreePath)) { $null } else { Resolve-UserPath -Path $WorktreePath -Fallback $WorktreePath }
if (-not $EffectiveWorktreePath) { $failures = Add-ResultItem $failures 'WorktreePath is required directly or through LifecyclePath.' }
elseif (-not (Test-Path -LiteralPath $EffectiveWorktreePath -PathType Container)) { $failures = Add-ResultItem $failures "Worktree path does not exist: $EffectiveWorktreePath" }

$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\verify-$stamp")
if (Is-UnderPath -Path $EffectiveOutputDir -Root $TargetRoot) { throw 'OutputDir must stay outside TargetPath.' }
if ($EffectiveWorktreePath -and (Is-UnderPath -Path $EffectiveOutputDir -Root $EffectiveWorktreePath)) { throw 'OutputDir must stay outside WorktreePath so evidence capture remains immutable.' }
$EffectiveOutputDir = Initialize-SafeDirectory -Path $EffectiveOutputDir

$targetGitRoot = $null
$worktreeGitRoot = $null
$targetCommonDir = $null
$worktreeCommonDir = $null
$currentBranch = $null
$branchMatches = $false
$sameCommonDir = $false
$commandResults = New-Object System.Collections.Generic.List[object]
$approvedVerificationPlan = $null
$evidenceFiles = New-Object System.Collections.Generic.List[object]
$gitState = $null

try {
  $targetGitRootOutput = & git -C $TargetRoot rev-parse --show-toplevel 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-ResultItem $failures "Target is not a git repository: $targetGitRootOutput" }
  else { $targetGitRoot = Get-LizardNormalizedGitPath -Path ([string]($targetGitRootOutput | Select-Object -First 1)) -BasePath $TargetRoot }
  if ($targetGitRoot) {
    $commonOutput = & git -C $TargetRoot rev-parse --git-common-dir 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-ResultItem $failures "Unable to inspect target git common dir: $commonOutput" }
    else { $targetCommonDir = Get-LizardNormalizedGitPath -Path ([string]($commonOutput | Select-Object -First 1)) -BasePath $TargetRoot }
  }
} catch { $failures = Add-ResultItem $failures "Unable to inspect target repository: $($_.Exception.Message)" }

if ($EffectiveWorktreePath -and (Test-Path -LiteralPath $EffectiveWorktreePath -PathType Container)) {
  try {
    $worktreeGitRootOutput = & git -C $EffectiveWorktreePath rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-ResultItem $failures "Worktree path is not a git worktree: $worktreeGitRootOutput" }
    else { $worktreeGitRoot = Get-LizardNormalizedGitPath -Path ([string]($worktreeGitRootOutput | Select-Object -First 1)) -BasePath $EffectiveWorktreePath }
    if ($worktreeGitRoot -and -not (Same-Path $worktreeGitRoot $EffectiveWorktreePath)) { $failures = Add-ResultItem $failures "WorktreePath must point at the worktree root: $worktreeGitRoot" }
    if ($worktreeGitRoot) {
      $commonOutput = & git -C $EffectiveWorktreePath rev-parse --git-common-dir 2>&1
      if ($LASTEXITCODE -ne 0) { $failures = Add-ResultItem $failures "Unable to inspect worktree git common dir: $commonOutput" }
      else { $worktreeCommonDir = Get-LizardNormalizedGitPath -Path ([string]($commonOutput | Select-Object -First 1)) -BasePath $EffectiveWorktreePath }
      $branchOutput = & git -C $EffectiveWorktreePath branch --show-current 2>&1
      if ($LASTEXITCODE -ne 0) { $failures = Add-ResultItem $failures "Unable to inspect worktree branch: $branchOutput" }
      else { $currentBranch = [string]($branchOutput | Select-Object -First 1) }
      if ([string]::IsNullOrWhiteSpace($currentBranch)) { $failures = Add-ResultItem $failures 'Detached HEAD is not allowed for L2 verification.' }
    }
  } catch { $failures = Add-ResultItem $failures "Unable to inspect worktree repository: $($_.Exception.Message)" }
}

if ($targetCommonDir -and $worktreeCommonDir) {
  $sameCommonDir = Same-Path $targetCommonDir $worktreeCommonDir
  if (-not $sameCommonDir) { $failures = Add-ResultItem $failures 'Worktree does not belong to the same git repository as TargetPath.' }
}
if ($Branch -and $currentBranch) {
  $branchMatches = $Branch.Equals($currentBranch, [System.StringComparison]::Ordinal)
  if (-not $branchMatches) { $failures = Add-ResultItem $failures "Worktree branch mismatch. Expected '$Branch', got '$currentBranch'." }
}
if ($lifecycle) {
  if (-not (Same-Path -A $targetCommonDir -B ([string]$lifecycle.git_common_dir))) { $failures = Add-ResultItem $failures 'Target git common directory does not match lifecycle contract.' }
  if (-not (Same-Path -A $worktreeCommonDir -B ([string]$lifecycle.worktree_common_dir))) { $failures = Add-ResultItem $failures 'Worktree git common directory does not match lifecycle contract.' }
}

if ($failures.Count -eq 0 -and $Status -ne 'NEEDS_REVIEW') {
  try {
    $fullVerificationPlanPath = [System.IO.Path]::GetFullPath($VerificationPlanPath)
    if ((Is-UnderPath -Path $fullVerificationPlanPath -Root $TargetRoot) -or (Is-UnderPath -Path $fullVerificationPlanPath -Root $EffectiveWorktreePath)) { throw 'VERIFICATION_PLAN_LOCATION_INVALID: approved plan must stay outside target and worktree roots.' }
    $approvedVerificationPlan = Read-LizardVerificationPlan -Path $fullVerificationPlanPath -ExpectedSha256 $VerificationPlanSha256 -WorktreeRoot $EffectiveWorktreePath
  } catch { $failures = Add-ResultItem $failures $_.Exception.Message }
}

if ($failures.Count -eq 0 -and $EffectiveWorktreePath) {
  if ($approvedVerificationPlan) {
    foreach ($result in @(Invoke-LizardVerificationPlan -ApprovedPlan $approvedVerificationPlan -WorktreeRoot $EffectiveWorktreePath)) {
      $commandResults.Add($result) | Out-Null
      if (@($result.expected_exit_codes) -notcontains [int]$result.exit_code -and $Status -in @('PASS', 'WARN')) { $failures = Add-ResultItem $failures "VERIFICATION_COMMAND_FAILED: $($result.command_id) returned exit code $($result.exit_code)." }
    }
  }
  foreach ($relative in @($EvidenceFile)) {
    if ([string]::IsNullOrWhiteSpace([string]$relative)) { continue }
    if (-not (Is-SafeRelativePath ([string]$relative))) {
      $failures = Add-ResultItem $failures "Evidence file path is unsafe: $relative"
      continue
    }
    $full = [System.IO.Path]::GetFullPath((Join-Path $EffectiveWorktreePath ([string]$relative)))
    if (-not (Is-UnderPath -Path $full -Root $EffectiveWorktreePath) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
      $failures = Add-ResultItem $failures "Evidence file is missing or outside worktree: $relative"
      continue
    }
    try {
      $metadata = Get-SafeFileMetadata -AuthorizedRoot $EffectiveWorktreePath -Path $full
      $evidenceFiles.Add([pscustomobject][ordered]@{
        path = ([string]$relative).Replace('\', '/')
        sha256 = Get-SafeFileHash -AuthorizedRoot $EffectiveWorktreePath -Path $full
        bytes = [int64]$metadata.length
      }) | Out-Null
    } catch {
      $failures = Add-ResultItem $failures ("Evidence file rejected: {0}: {1}" -f $relative, $_.Exception.Message)
    }
  }
  try {
    $gitState = Get-LizardGitStateEvidence -WorktreePath $EffectiveWorktreePath
    $confirmState = Get-LizardGitStateEvidence -WorktreePath $EffectiveWorktreePath
    if ($gitState.state_hash -ne $confirmState.state_hash) { $failures = Add-ResultItem $failures 'WORKTREE_CHANGED_DURING_VERIFICATION: Git state changed while evidence was being sealed.' }
  } catch { $failures = Add-ResultItem $failures "Unable to capture final git evidence: $($_.Exception.Message)" }
}

$manifestPath = Join-Path $TargetRoot '.agent\loops\lizard-agent-layer.loop-install.json'
$verifierRel = '.agent/loops/loop-verifier-report.md'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if (($manifest.PSObject.Properties.Name -contains 'verifier_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.verifier_file)) { $verifierRel = [string]$manifest.verifier_file }
  } catch { $failures = Add-ResultItem $failures "Loop install manifest is invalid JSON: $($_.Exception.Message)" }
} else { $failures = Add-ResultItem $failures 'Loop install manifest missing. Run loop-init.ps1 first.' }

$reportPath = $null
$evidenceTargetPath = $null
$verifierFileSafe = $false
$normalizedVerifierRel = $verifierRel.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
$expectedVerifierPrefix = '.agent' + [System.IO.Path]::DirectorySeparatorChar + 'loops' + [System.IO.Path]::DirectorySeparatorChar
if (-not (Is-SafeRelativePath $verifierRel) -or -not $normalizedVerifierRel.StartsWith($expectedVerifierPrefix, (Get-LizardPathComparison))) {
  $failures = Add-ResultItem $failures "Verifier file path is unsafe: $verifierRel"
} else {
  try {
    $reportPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $normalizedVerifierRel)
    $evidenceTargetPath = [System.IO.Path]::ChangeExtension($reportPath, '.evidence.json')
    $evidenceTargetPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $evidenceTargetPath
    $verifierFileSafe = $true
  } catch { $failures = Add-ResultItem $failures "Verifier file path rejected: $($_.Exception.Message)" }
}

$effectiveStatus = if ($failures.Count -gt 0) { 'INVALID' } else { $Status }
$verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
$packetPayload = [pscustomobject][ordered]@{
  operation_id = if ($lifecycle) { [string]$lifecycle.operation_id } else { $null }
  lifecycle_path = $effectiveLifecyclePath
  lifecycle_hash = if ($lifecycleEnvelope -and $lifecycleEnvelope.PSObject.Properties.Name -contains 'payload_sha256') { [string]$lifecycleEnvelope.payload_sha256 } elseif ($lifecycleEnvelope) { [string]$lifecycleEnvelope.payload_hash } else { $null }
  requested_status = $Status
  effective_status = $effectiveStatus
  verifier = $Verifier
  implementer = $Implementer
  authenticated_implementer = $authenticatedImplementer
  verified_at = $verifiedAt
  summary_sha256 = Get-LizardEvidenceSha256 -Value $Summary
  target_root = $TargetRoot
  target_git_root = $targetGitRoot
  git_common_dir = $targetCommonDir
  worktree_root = $EffectiveWorktreePath
  branch = $Branch
  observed_branch = $currentBranch
  head_sha = if ($gitState) { [string]$gitState.payload.head_sha } else { $null }
  git_state_hash = if ($gitState) { [string]$gitState.state_hash } else { $null }
  git_state = if ($gitState) { $gitState.payload } else { $null }
  verification_plan_id = if ($approvedVerificationPlan) { [string]$approvedVerificationPlan.plan.plan_id } else { $null }
  verification_plan_sha256 = if ($approvedVerificationPlan) { [string]$approvedVerificationPlan.sha256 } else { $null }
  verification_runner_id = if ($approvedVerificationPlan) { [string]$approvedVerificationPlan.plan.runner_id } else { $null }
  commands = @($commandResults.ToArray())
  evidence_files = @($evidenceFiles.ToArray())
  auto_merge = $false
  human_merge_review_required = $true
}
$packetEnvelope = $null
$trustBindingSha256 = $null
if ($Status -ne 'NEEDS_REVIEW' -and $failures.Count -eq 0) {
  try {
    $effectiveChallengePath = Resolve-UserPath -Path $TrustChallengePath -Fallback $TrustChallengePath
    $effectivePrivateKeyPath = Resolve-UserPath -Path $VerifierPrivateKeyPath -Fallback $VerifierPrivateKeyPath
    Assert-PathOutsideRoot -Path $effectiveChallengePath -ExcludedRoot $TargetRoot -Label 'TrustChallengePath'
    Assert-PathOutsideRoot -Path $effectivePrivateKeyPath -ExcludedRoot $TargetRoot -Label 'VerifierPrivateKeyPath'
    if ((Is-UnderPath -Path $effectiveChallengePath -Root $EffectiveWorktreePath) -or (Is-UnderPath -Path $effectivePrivateKeyPath -Root $EffectiveWorktreePath)) { throw 'Verifier trust inputs must stay outside WorktreePath.' }
    $trustBindingSha256 = Get-LizardVerifierTrustBinding -OperationId ([string]$packetPayload.operation_id) -LifecycleHash ([string]$packetPayload.lifecycle_hash) -VerificationPlanSha256 ([string]$packetPayload.verification_plan_sha256) -TargetRoot $TargetRoot
    $packetEnvelope = New-LizardSignedEvidenceEnvelope -Payload $packetPayload -PayloadKind 'verifier-evidence' -Purpose 'loop-completion' -Subject ([string]$packetPayload.operation_id) -BindingSha256 $trustBindingSha256 -ChallengePath $effectiveChallengePath -ChallengeSha256 $TrustChallengeSha256 -PrivateKeyPath $effectivePrivateKeyPath -PrivateKeySha256 $VerifierPrivateKeySha256
    if ([string]$packetEnvelope.principal_id -ne [string]$Verifier) { throw 'VERIFIER_IDENTITY_MISMATCH: Verifier must equal the authenticated private-key principal.' }
  } catch { $failures = Add-ResultItem $failures $_.Exception.Message }
}
if ($null -eq $packetEnvelope) {
  if ($failures.Count -gt 0) { $effectiveStatus = 'INVALID'; $packetPayload.effective_status = 'INVALID' }
  $packetEnvelope = New-LizardEvidenceEnvelope -SchemaVersion 1 -Payload $packetPayload
}
$packetEvidenceHash = if ($packetEnvelope.PSObject.Properties.Name -contains 'payload_sha256') { [string]$packetEnvelope.payload_sha256 } else { [string]$packetEnvelope.payload_hash }

$mdLines = @(
  '# loop verifier report', '',
  'Pattern: minimal-fix-assist',
  'Auto-merge: forbidden', '',
  '## Verdict', '',
  ('Status: {0}' -f $effectiveStatus),
  ('Requested status: {0}' -f $Status),
  ('Verifier: {0}' -f $Verifier),
  ('Implementer: {0}' -f $Implementer),
  ('Verified at: {0}' -f $verifiedAt),
  ('Operation ID: {0}' -f $packetPayload.operation_id),
  ('Lifecycle hash: {0}' -f $packetPayload.lifecycle_hash),
  ('HEAD SHA: {0}' -f $packetPayload.head_sha),
  ('Git state hash: {0}' -f $packetPayload.git_state_hash),
  ('Evidence packet hash: {0}' -f $packetEvidenceHash), '',
  '## Summary', '', $Summary, '',
  '## Verification Commands', ''
)
if ($commandResults.Count -eq 0) { $mdLines += '- None' }
else { foreach ($result in $commandResults) { $mdLines += ('- `{0}` -> exit `{1}`, output `{2}`' -f $result.command_id, $result.exit_code, $result.output_sha256) } }
$mdLines += @('', '## Evidence Files', '')
if ($evidenceFiles.Count -eq 0) { $mdLines += '- None' }
else { foreach ($file in $evidenceFiles) { $mdLines += ('- `{0}` -> `{1}`' -f $file.path, $file.sha256) } }
$mdLines += @('', '## Failures', '')
if ($failures.Count -eq 0) { $mdLines += '- None' } else { foreach ($failure in $failures) { $mdLines += ('- {0}' -f $failure) } }
$mdLines += @('', '## Decision Packet', '', 'Recommended human decision: merge|revise|discard|pause', 'Human merge review required: true', 'Merge allowed automatically: false')

$outputMdPath = Join-Path $EffectiveOutputDir 'loop-verifier-report.md'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $outputMdPath -Value $mdLines
$writeTransaction = $null
if ($Apply -and $failures.Count -eq 0 -and $verifierFileSafe) {
  $writeTransaction = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName 'loop-verify-write' -FailAfterMutation $TestFailAfterMutation
  try {
    $parent = Split-Path -Parent $reportPath
    if (-not (Test-Path -LiteralPath $parent)) { New-LizardTransactionalDirectory -Path $parent | Out-Null }
    Set-LizardTransactionalContent -Path $reportPath -Value $mdLines
    Set-LizardTransactionalContent -Path $evidenceTargetPath -Value ($packetEnvelope | ConvertTo-Json -Depth 20)
    Complete-LizardTransaction | Out-Null
  } catch {
    $verifyWriteError = $_
    if (Test-Path -LiteralPath (Join-Path $TargetRoot '.lizard-agent-layer.lock')) {
      try { Undo-LizardTransaction | Out-Null } catch { Write-Warning "Verifier write rollback requires recovery: $($_.Exception.Message)" }
    }
    throw $verifyWriteError
  }
}

$report = [pscustomobject][ordered]@{
  generated_at = $verifiedAt
  mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
  target = $TargetRoot
  operation_id = $packetPayload.operation_id
  lifecycle_path = $effectiveLifecyclePath
  lifecycle_hash = $packetPayload.lifecycle_hash
  worktree_path = $EffectiveWorktreePath
  branch = $Branch
  observed_branch = $currentBranch
  branch_matches = $branchMatches
  same_git_common_dir = $sameCommonDir
  verifier = $Verifier
  implementer = $Implementer
  requested_status = $Status
  status = $effectiveStatus
  head_sha = $packetPayload.head_sha
  git_state_hash = $packetPayload.git_state_hash
  evidence_packet_hash = $packetEvidenceHash
  trust_binding_sha256 = $trustBindingSha256
  verification_plan_id = $packetPayload.verification_plan_id
  verification_plan_sha256 = $packetPayload.verification_plan_sha256
  verification_runner_id = $packetPayload.verification_runner_id
  write_transaction_operation_id = if ($writeTransaction) { [string]$writeTransaction.operation_id } else { $null }
  command_results = @($commandResults.ToArray())
  evidence_files = @($evidenceFiles.ToArray())
  verifier_file = $verifierRel
  verifier_file_safe = $verifierFileSafe
  verifier_file_written = ($Apply -and $failures.Count -eq 0 -and $verifierFileSafe)
  evidence_file = $evidenceTargetPath
  auto_merge = $false
  human_merge_review_required = $true
  warnings = @($warnings)
  failures = @($failures)
}
$jsonPath = Join-Path $EffectiveOutputDir 'loop-verify-report.json'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 20)

if ($Json) { $report | ConvertTo-Json -Depth 20 }
else {
  Write-Host 'lizard-agent-layer L2 verifier'
  Write-Host "Mode: $($report.mode)"
  Write-Host "Status: $effectiveStatus"
  Write-Host "Verifier: $Verifier"
  Write-Host "Implementer: $Implementer"
  Write-Host "Operation: $($report.operation_id)"
  Write-Host "HEAD: $($report.head_sha)"
  Write-Host "Evidence packet: $($report.evidence_packet_hash)"
  Write-Host "Auto-merge: forbidden"
  Write-Host "Output report: $outputMdPath"
  if ($report.verifier_file_written) { Write-Host "Target verifier file: $reportPath" }
}
if ($failures.Count -gt 0) { exit 1 }
