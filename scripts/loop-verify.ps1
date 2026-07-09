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
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
function Resolve-UserPath {
  param([string]$Path, [string]$Fallback)
  $candidate = if ([string]::IsNullOrWhiteSpace($Path)) { $Fallback } else { $Path }
  if ([System.IO.Path]::IsPathRooted($candidate)) { return [System.IO.Path]::GetFullPath($candidate) }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $candidate))
}
$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\verify-$stamp")
New-Item -ItemType Directory -Path $EffectiveOutputDir -Force | Out-Null

$failures = @()
if ([string]::IsNullOrWhiteSpace($Verifier)) { $failures += 'Verifier is required.' }
if ([string]::IsNullOrWhiteSpace($WorktreePath)) { $failures += 'WorktreePath is required.' }
$EffectiveWorktreePath = if ([string]::IsNullOrWhiteSpace($WorktreePath)) { $null } else { Resolve-UserPath -Path $WorktreePath -Fallback $WorktreePath }
if ($EffectiveWorktreePath -and -not (Test-Path -LiteralPath $EffectiveWorktreePath)) { $failures += "Worktree path does not exist: $EffectiveWorktreePath" }

$manifestPath = Join-Path $TargetRoot '.agent\loops\lizard-agent-layer.loop-install.json'
$verifierRel = '.agent\loops\loop-verifier-report.md'
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if (($manifest.PSObject.Properties.Name -contains 'verifier_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.verifier_file)) { $verifierRel = [string]$manifest.verifier_file }
} else {
  $failures += 'Loop install manifest missing. Run loop-init.ps1 first.'
}

$reportPath = Join-Path $TargetRoot ($verifierRel.Replace('/', '\'))
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
$mdLines += '## Failures'
$mdLines += ''
if ($failures.Count -eq 0) { $mdLines += '- None' } else { foreach ($failure in $failures) { $mdLines += ('- {0}' -f $failure) } }

$outputMdPath = Join-Path $EffectiveOutputDir 'loop-verifier-report.md'
$mdLines | Set-Content -LiteralPath $outputMdPath -Encoding UTF8
if ($Apply -and $failures.Count -eq 0) {
  $parent = Split-Path -Parent $reportPath
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $mdLines | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

$report = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
  target = $TargetRoot
  worktree_path = $EffectiveWorktreePath
  branch = $Branch
  verifier = $Verifier
  status = $Status
  summary = $Summary
  verifier_file = $verifierRel
  verifier_file_written = ($Apply -and $failures.Count -eq 0)
  auto_merge = $false
  human_merge_review_required = $true
  failures = @($failures)
}
$jsonPath = Join-Path $EffectiveOutputDir 'loop-verify-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} else {
  Write-Host 'lizard-agent-layer L2 verifier'
  Write-Host "Mode: $($report.mode)"
  Write-Host "Status: $Status"
  Write-Host "Verifier: $Verifier"
  Write-Host "Worktree: $EffectiveWorktreePath"
  Write-Host "Auto-merge: forbidden"
  Write-Host "Output report: $outputMdPath"
  if ($Apply -and $failures.Count -eq 0) { Write-Host "Target verifier file: $reportPath" }
}
if ($failures.Count -gt 0) { exit 1 }
