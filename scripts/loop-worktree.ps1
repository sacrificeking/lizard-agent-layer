param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$ItemId = 'manual',
  [string]$Branch,
  [string]$WorktreePath,
  [string]$BaseRef = 'HEAD',
  [string]$OperationId,
  [switch]$RegisterExisting,
  [switch]$Apply,
  [switch]$HumanApproved,
  [string]$TrustChallengePath,
  [string]$TrustChallengeSha256,
  [string]$ImplementerPrivateKeyPath,
  [string]$ImplementerPrivateKeySha256,
  [switch]$Json,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.LoopEvidence.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Trust.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Git.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$operationId = if ([string]::IsNullOrWhiteSpace($OperationId)) { [Guid]::NewGuid().ToString('N') } else { $OperationId.ToLowerInvariant() }
if ($operationId -notmatch '^[a-f0-9]{32}$') { throw 'LIFECYCLE_OPERATION_ID_INVALID: OperationId must be 32 lowercase hex characters.' }

function Sanitize-Name {
  param([string]$Value)
  $safe = ($Value.ToLowerInvariant() -replace '[^a-z0-9._/-]+', '-') -replace '-+', '-'
  $safe = $safe.Trim('-', '/', '.')
  if ([string]::IsNullOrWhiteSpace($safe)) { return 'manual' }
  return $safe
}
function Resolve-UserPath {
  param([string]$Path, [string]$Fallback)
  $candidate = if ([string]::IsNullOrWhiteSpace($Path)) { $Fallback } else { $Path }
  if ([System.IO.Path]::IsPathRooted($candidate)) { return [System.IO.Path]::GetFullPath($candidate) }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $candidate))
}
function Is-UnderPath {
  param([string]$Path, [string]$Root)
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
  if ($full.Equals($rootFull, (Get-LizardPathComparison))) { return $true }
  return $full.StartsWith(($rootFull + [System.IO.Path]::DirectorySeparatorChar), (Get-LizardPathComparison))
}
function Add-Item { param([string[]]$Array, [string]$Value) if ($Value) { return @($Array + $Value) } return $Array }

$safeItem = Sanitize-Name $ItemId
if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "lizard/l2/$safeItem" }
$Branch = Assert-LizardGitBranchName -Branch $Branch
$BaseRef = Assert-LizardGitBaseReference -BaseRef $BaseRef
$safeBranchForPath = (Sanitize-Name $Branch).Replace('/', '-')
$targetName = Split-Path -Leaf $TargetRoot
$defaultWorktree = Join-Path $LayerRoot (".tmp\loops\worktrees\{0}-{1}-{2}" -f $targetName, $safeBranchForPath, $stamp)
$EffectiveWorktreePath = Resolve-UserPath -Path $WorktreePath -Fallback $defaultWorktree
$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\worktree-$stamp")
if (Is-UnderPath -Path $EffectiveOutputDir -Root $TargetRoot) { throw 'OutputDir must stay outside TargetPath so lifecycle evidence cannot mutate the target.' }
if (Is-UnderPath -Path $EffectiveWorktreePath -Root $TargetRoot) { throw 'WorktreePath must stay outside TargetPath.' }
$worktreeParent = Split-Path -Parent $EffectiveWorktreePath
$EffectiveWorktreePath = Resolve-SafeTargetDestination -AuthorizedRoot $worktreeParent -DestinationPath $EffectiveWorktreePath
$EffectiveOutputDir = Initialize-SafeDirectory -Path $EffectiveOutputDir

$failures = @()
$warnings = @()
$gitRoot = $null
$mainStatus = @()
$branchExists = $false
$pathExists = Test-Path -LiteralPath $EffectiveWorktreePath
$baseRevision = $null
$targetCommonDir = $null
$worktreeCommonDir = $null
$observedBranch = $null
$observedHead = $null

try {
  $gitRootOutput = & git -C $TargetRoot rev-parse --show-toplevel 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Target is not a git repository: $gitRootOutput" }
  else { $gitRoot = Get-LizardNormalizedGitPath -Path ([string]($gitRootOutput | Select-Object -First 1)) -BasePath $TargetRoot }
} catch {
  $failures = Add-Item $failures "Unable to inspect git repository: $($_.Exception.Message)"
}

if ($gitRoot) {
  $targetCommonOutput = & git -C $TargetRoot rev-parse --git-common-dir 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Unable to inspect target git common dir: $targetCommonOutput" }
  else { $targetCommonDir = Get-LizardNormalizedGitPath -Path ([string]($targetCommonOutput | Select-Object -First 1)) -BasePath $TargetRoot }
  $mainStatus = @(& git -C $TargetRoot status --short 2>$null)
  if ($mainStatus.Count -gt 0) { $warnings = Add-Item $warnings 'Main worktree has uncommitted changes; preserve them and keep L2 writes isolated.' }
  & git -C $TargetRoot show-ref --verify --quiet "refs/heads/$Branch"
  $branchExists = ($LASTEXITCODE -eq 0)
  if ($branchExists -and -not $RegisterExisting) { $failures = Add-Item $failures "Branch already exists: $Branch" }
  if (-not $branchExists -and $RegisterExisting) { $failures = Add-Item $failures "Registration requires the existing branch: $Branch" }
  try { $baseRevision = Resolve-LizardGitCommit -RepositoryRoot $TargetRoot -BaseRef $BaseRef }
  catch { $failures = Add-Item $failures $_.Exception.Message }
}

if ($pathExists -and -not $RegisterExisting) { $failures = Add-Item $failures "Worktree path already exists: $EffectiveWorktreePath" }
if (-not $pathExists -and $RegisterExisting) { $failures = Add-Item $failures "Registration requires an existing worktree path: $EffectiveWorktreePath" }
if ($Apply -and -not $HumanApproved) { $failures = Add-Item $failures 'Apply requires -HumanApproved for L2 worktree creation.' }
if ($RegisterExisting -and -not $Apply) { $failures = Add-Item $failures 'RegisterExisting requires -Apply -HumanApproved to seal lifecycle evidence.' }
if ($Apply -and $RegisterExisting -and ([string]::IsNullOrWhiteSpace($TrustChallengePath) -or [string]::IsNullOrWhiteSpace($TrustChallengeSha256) -or [string]::IsNullOrWhiteSpace($ImplementerPrivateKeyPath) -or [string]::IsNullOrWhiteSpace($ImplementerPrivateKeySha256))) { $failures = Add-Item $failures 'LIFECYCLE_SIGNATURE_REQUIRED: registration requires an external digest-bound challenge and implementer private key.' }
if ($Apply -and -not $RegisterExisting) {
  $failures = Add-Item $failures 'SAFEFS_EXTERNAL_MUTATOR_UNBOUND: Built-in git worktree creation is disabled because Git cannot consume the SafeFs parent-handle boundary. Create the reviewed worktree externally, then re-run with -RegisterExisting -Apply -HumanApproved.'
}

$mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
$created = $false
$registered = $false
if ($Apply -and $RegisterExisting -and $failures.Count -eq 0) {
  try { $EffectiveWorktreePath = Resolve-SafeRoot -Path $EffectiveWorktreePath -RequireExisting }
  catch { $failures = Add-Item $failures "Existing worktree root rejected: $($_.Exception.Message)" }
  if ($failures.Count -eq 0) {
    $commonOutput = & git -C $EffectiveWorktreePath rev-parse --git-common-dir 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Registered worktree common dir could not be read: $commonOutput" }
    else { $worktreeCommonDir = Get-LizardNormalizedGitPath -Path ([string]($commonOutput | Select-Object -First 1)) -BasePath $EffectiveWorktreePath }
    $observedBranchOutput = & git -C $EffectiveWorktreePath branch --show-current 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Registered worktree branch could not be read: $observedBranchOutput" }
    else { $observedBranch = [string]($observedBranchOutput | Select-Object -First 1) }
    $observedHeadOutput = & git -C $EffectiveWorktreePath rev-parse HEAD 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Registered worktree HEAD could not be read: $observedHeadOutput" }
    else { $observedHead = [string]($observedHeadOutput | Select-Object -First 1) }
    $registeredStatus = @(& git -C $EffectiveWorktreePath status --short 2>$null)
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures 'Registered worktree status could not be read.' }
    elseif ($registeredStatus.Count -gt 0) { $failures = Add-Item $failures 'Registration requires a clean worktree before assisted changes begin.' }
    if ($targetCommonDir -and $worktreeCommonDir -and -not $targetCommonDir.Equals($worktreeCommonDir, (Get-LizardPathComparison))) {
      $failures = Add-Item $failures 'Registered worktree does not share the target repository common directory.'
    }
    if ($observedBranch -ne $Branch) { $failures = Add-Item $failures "Registered worktree branch mismatch. Expected '$Branch', got '$observedBranch'." }
    if ($observedHead -ne $baseRevision) { $failures = Add-Item $failures "Registered worktree HEAD mismatch. Expected '$baseRevision', got '$observedHead'." }
    if ($failures.Count -eq 0) { $registered = $true }
  }
}

$status = if ($failures.Count -gt 0) { 'STOP' } elseif ($created -or $registered) { 'CREATED' } else { 'PREVIEW' }
$lifecyclePayload = [pscustomobject][ordered]@{
  operation_id = $operationId
  status = $status
  created_at = (Get-Date).ToUniversalTime().ToString('o')
  target_root = $TargetRoot
  target_git_root = $gitRoot
  git_common_dir = $targetCommonDir
  item_id = $ItemId
  branch = $Branch
  observed_branch = $observedBranch
  base_ref = $BaseRef
  base_sha = $baseRevision
  observed_head_sha = $observedHead
  worktree_root = $EffectiveWorktreePath
  worktree_common_dir = $worktreeCommonDir
  mutation_origin = if ($registered) { 'external-registered' } elseif ($created) { 'layer' } else { 'none' }
  human_approved = $HumanApproved.IsPresent
  auto_merge = $false
}
$lifecycleEnvelope = $null
$lifecycleTrustBinding = $null
if ($status -eq 'CREATED') {
  try {
    $effectiveChallengePath = Resolve-UserPath -Path $TrustChallengePath -Fallback $TrustChallengePath
    $effectivePrivateKeyPath = Resolve-UserPath -Path $ImplementerPrivateKeyPath -Fallback $ImplementerPrivateKeyPath
    if ((Is-UnderPath $effectiveChallengePath $TargetRoot) -or (Is-UnderPath $effectivePrivateKeyPath $TargetRoot) -or (Is-UnderPath $effectiveChallengePath $EffectiveWorktreePath) -or (Is-UnderPath $effectivePrivateKeyPath $EffectiveWorktreePath)) { throw 'Lifecycle trust inputs must stay outside target and worktree roots.' }
    $lifecycleTrustBinding = Get-LizardLifecycleTrustBinding -OperationId $operationId -TargetRoot $TargetRoot -WorktreeRoot $EffectiveWorktreePath -Branch $Branch -BaseSha $baseRevision
    $lifecycleEnvelope = New-LizardSignedEvidenceEnvelope -Payload $lifecyclePayload -PayloadKind 'worktree-lifecycle' -Purpose 'worktree-registration' -Subject $operationId -BindingSha256 $lifecycleTrustBinding -ChallengePath $effectiveChallengePath -ChallengeSha256 $TrustChallengeSha256 -PrivateKeyPath $effectivePrivateKeyPath -PrivateKeySha256 $ImplementerPrivateKeySha256
  } catch {
    $failures = Add-Item $failures $_.Exception.Message
    $status = 'STOP'; $lifecyclePayload.status = 'STOP'
  }
}
if ($null -eq $lifecycleEnvelope) { $lifecycleEnvelope = New-LizardEvidenceEnvelope -SchemaVersion 1 -Payload $lifecyclePayload }
$lifecycleEvidenceHash = if ($lifecycleEnvelope.PSObject.Properties.Name -contains 'payload_sha256') { [string]$lifecycleEnvelope.payload_sha256 } else { [string]$lifecycleEnvelope.payload_hash }
$lifecyclePath = Join-Path $EffectiveOutputDir 'loop-worktree-lifecycle.json'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $lifecyclePath -Value ($lifecycleEnvelope | ConvertTo-Json -Depth 12)
$report = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = $mode
  status = $status
  operation_id = $operationId
  target = $TargetRoot
  git_root = $gitRoot
  item_id = $ItemId
  branch = $Branch
  base_ref = $BaseRef
  base_revision = $baseRevision
  target_git_common_dir = $targetCommonDir
  worktree_git_common_dir = $worktreeCommonDir
  observed_branch = $observedBranch
  observed_head_sha = $observedHead
  lifecycle_path = $lifecyclePath
  lifecycle_hash = $lifecycleEvidenceHash
  lifecycle_trust_binding_sha256 = $lifecycleTrustBinding
  authenticated_implementer = if ($lifecycleEnvelope.PSObject.Properties.Name -contains 'principal_id') { [string]$lifecycleEnvelope.principal_id } else { $null }
  approval_ref = if ($lifecycleEnvelope.PSObject.Properties.Name -contains 'approval_ref') { [string]$lifecycleEnvelope.approval_ref } else { $null }
  worktree_path = $EffectiveWorktreePath
  path_exists = $pathExists
  branch_exists = $branchExists
  main_worktree_dirty = ($mainStatus.Count -gt 0)
  human_approved = $HumanApproved.IsPresent
  created = $created
  registered = $registered
  auto_merge = $false
  human_merge_review_required = $true
  warnings = @($warnings)
  failures = @($failures)
}
$jsonPath = Join-Path $EffectiveOutputDir 'loop-worktree-report.json'
$mdPath = Join-Path $EffectiveOutputDir 'loop-worktree-plan.md'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 8)

$lines = @()
$lines += '# lizard-agent-layer L2 worktree plan'
$lines += ''
$lines += ('- Mode: `{0}`' -f $mode)
$lines += ('- Status: `{0}`' -f $status)
$lines += ('- Target: `{0}`' -f $TargetRoot)
$lines += ('- Item: `{0}`' -f $ItemId)
$lines += ('- Branch: `{0}`' -f $Branch)
$lines += ('- Worktree path: `{0}`' -f $EffectiveWorktreePath)
$lines += ('- Base ref: `{0}`' -f $BaseRef)
$lines += ('- Base revision: `{0}`' -f $baseRevision)
$lines += ('- Operation ID: `{0}`' -f $operationId)
$lines += ('- Lifecycle contract: `{0}`' -f $lifecyclePath)
$lines += ('- Lifecycle hash: `{0}`' -f $lifecycleEvidenceHash)
$lines += ('- Human approved: `{0}`' -f $HumanApproved.IsPresent)
$lines += '- Auto-merge: `forbidden`'
$lines += '- Human merge review required: `true`'
$lines += ''
$lines += '## Main Worktree Status'
$lines += ''
if ($mainStatus.Count -eq 0) { $lines += '- Clean or unavailable.' } else { foreach ($entry in $mainStatus) { $lines += ('- `{0}`' -f $entry) } }
$lines += ''
$lines += '## Warnings'
$lines += ''
if ($warnings.Count -eq 0) { $lines += '- None' } else { foreach ($warning in $warnings) { $lines += ('- {0}' -f $warning) } }
$lines += ''
$lines += '## Failures'
$lines += ''
if ($failures.Count -eq 0) { $lines += '- None' } else { foreach ($failure in $failures) { $lines += ('- {0}' -f $failure) } }
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $mdPath -Value $lines

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} else {
  Write-Host 'lizard-agent-layer L2 worktree'
  Write-Host "Mode: $mode"
  Write-Host "Status: $status"
  Write-Host "Target: $TargetRoot"
  Write-Host "Branch: $Branch"
  Write-Host "Worktree: $EffectiveWorktreePath"
  Write-Host "Operation: $operationId"
  Write-Host "Lifecycle: $lifecyclePath"
  Write-Host "Auto-merge: forbidden"
  Write-Host "Report: $jsonPath"
  Write-Host "Plan: $mdPath"
  if (-not $Apply) { Write-Host 'Preview only. Re-run with -Apply -HumanApproved to create the isolated worktree.' }
  if ($failures.Count -gt 0) {
    Write-Host 'Failures:'
    foreach ($failure in $failures) { Write-Host "  - $failure" }
  }
}

if ($failures.Count -gt 0) { exit 1 }
