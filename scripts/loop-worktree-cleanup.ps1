param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$WorktreePath,
  [string]$Branch,
  [switch]$RemoveBranch,
  [switch]$Force,
  [switch]$Apply,
  [switch]$HumanApproved,
  [switch]$Json,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$stamp = Get-Date -Format 'yyyyMMddHHmmss'

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
  if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $full.StartsWith(($rootFull + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
}
function Same-Path {
  param([string]$A, [string]$B)
  if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
  $left = [System.IO.Path]::GetFullPath($A).TrimEnd([char[]]@('\', '/'))
  $right = [System.IO.Path]::GetFullPath($B).TrimEnd([char[]]@('\', '/'))
  return $left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase)
}
function Normalize-GitPath {
  param([string]$Path, [string]$BasePath)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}
function Add-Item { param([string[]]$Array, [string]$Value) if ($Value) { return @($Array + $Value) } return $Array }

$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\cleanup-$stamp")
if (-not $Apply -and (Is-UnderPath -Path $EffectiveOutputDir -Root $TargetRoot)) { throw 'OutputDir would write inside the target during preview. Choose a path outside the target or use -Apply.' }
New-Item -ItemType Directory -Path $EffectiveOutputDir -Force | Out-Null

$failures = @()
$warnings = @()
if ([string]::IsNullOrWhiteSpace($WorktreePath)) { $failures = Add-Item $failures 'WorktreePath is required.' }
if ($Apply -and -not $HumanApproved) { $failures = Add-Item $failures 'Apply requires -HumanApproved for L2 worktree cleanup.' }

$EffectiveWorktreePath = if ([string]::IsNullOrWhiteSpace($WorktreePath)) { $null } else { Resolve-UserPath -Path $WorktreePath -Fallback $WorktreePath }
if ($EffectiveWorktreePath) {
  if (Same-Path $EffectiveWorktreePath $TargetRoot) { $failures = Add-Item $failures 'Refusing to clean up TargetPath as a worktree.' }
  if (Is-UnderPath -Path $EffectiveWorktreePath -Root $TargetRoot) { $failures = Add-Item $failures 'Refusing to clean up a worktree path inside TargetPath.' }
  if (-not (Test-Path -LiteralPath $EffectiveWorktreePath)) { $failures = Add-Item $failures "Worktree path does not exist: $EffectiveWorktreePath" }
}

$protectedBranches = @('main', 'master', 'develop', 'dev', 'trunk', 'release', 'prod', 'production')
if ($RemoveBranch -and -not [string]::IsNullOrWhiteSpace($Branch) -and $protectedBranches -contains $Branch.ToLowerInvariant()) { $failures = Add-Item $failures "Refusing to delete protected branch: $Branch" }

$targetGitRoot = $null
$worktreeGitRoot = $null
$targetCommonDir = $null
$worktreeCommonDir = $null
$currentBranch = $null
$sameCommonDir = $false
$branchMatches = $false
$worktreeDirty = $false

try {
  $targetGitRootOutput = & git -C $TargetRoot rev-parse --show-toplevel 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Target is not a git repository: $targetGitRootOutput" }
  else { $targetGitRoot = Normalize-GitPath ([string]($targetGitRootOutput | Select-Object -First 1)) $TargetRoot }
} catch {
  $failures = Add-Item $failures "Unable to inspect target git repository: $($_.Exception.Message)"
}
if ($targetGitRoot) {
  $commonOutput = & git -C $TargetRoot rev-parse --git-common-dir 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Unable to inspect target git common dir: $commonOutput" }
  else { $targetCommonDir = Normalize-GitPath ([string]($commonOutput | Select-Object -First 1)) $TargetRoot }
}

if ($EffectiveWorktreePath -and (Test-Path -LiteralPath $EffectiveWorktreePath)) {
  $worktreeGitRootOutput = & git -C $EffectiveWorktreePath rev-parse --show-toplevel 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Worktree path is not a git worktree: $worktreeGitRootOutput" }
  else { $worktreeGitRoot = Normalize-GitPath ([string]($worktreeGitRootOutput | Select-Object -First 1)) $EffectiveWorktreePath }
  if ($worktreeGitRoot -and -not (Same-Path $worktreeGitRoot $EffectiveWorktreePath)) { $failures = Add-Item $failures "WorktreePath must point at the worktree root. Git root is: $worktreeGitRoot" }
  if ($worktreeGitRoot) {
    $worktreeCommonOutput = & git -C $EffectiveWorktreePath rev-parse --git-common-dir 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Unable to inspect worktree git common dir: $worktreeCommonOutput" }
    else { $worktreeCommonDir = Normalize-GitPath ([string]($worktreeCommonOutput | Select-Object -First 1)) $EffectiveWorktreePath }
    $branchOutput = & git -C $EffectiveWorktreePath branch --show-current 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Unable to inspect worktree branch: $branchOutput" }
    else { $currentBranch = [string]($branchOutput | Select-Object -First 1) }
    $statusOutput = @(& git -C $EffectiveWorktreePath status --short 2>$null)
    $worktreeDirty = ($statusOutput.Count -gt 0)
    if ($worktreeDirty -and -not $Force) { $failures = Add-Item $failures 'Worktree has uncommitted changes. Use -Force only after intentional human review.' }
    elseif ($worktreeDirty) { $warnings = Add-Item $warnings 'Worktree has uncommitted changes and -Force was supplied.' }
  }
}
if ($targetCommonDir -and $worktreeCommonDir) {
  $sameCommonDir = Same-Path $targetCommonDir $worktreeCommonDir
  if (-not $sameCommonDir) { $failures = Add-Item $failures 'Worktree does not belong to the same git repository as TargetPath.' }
}
if (-not [string]::IsNullOrWhiteSpace($Branch) -and -not [string]::IsNullOrWhiteSpace($currentBranch)) {
  $branchMatches = $currentBranch.Equals($Branch, [System.StringComparison]::Ordinal)
  if (-not $branchMatches) { $failures = Add-Item $failures "Worktree branch mismatch. Expected '$Branch', got '$currentBranch'." }
}

$mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
$removed = $false
$branchDeleted = $false
if ($Apply -and $failures.Count -eq 0) {
  $args = @('worktree', 'remove')
  if ($Force) { $args += '--force' }
  $args += $EffectiveWorktreePath
  $removeOutput = & git -C $TargetRoot @args 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "git worktree remove failed: $removeOutput" }
  else { $removed = $true }
  if ($removed -and $RemoveBranch -and -not [string]::IsNullOrWhiteSpace($Branch)) {
    $branchArgs = @('branch')
    if ($Force) { $branchArgs += '-D' } else { $branchArgs += '-d' }
    $branchArgs += $Branch
    $branchOutput = & git -C $TargetRoot @branchArgs 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "git branch delete failed: $branchOutput" }
    else { $branchDeleted = $true }
  }
}

$status = if ($failures.Count -gt 0) { 'STOP' } elseif ($Apply) { 'REMOVED' } else { 'PREVIEW' }
$report = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = $mode
  status = $status
  target = $TargetRoot
  target_git_root = $targetGitRoot
  worktree_path = $EffectiveWorktreePath
  worktree_git_root = $worktreeGitRoot
  branch = $Branch
  observed_branch = $currentBranch
  branch_matches = $branchMatches
  same_git_common_dir = $sameCommonDir
  worktree_dirty = $worktreeDirty
  human_approved = $HumanApproved.IsPresent
  force = $Force.IsPresent
  remove_branch = $RemoveBranch.IsPresent
  removed = $removed
  branch_deleted = $branchDeleted
  auto_merge = $false
  warnings = @($warnings)
  failures = @($failures)
}
$jsonPath = Join-Path $EffectiveOutputDir 'loop-worktree-cleanup-report.json'
$mdPath = Join-Path $EffectiveOutputDir 'loop-worktree-cleanup-plan.md'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @()
$lines += '# lizard-agent-layer L2 worktree cleanup plan'
$lines += ''
$lines += ('- Mode: `{0}`' -f $mode)
$lines += ('- Status: `{0}`' -f $status)
$lines += ('- Target: `{0}`' -f $TargetRoot)
$lines += ('- Worktree path: `{0}`' -f $EffectiveWorktreePath)
$lines += ('- Branch: `{0}`' -f $Branch)
$lines += ('- Observed branch: `{0}`' -f $currentBranch)
$lines += ('- Remove branch: `{0}`' -f $RemoveBranch.IsPresent)
$lines += ('- Force: `{0}`' -f $Force.IsPresent)
$lines += ('- Human approved: `{0}`' -f $HumanApproved.IsPresent)
$lines += '- Auto-merge: `forbidden`'
$lines += ''
$lines += '## Warnings'
$lines += ''
if ($warnings.Count -eq 0) { $lines += '- None' } else { foreach ($warning in $warnings) { $lines += ('- {0}' -f $warning) } }
$lines += ''
$lines += '## Failures'
$lines += ''
if ($failures.Count -eq 0) { $lines += '- None' } else { foreach ($failure in $failures) { $lines += ('- {0}' -f $failure) } }
$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} else {
  Write-Host 'lizard-agent-layer L2 worktree cleanup'
  Write-Host "Mode: $mode"
  Write-Host "Status: $status"
  Write-Host "Target: $TargetRoot"
  Write-Host "Worktree: $EffectiveWorktreePath"
  Write-Host "Branch: $Branch"
  Write-Host "Auto-merge: forbidden"
  Write-Host "Report: $jsonPath"
  Write-Host "Plan: $mdPath"
  if (-not $Apply) { Write-Host 'Preview only. Re-run with -Apply -HumanApproved to remove the isolated worktree.' }
}
if ($failures.Count -gt 0) { exit 1 }
