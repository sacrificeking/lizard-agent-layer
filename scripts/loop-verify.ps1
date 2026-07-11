param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$LifecyclePath,
  [string]$WorktreePath,
  [string]$Branch,
  [string]$Verifier,
  [string]$Implementer,
  [string[]]$VerificationCommand,
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
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$stamp = Get-Date -Format 'yyyyMMddHHmmss'

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
  return $left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase)
}
function Is-UnderPath {
  param([string]$Path, [string]$Root)
  if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
  if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $full.StartsWith(($rootFull + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
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
function Invoke-VerificationCommand {
  param([string]$Command, [string]$WorkingDirectory)
  $started = (Get-Date).ToUniversalTime().ToString('o')
  $hostPath = (Get-Process -Id $PID).Path
  Push-Location $WorkingDirectory
  try {
    $global:LASTEXITCODE = 0
    $output = (& $hostPath -NoProfile -Command $Command 2>&1 | Out-String)
    $exitCode = [int]$LASTEXITCODE
  } finally {
    Pop-Location
  }
  [pscustomobject][ordered]@{
    command = $Command
    started_at = $started
    completed_at = (Get-Date).ToUniversalTime().ToString('o')
    exit_code = $exitCode
    output_sha256 = Get-LizardEvidenceSha256 -Value $output
    output_bytes = (New-Object System.Text.UTF8Encoding($false)).GetByteCount($output)
  }
}

$failures = @()
$warnings = @()
if ([string]::IsNullOrWhiteSpace($Verifier)) { $failures = Add-ResultItem $failures 'Verifier is required.' }
if ([string]::IsNullOrWhiteSpace($LifecyclePath)) { $failures = Add-ResultItem $failures 'LifecyclePath is required.' }
if ($Status -ne 'NEEDS_REVIEW') {
  if ([string]::IsNullOrWhiteSpace($Implementer)) { $failures = Add-ResultItem $failures 'Implementer is required for a verdict.' }
  elseif (-not [string]::IsNullOrWhiteSpace($Verifier) -and $Implementer.Trim().Equals($Verifier.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) { $failures = Add-ResultItem $failures 'SELF_VERIFICATION_FORBIDDEN: Implementer and verifier must be different identities.' }
  if (@($VerificationCommand).Count -eq 0) { $failures = Add-ResultItem $failures 'At least one VerificationCommand is required for a verdict.' }
}

$effectiveLifecyclePath = if ([string]::IsNullOrWhiteSpace($LifecyclePath)) { $null } else { Resolve-UserPath -Path $LifecyclePath -Fallback $LifecyclePath }
$lifecycleEnvelope = $null
$lifecycle = $null
if ($effectiveLifecyclePath) {
  try {
    $lifecycleEnvelope = Read-LizardEvidenceEnvelope -Path $effectiveLifecyclePath -SchemaVersion 1
    $lifecycle = $lifecycleEnvelope.payload
    if ([string]$lifecycle.status -ne 'CREATED') { $failures = Add-ResultItem $failures "Lifecycle status must be CREATED, got '$($lifecycle.status)'." }
    if (-not (Same-Path ([string]$lifecycle.target_root) $TargetRoot)) { $failures = Add-ResultItem $failures 'Lifecycle target root does not match TargetPath.' }
    if (-not [string]::IsNullOrWhiteSpace($WorktreePath) -and -not (Same-Path -A $WorktreePath -B ([string]$lifecycle.worktree_root))) { $failures = Add-ResultItem $failures 'WorktreePath does not match lifecycle contract.' }
    else { $WorktreePath = [string]$lifecycle.worktree_root }
    if (-not [string]::IsNullOrWhiteSpace($Branch) -and $Branch -ne [string]$lifecycle.branch) { $failures = Add-ResultItem $failures 'Branch does not match lifecycle contract.' }
    else { $Branch = [string]$lifecycle.branch }
  } catch {
    $failures = Add-ResultItem $failures "Lifecycle contract rejected: $($_.Exception.Message)"
  }
}

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

if ($failures.Count -eq 0 -and $EffectiveWorktreePath) {
  foreach ($command in @($VerificationCommand)) {
    if ([string]::IsNullOrWhiteSpace([string]$command)) { continue }
    $result = Invoke-VerificationCommand -Command ([string]$command) -WorkingDirectory $EffectiveWorktreePath
    $commandResults.Add($result) | Out-Null
    if ([int]$result.exit_code -ne 0 -and $Status -in @('PASS', 'WARN')) { $failures = Add-ResultItem $failures "Verification command failed with exit code $($result.exit_code): $command" }
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
    $evidenceFiles.Add([pscustomobject][ordered]@{
      path = ([string]$relative).Replace('\', '/')
      sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
      bytes = (Get-Item -LiteralPath $full).Length
    }) | Out-Null
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
if (-not (Is-SafeRelativePath $verifierRel) -or -not $normalizedVerifierRel.StartsWith($expectedVerifierPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
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
  lifecycle_hash = if ($lifecycleEnvelope) { [string]$lifecycleEnvelope.payload_hash } else { $null }
  requested_status = $Status
  effective_status = $effectiveStatus
  verifier = $Verifier
  implementer = $Implementer
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
  commands = @($commandResults.ToArray())
  evidence_files = @($evidenceFiles.ToArray())
  auto_merge = $false
  human_merge_review_required = $true
}
$packetEnvelope = New-LizardEvidenceEnvelope -SchemaVersion 1 -Payload $packetPayload

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
  ('Evidence packet hash: {0}' -f $packetEnvelope.payload_hash), '',
  '## Summary', '', $Summary, '',
  '## Verification Commands', ''
)
if ($commandResults.Count -eq 0) { $mdLines += '- None' }
else { foreach ($result in $commandResults) { $mdLines += ('- `{0}` -> exit `{1}`, output `{2}`' -f $result.command, $result.exit_code, $result.output_sha256) } }
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
  evidence_packet_hash = $packetEnvelope.payload_hash
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
