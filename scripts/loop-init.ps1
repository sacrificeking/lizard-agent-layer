param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$Pattern = 'daily-triage',
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$Apply,
  [switch]$Force,
  [switch]$WritePlan,
  [string]$PlanPath,
  [string]$OutputDir,
  [int]$TestFailAfterMutation = 0
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$VersionPath = Join-Path $LayerRoot 'VERSION'
$LayerVersion = if (Test-Path -LiteralPath $VersionPath) { (Get-Content -LiteralPath $VersionPath -Raw).Trim() } else { '0.0.0-dev' }
$PatternPath = Join-Path $LayerRoot ("loops\{0}.json" -f $Pattern)
if (-not (Test-Path -LiteralPath $PatternPath)) { throw "Unknown loop pattern '$Pattern'. Expected loops/$Pattern.json." }
$PatternDoc = Get-Content -LiteralPath $PatternPath -Raw | ConvertFrom-Json

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
  $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
  return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-OutputOutsideTarget {
  param([string]$Path, [string]$Label)
  if ($Path -and (Is-UnderPath -Path $Path -Root $TargetRoot)) {
    throw "$Label must stay outside the target."
  }
}

function Assert-SafeRelativeTargetPath {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label is empty." }
  if ([System.IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:') { throw "$Label must be a relative target path: $Path" }
  $normalized = $Path.Replace('/', '\')
  if ($normalized -match '(^|\\)\.\.($|\\)') { throw "$Label must not traverse upward: $Path" }
  if ($normalized -match '(^|\\)\.($|\\)') { throw "$Label must not contain current-directory segments: $Path" }
  return $normalized
}

function To-TargetRel {
  param([string]$Path)
  $full = [System.IO.Path]::GetFullPath($Path)
  $rootFull = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd([char[]]@('\', '/'))
  $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
  if ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $full.Substring($prefix.Length) }
  return $Path
}

function Add-Unique {
  param($List, [string]$Value)
  if ($Value -and -not $List.Contains($Value)) { $List.Add($Value) | Out-Null }
}

function Copy-Or-Skip {
  param([string]$Source, [string]$Dest)
  if (-not (Test-Path -LiteralPath $Source)) { throw "Missing source file: $Source" }
  $Dest = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $Dest
  $rel = To-TargetRel $Dest
  Add-Unique $Managed $rel
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) { Add-Unique $Skipped $rel; return }
  Add-Unique $Planned $rel
  if ($Apply) {
    $parent = Split-Path -Parent $Dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-LizardTransactionalDirectory -Path $parent | Out-Null }
    Copy-LizardTransactionalFile -Source $Source -Destination $Dest -Force:$Force
    Add-Unique $Written $rel
  }
}

function Write-Or-Skip {
  param([string]$Dest, [string]$Content)
  $Dest = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $Dest
  $rel = To-TargetRel $Dest
  Add-Unique $Managed $rel
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) { Add-Unique $Skipped $rel; return }
  Add-Unique $Planned $rel
  if ($Apply) {
    $parent = Split-Path -Parent $Dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-LizardTransactionalDirectory -Path $parent | Out-Null }
    Set-LizardTransactionalContent -Path $Dest -Value $Content
    Add-Unique $Written $rel
  }
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\init-$stamp")
$ShouldWritePlan = $WritePlan.IsPresent -or -not [string]::IsNullOrWhiteSpace($PlanPath)
$EffectivePlanPath = if ($ShouldWritePlan) { Resolve-UserPath -Path $PlanPath -Fallback (Join-Path $EffectiveOutputDir 'loop-init-plan.md') } else { $null }
Assert-OutputOutsideTarget -Path $EffectiveOutputDir -Label 'OutputDir'
Assert-OutputOutsideTarget -Path $EffectivePlanPath -Label 'PlanPath'
$EffectiveOutputDir = Initialize-SafeDirectory -Path $EffectiveOutputDir
if ($EffectivePlanPath) {
  $planParent = Split-Path -Parent $EffectivePlanPath
  if ($planParent) { $planParent = Initialize-SafeDirectory -Path $planParent }
}

$Mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
$Planned = New-Object System.Collections.Generic.List[string]
$Written = New-Object System.Collections.Generic.List[string]
$Skipped = New-Object System.Collections.Generic.List[string]
$Managed = New-Object System.Collections.Generic.List[string]
$loopsRoot = Join-Path $TargetRoot '.agent\loops'

$stateFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.stateFile) -Label 'stateFile'
$budgetFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.budgetFile) -Label 'budgetFile'
$runLogFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.runLogFile) -Label 'runLogFile'
$constraintsFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.constraintsFile) -Label 'constraintsFile'
$worktreePolicyRel = $null
$assistedPlanRel = $null
$verifierRel = $null
if (($PatternDoc.PSObject.Properties.Name -contains 'worktreePolicyFile') -and -not [string]::IsNullOrWhiteSpace([string]$PatternDoc.worktreePolicyFile)) {
  $worktreePolicyRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.worktreePolicyFile) -Label 'worktreePolicyFile'
}
if (($PatternDoc.PSObject.Properties.Name -contains 'assistedPlanFile') -and -not [string]::IsNullOrWhiteSpace([string]$PatternDoc.assistedPlanFile)) {
  $assistedPlanRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.assistedPlanFile) -Label 'assistedPlanFile'
}
if (($PatternDoc.PSObject.Properties.Name -contains 'verifierFile') -and -not [string]::IsNullOrWhiteSpace([string]$PatternDoc.verifierFile)) {
  $verifierRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.verifierFile) -Label 'verifierFile'
}

$loopTransaction = $null
if ($Apply) { $loopTransaction = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName 'loop-init' -FailAfterMutation $TestFailAfterMutation }
try {
if (-not (Test-Path -LiteralPath $loopsRoot)) {
  Add-Unique $Planned '.agent\loops'
  if ($Apply) { New-LizardTransactionalDirectory -Path $loopsRoot | Out-Null; Add-Unique $Written '.agent\loops' }
} else {
  if (-not (Test-Path -LiteralPath $loopsRoot -PathType Container)) { throw 'DESTINATION_TYPE_CONFLICT: .agent/loops must be a directory.' }
  Add-Unique $Skipped '.agent\loops'
}

Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\LOOP.md') (Join-Path $loopsRoot 'LOOP.md')
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-budget.md') (Join-Path $TargetRoot $budgetFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-run-log.md') (Join-Path $TargetRoot $runLogFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-constraints.md') (Join-Path $TargetRoot $constraintsFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-state.md') (Join-Path $TargetRoot $stateFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-state.md') (Join-Path $loopsRoot 'loop-state.md')
if ($worktreePolicyRel) { Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\worktree-policy.md') (Join-Path $TargetRoot $worktreePolicyRel) }
if ($assistedPlanRel) { Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\assisted-fix-plan.md') (Join-Path $TargetRoot $assistedPlanRel) }
if ($verifierRel) { Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-verifier-report.md') (Join-Path $TargetRoot $verifierRel) }

$manifestPath = Join-Path $loopsRoot 'lizard-agent-layer.loop-install.json'
$manifestRel = To-TargetRel $manifestPath
$manifestManaged = New-Object System.Collections.Generic.List[string]
foreach ($item in $Managed) { Add-Unique $manifestManaged $item }
Add-Unique $manifestManaged $manifestRel
$manifest = [ordered]@{
  schema_version = 1
  layer = 'lizard-agent-layer'
  layer_version = $LayerVersion
  installed_at = (Get-Date).ToUniversalTime().ToString('o')
  pattern = [string]$PatternDoc.name
  readiness_level = [string]$PatternDoc.readinessLevel
  risk_level = [string]$PatternDoc.riskLevel
  state_file = [string]$PatternDoc.stateFile
  budget_file = [string]$PatternDoc.budgetFile
  run_log_file = [string]$PatternDoc.runLogFile
  constraints_file = [string]$PatternDoc.constraintsFile
  worktree_policy_file = if ($worktreePolicyRel) { [string]$PatternDoc.worktreePolicyFile } else { $null }
  assisted_plan_file = if ($assistedPlanRel) { [string]$PatternDoc.assistedPlanFile } else { $null }
  verifier_file = if ($verifierRel) { [string]$PatternDoc.verifierFile } else { $null }
  skills = @($PatternDoc.skills)
  allowed_actions = @($PatternDoc.allowedActions)
  denied_actions = @($PatternDoc.deniedActions)
  human_gates = @($PatternDoc.humanGates)
  managed_paths = @($manifestManaged.ToArray())
  transaction_operation_id = if ($loopTransaction) { [string]$loopTransaction.operation_id } else { $null }
}
Write-Or-Skip $manifestPath ($manifest | ConvertTo-Json -Depth 10)
if ($Apply) { Complete-LizardTransaction | Out-Null }
} catch {
  $loopInitError = $_
  if ($Apply -and (Test-Path -LiteralPath (Join-Path $TargetRoot '.lizard-agent-layer.lock'))) {
    try { Undo-LizardTransaction | Out-Null } catch { Write-Warning "Loop init rollback requires recovery: $($_.Exception.Message)" }
  }
  throw $loopInitError
}

$planLines = New-Object System.Collections.Generic.List[string]
$planLines.Add('# lizard-agent-layer loop init plan') | Out-Null
$planLines.Add('') | Out-Null
$planLines.Add(('- Mode: `{0}`' -f $Mode)) | Out-Null
$planLines.Add(('- Target: `{0}`' -f $TargetRoot)) | Out-Null
$planLines.Add(('- Pattern: `{0}`' -f $PatternDoc.name)) | Out-Null
$planLines.Add(('- Readiness: `{0}`' -f $PatternDoc.readinessLevel)) | Out-Null
$planLines.Add(('- Risk: `{0}`' -f $PatternDoc.riskLevel)) | Out-Null
$planLines.Add(('- Layer version: `{0}`' -f $LayerVersion)) | Out-Null
$defaultAction = if ([string]$PatternDoc.readinessLevel -eq 'L2') { 'assisted worktree only; no auto-merge' } else { 'report-only' }
$planLines.Add(('- Default action: {0}' -f $defaultAction)) | Out-Null
$planLines.Add('- Existing files: skipped unless `-Force` is supplied') | Out-Null
$planLines.Add('') | Out-Null
$planLines.Add('## Planned paths') | Out-Null
$planLines.Add('') | Out-Null
if ($Planned.Count -eq 0) { $planLines.Add('- None') | Out-Null } else { foreach ($item in $Planned) { $planLines.Add(('- `{0}`' -f $item)) | Out-Null } }
$planLines.Add('') | Out-Null
$planLines.Add('## Skipped paths') | Out-Null
$planLines.Add('') | Out-Null
if ($Skipped.Count -eq 0) { $planLines.Add('- None') | Out-Null } else { foreach ($item in $Skipped) { $planLines.Add(('- `{0}`' -f $item)) | Out-Null } }
$planLines.Add('') | Out-Null
$planLines.Add('## Human gates') | Out-Null
$planLines.Add('') | Out-Null
foreach ($gate in @($PatternDoc.humanGates)) { $planLines.Add(('- {0}' -f $gate)) | Out-Null }
if ($ShouldWritePlan) { Set-SafeContent -AuthorizedRoot $planParent -Path $EffectivePlanPath -Value $planLines }

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = $Mode
  target = $TargetRoot
  pattern = [string]$PatternDoc.name
  readiness_level = [string]$PatternDoc.readinessLevel
  risk_level = [string]$PatternDoc.riskLevel
  layer_version = $LayerVersion
  force = $Force.IsPresent
  planned = @($Planned.ToArray())
  written = @($Written.ToArray())
  skipped = @($Skipped.ToArray())
  managed_paths = @($manifestManaged.ToArray())
  default_action = $defaultAction
  plan_path = $EffectivePlanPath
}
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path (Join-Path $EffectiveOutputDir 'loop-init-report.json') -Value ($report | ConvertTo-Json -Depth 10)

Write-Host "lizard-agent-layer loop init $Mode"
Write-Host "Target: $TargetRoot"
Write-Host "Pattern: $($PatternDoc.name)"
Write-Host "Readiness: $($PatternDoc.readinessLevel)"
Write-Host "Risk: $($PatternDoc.riskLevel)"
Write-Host "Planned: $($Planned.Count)"
Write-Host "Written: $($Written.Count)"
Write-Host "Skipped: $($Skipped.Count)"
Write-Host "Report: $(Join-Path $EffectiveOutputDir 'loop-init-report.json')"
if ($EffectivePlanPath) { Write-Host "Plan: $EffectivePlanPath" }
if (-not $Apply) { Write-Host 'Preview only. Re-run with -Apply to write loop runtime files.' }
