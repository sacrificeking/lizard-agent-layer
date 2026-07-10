param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$ItemId = 'manual',
  [string]$Branch,
  [string]$WorktreePath,
  [string]$BaseRef = 'HEAD',
  [switch]$Apply,
  [switch]$HumanApproved,
  [switch]$Json,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$stamp = Get-Date -Format 'yyyyMMddHHmmss'

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
  if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $full.StartsWith(($rootFull + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
}
function Add-Item { param([string[]]$Array, [string]$Value) if ($Value) { return @($Array + $Value) } return $Array }

$safeItem = Sanitize-Name $ItemId
if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "lizard/l2/$safeItem" }
$safeBranchForPath = (Sanitize-Name $Branch).Replace('/', '-')
$targetName = Split-Path -Leaf $TargetRoot
$defaultWorktree = Join-Path $LayerRoot (".tmp\loops\worktrees\{0}-{1}-{2}" -f $targetName, $safeBranchForPath, $stamp)
$EffectiveWorktreePath = Resolve-UserPath -Path $WorktreePath -Fallback $defaultWorktree
$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\worktree-$stamp")
if (-not $Apply -and (Is-UnderPath -Path $EffectiveOutputDir -Root $TargetRoot)) { throw 'OutputDir would write inside the target during preview. Choose a path outside the target or use -Apply.' }
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

try {
  $gitRootOutput = & git -C $TargetRoot rev-parse --show-toplevel 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Target is not a git repository: $gitRootOutput" }
  else { $gitRoot = [string]($gitRootOutput | Select-Object -First 1) }
} catch {
  $failures = Add-Item $failures "Unable to inspect git repository: $($_.Exception.Message)"
}

if ($gitRoot) {
  $mainStatus = @(& git -C $TargetRoot status --short 2>$null)
  if ($mainStatus.Count -gt 0) { $warnings = Add-Item $warnings 'Main worktree has uncommitted changes; preserve them and keep L2 writes isolated.' }
  & git -C $TargetRoot show-ref --verify --quiet "refs/heads/$Branch"
  $branchExists = ($LASTEXITCODE -eq 0)
  if ($branchExists) { $failures = Add-Item $failures "Branch already exists: $Branch" }
  $baseRevisionOutput = & git -C $TargetRoot rev-parse $BaseRef 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "Base ref is invalid: $BaseRef ($baseRevisionOutput)" }
  else { $baseRevision = [string]($baseRevisionOutput | Select-Object -First 1) }
}

if ($pathExists) { $failures = Add-Item $failures "Worktree path already exists: $EffectiveWorktreePath" }
if ($Apply -and -not $HumanApproved) { $failures = Add-Item $failures 'Apply requires -HumanApproved for L2 worktree creation.' }

$mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
$created = $false
if ($Apply -and $failures.Count -eq 0) {
  $parent = Split-Path -Parent $EffectiveWorktreePath
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { Initialize-SafeDirectory -Path $parent | Out-Null }
  $EffectiveWorktreePath = Resolve-SafeTargetDestination -AuthorizedRoot $parent -DestinationPath $EffectiveWorktreePath
  $worktreeOutput = & git -C $TargetRoot worktree add --quiet -b $Branch $EffectiveWorktreePath $BaseRef 2>&1
  if ($LASTEXITCODE -ne 0) { $failures = Add-Item $failures "git worktree add failed: $worktreeOutput" }
  else { $created = $true }
}

$status = if ($failures.Count -gt 0) { 'STOP' } elseif ($Apply) { 'CREATED' } else { 'PREVIEW' }
$report = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = $mode
  status = $status
  target = $TargetRoot
  git_root = $gitRoot
  item_id = $ItemId
  branch = $Branch
  base_ref = $BaseRef
  base_revision = $baseRevision
  worktree_path = $EffectiveWorktreePath
  path_exists = $pathExists
  branch_exists = $branchExists
  main_worktree_dirty = ($mainStatus.Count -gt 0)
  human_approved = $HumanApproved.IsPresent
  created = $created
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
  Write-Host "Auto-merge: forbidden"
  Write-Host "Report: $jsonPath"
  Write-Host "Plan: $mdPath"
  if (-not $Apply) { Write-Host 'Preview only. Re-run with -Apply -HumanApproved to create the isolated worktree.' }
}

if ($failures.Count -gt 0) { exit 1 }
