param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$WorktreePath,
  [string]$Branch,
  [string]$Verifier,
  [ValidateSet('NEEDS_REVIEW', 'PASS', 'WARN', 'FAIL')]
  [string]$Status = 'NEEDS_REVIEW',
  [string]$Summary = 'Verifier review pending.',
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
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
function Is-SafeRelativePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  if ([System.IO.Path]::IsPathRooted($Path)) { return $false }
  if ($Path -match '^[A-Za-z]:') { return $false }
  $normalized = $Path.Replace('/', '\')
  if ($normalized -match '(^|\\)\.\.($|\\)') { return $false }
  return $true
}
function Normalize-GitPath {
  param([string]$Path, [string]$BasePath)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}
function Same-Path {
  param([string]$A, [string]$B)
  if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
  $left = [System.IO.Path]::GetFullPath($A).TrimEnd([char[]]@('\', '/'))
  $right = [System.IO.Path]::GetFullPath($B).TrimEnd([char[]]@('\', '/'))
  return $left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase)
}
function Add-Item { param([string[]]$Array, [string]$Value) if ($Value) { return @($Array + $Value) } return $Array }

$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\verify-$stamp")
if (-not $Apply -and (Is-UnderPath -Path $EffectiveOutputDir -Root $TargetRoot)) { throw 'OutputDir would write inside the target during preview. Choose a path outside the target or use -Apply.' }
$EffectiveOutputDir = Initialize-SafeDirectory -Path $EffectiveOutputDir

$failures = @()
$warnings = @()
if ([string]::IsNullOrWhiteSpace($Verifier)) { $failures = Add-Item $failures 'Verifier is required.' }
if ([string]::IsNullOrWhiteSpace($WorktreePath)) { $failures = Add-Item $failures 'WorktreePath is required.' }
if ([string]::IsNullOrWhiteSpace($Branch)) { $failures = Add-Item $failures 'Branch is required for L2 verifier branch binding.' }

$EffectiveWorktreePath = if ([string]::IsNullOrWhiteSpace($WorktreePath)) { $null } else { Resolve-UserPath -Path $WorktreePath -Fallback $WorktreePath }
if ($EffectiveWorktreePath -and -not (Test-Path -LiteralPath $EffectiveWorktreePath)) { $failures = Add-Item $failures "Worktree path does not exist: $EffectiveWorktreePath" }

$targetGitRoot = $null
$worktreeGitRoot = $null
$targetCommonDir = $null
$worktreeCommonDir = $null
$currentBranch = $null
$branchMatches = $false
$sameCommonDir = $false
$worktreeStatus = @()

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
  try {
    $worktreeGitRootOutput = & git -C $EffectiveWorktreePath rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Worktree path is not a git worktree: $worktreeGitRootOutput" }
    else { $worktreeGitRoot = Normalize-GitPath ([string]($worktreeGitRootOutput | Select-Object -First 1)) $EffectiveWorktreePath }
  } catch {
    $failures = Add-Item $failures "Unable to inspect worktree git repository: $($_.Exception.Message)"
  }
  if ($worktreeGitRoot -and -not (Same-Path $worktreeGitRoot $EffectiveWorktreePath)) { $failures = Add-Item $failures "WorktreePath must point at the worktree root. Git root is: $worktreeGitRoot" }
  if ($worktreeGitRoot) {
    $worktreeCommonOutput = & git -C $EffectiveWorktreePath rev-parse --git-common-dir 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Unable to inspect worktree git common dir: $worktreeCommonOutput" }
    else { $worktreeCommonDir = Normalize-GitPath ([string]($worktreeCommonOutput | Select-Object -First 1)) $EffectiveWorktreePath }
    $branchOutput = & git -C $EffectiveWorktreePath branch --show-current 2>&1
    if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Unable to inspect worktree branch: $branchOutput" }
    else { $currentBranch = [string]($branchOutput | Select-Object -First 1) }
    $worktreeStatus = @(& git -C $EffectiveWorktreePath status --short 2>$null)
    if ($worktreeStatus.Count -gt 0) { $warnings = Add-Item $warnings 'Worktree has uncommitted changes; verifier decision must account for them.' }
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

$manifestPath = Join-Path $TargetRoot '.agent\loops\lizard-agent-layer.loop-install.json'
$verifierRel = '.agent/loops/loop-verifier-report.md'
if (Test-Path -LiteralPath $manifestPath) {
  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if (($manifest.PSObject.Properties.Name -contains 'verifier_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.verifier_file)) { $verifierRel = [string]$manifest.verifier_file }
  } catch {
    $failures = Add-Item $failures "Loop install manifest is invalid JSON: $($_.Exception.Message)"
  }
} else {
  $failures = Add-Item $failures 'Loop install manifest missing. Run loop-init.ps1 first.'
}

$normalizedVerifierRel = $verifierRel.Replace('/', '\')
$verifierFileSafe = $false
$reportPath = $null
if (-not (Is-SafeRelativePath $verifierRel)) {
  $failures = Add-Item $failures "Verifier file path is unsafe: $verifierRel"
} elseif ($normalizedVerifierRel -notmatch '^\.agent\\loops\\') {
  $failures = Add-Item $failures "Verifier file must stay under .agent/loops: $verifierRel"
} else {
  $reportPath = [System.IO.Path]::GetFullPath((Join-Path $TargetRoot $normalizedVerifierRel))
  try {
    $reportPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $reportPath
    $verifierFileSafe = $true
  } catch {
    $failures = Add-Item $failures "Verifier file path rejected: $($_.Exception.Message)"
  }
}

$mdLines = @()
$mdLines += '# loop verifier report'
$mdLines += ''
$mdLines += 'Pattern: minimal-fix-assist'
$mdLines += 'Auto-merge: forbidden'
$mdLines += ''
$mdLines += '## Verdict'
$mdLines += ''
$mdLines += ('Status: {0}' -f $Status)
$mdLines += ('Verifier: {0}' -f $Verifier)
$mdLines += ('Verified at: {0}' -f (Get-Date).ToUniversalTime().ToString('o'))
$mdLines += ('Worktree path: {0}' -f $EffectiveWorktreePath)
$mdLines += ('Branch: {0}' -f $Branch)
$mdLines += ('Observed branch: {0}' -f $currentBranch)
$mdLines += ('Same repository: {0}' -f $sameCommonDir)
$mdLines += ''
$mdLines += '## Summary'
$mdLines += ''
$mdLines += $Summary
$mdLines += ''
$mdLines += '## Decision Packet'
$mdLines += ''
$mdLines += 'Recommended human decision: merge|revise|discard|pause'
$mdLines += 'Human merge review required: true'
$mdLines += 'Merge allowed automatically: false'
$mdLines += ''
$mdLines += '## Worktree Status'
$mdLines += ''
if ($worktreeStatus.Count -eq 0) { $mdLines += '- Clean or unavailable.' } else { foreach ($entry in $worktreeStatus) { $mdLines += ('- `{0}`' -f $entry) } }
$mdLines += ''
$mdLines += '## Warnings'
$mdLines += ''
if ($warnings.Count -eq 0) { $mdLines += '- None' } else { foreach ($warning in $warnings) { $mdLines += ('- {0}' -f $warning) } }
$mdLines += ''
$mdLines += '## Failures'
$mdLines += ''
if ($failures.Count -eq 0) { $mdLines += '- None' } else { foreach ($failure in $failures) { $mdLines += ('- {0}' -f $failure) } }

$outputMdPath = Join-Path $EffectiveOutputDir 'loop-verifier-report.md'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $outputMdPath -Value $mdLines
if ($Apply -and $failures.Count -eq 0 -and $verifierFileSafe) {
  $parent = Split-Path -Parent $reportPath
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-SafeDirectory -AuthorizedRoot $TargetRoot -Path $parent | Out-Null }
  Set-SafeContent -AuthorizedRoot $TargetRoot -Path $reportPath -Value $mdLines
}

$report = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
  target = $TargetRoot
  target_git_root = $targetGitRoot
  worktree_path = $EffectiveWorktreePath
  worktree_git_root = $worktreeGitRoot
  branch = $Branch
  observed_branch = $currentBranch
  branch_matches = $branchMatches
  same_git_common_dir = $sameCommonDir
  verifier = $Verifier
  status = $Status
  summary = $Summary
  verifier_file = $verifierRel
  verifier_file_safe = $verifierFileSafe
  verifier_file_written = ($Apply -and $failures.Count -eq 0 -and $verifierFileSafe)
  auto_merge = $false
  human_merge_review_required = $true
  warnings = @($warnings)
  failures = @($failures)
}
$jsonPath = Join-Path $EffectiveOutputDir 'loop-verify-report.json'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 8)

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} else {
  Write-Host 'lizard-agent-layer L2 verifier'
  Write-Host "Mode: $($report.mode)"
  Write-Host "Status: $Status"
  Write-Host "Verifier: $Verifier"
  Write-Host "Worktree: $EffectiveWorktreePath"
  Write-Host "Branch: $Branch"
  Write-Host "Observed branch: $currentBranch"
  Write-Host "Auto-merge: forbidden"
  Write-Host "Output report: $outputMdPath"
  if ($Apply -and $failures.Count -eq 0 -and $verifierFileSafe) { Write-Host "Target verifier file: $reportPath" }
}
if ($failures.Count -gt 0) { exit 1 }
