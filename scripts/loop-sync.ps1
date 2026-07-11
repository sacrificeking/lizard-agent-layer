param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$Pattern,
  [switch]$Apply,
  [switch]$ForceTemplates,
  [switch]$Strict,
  [switch]$Json,
  [string]$OutputDir,
  [int]$TestFailAfterMutation = 0
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$EffectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) { Join-Path $LayerRoot ".tmp\loops\sync-$stamp" } elseif ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path (Get-Location).Path $OutputDir }
function Is-UnderPath {
  param([string]$Path, [string]$Root)
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
  if ($full.Equals($rootFull, (Get-LizardPathComparison))) { return $true }
  return $full.StartsWith(($rootFull + [System.IO.Path]::DirectorySeparatorChar), (Get-LizardPathComparison))
}
if (Is-UnderPath -Path $EffectiveOutputDir -Root $TargetRoot) { throw 'OutputDir must stay outside the target.' }
$EffectiveOutputDir = Initialize-SafeDirectory -Path $EffectiveOutputDir

$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]
$Planned = New-Object System.Collections.Generic.List[string]
$Written = New-Object System.Collections.Generic.List[string]
$Skipped = New-Object System.Collections.Generic.List[string]
function Add-Unique { param($List, [string]$Value) if ($Value -and -not $List.Contains($Value)) { $List.Add($Value) | Out-Null } }
function Add-Failure { param([string]$Message) $Failures.Add($Message) | Out-Null }
function Add-Warning { param([string]$Message) $Warnings.Add($Message) | Out-Null }
function Assert-SafeRelativeTargetPath {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label is empty." }
  if ([System.IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:') { throw "$Label must be a relative target path: $Path" }
  $normalized = $Path.Replace('/', '\')
  if ($normalized -match '(^|\\)\.\.($|\\)') { throw "$Label must not traverse upward: $Path" }
  return $normalized
}
function Copy-Template {
  param([string]$Template, [string]$DestRel, [bool]$CanOverwrite)
  $source = Join-Path $LayerRoot $Template
  $dest = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $DestRel)
  if (-not (Test-Path -LiteralPath $source)) { Add-Failure "Template missing: $Template"; return }
  if ((Test-Path -LiteralPath $dest) -and -not $CanOverwrite) { Add-Unique $Skipped $DestRel; return }
  Add-Unique $Planned $DestRel
  if ($Apply) {
    $parent = Split-Path -Parent $dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-LizardTransactionalDirectory -Path $parent | Out-Null }
    Copy-LizardTransactionalFile -Source $source -Destination $dest -Force:$CanOverwrite
    Add-Unique $Written $DestRel
  }
}

$versionPath = Join-Path $LayerRoot 'VERSION'
$currentVersion = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { '0.0.0-dev' }
$manifestPath = Join-Path $TargetRoot '.agent\loops\lizard-agent-layer.loop-install.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Missing loop install manifest. Run loop-init.ps1 first.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$patternName = if (-not [string]::IsNullOrWhiteSpace($Pattern)) { $Pattern } elseif ($manifest.pattern) { [string]$manifest.pattern } else { 'daily-triage' }
$patternPath = Join-Path $LayerRoot ("loops\{0}.json" -f $patternName)
if (-not (Test-Path -LiteralPath $patternPath)) { throw "Unknown loop pattern '$patternName'." }
$patternDoc = Get-Content -LiteralPath $patternPath -Raw | ConvertFrom-Json

if ($manifest.layer_version -ne $currentVersion) { Add-Warning "Layer version drift: installed $($manifest.layer_version), current $currentVersion." }
if ($manifest.pattern -ne $patternDoc.name) { Add-Warning "Pattern drift: manifest $($manifest.pattern), current $($patternDoc.name)." }

$stateRel = Assert-SafeRelativeTargetPath ([string]$patternDoc.stateFile) 'stateFile'
$budgetRel = Assert-SafeRelativeTargetPath ([string]$patternDoc.budgetFile) 'budgetFile'
$runLogRel = Assert-SafeRelativeTargetPath ([string]$patternDoc.runLogFile) 'runLogFile'
$constraintsRel = Assert-SafeRelativeTargetPath ([string]$patternDoc.constraintsFile) 'constraintsFile'
$worktreePolicyRel = $null
$assistedPlanRel = $null
$verifierRel = $null
if (($patternDoc.PSObject.Properties.Name -contains 'worktreePolicyFile') -and -not [string]::IsNullOrWhiteSpace([string]$patternDoc.worktreePolicyFile)) { $worktreePolicyRel = Assert-SafeRelativeTargetPath ([string]$patternDoc.worktreePolicyFile) 'worktreePolicyFile' }
if (($patternDoc.PSObject.Properties.Name -contains 'assistedPlanFile') -and -not [string]::IsNullOrWhiteSpace([string]$patternDoc.assistedPlanFile)) { $assistedPlanRel = Assert-SafeRelativeTargetPath ([string]$patternDoc.assistedPlanFile) 'assistedPlanFile' }
if (($patternDoc.PSObject.Properties.Name -contains 'verifierFile') -and -not [string]::IsNullOrWhiteSpace([string]$patternDoc.verifierFile)) { $verifierRel = Assert-SafeRelativeTargetPath ([string]$patternDoc.verifierFile) 'verifierFile' }
$syncTransaction = $null
if ($Apply -and $Strict -and $Warnings.Count -gt 0) { throw "STRICT_SYNC_BLOCKED: $($Warnings -join '; ')" }
if ($Apply) { $syncTransaction = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName 'loop-sync' -FailAfterMutation $TestFailAfterMutation }
try {
Copy-Template 'templates\loops\LOOP.md' '.agent\loops\LOOP.md' ([bool]$ForceTemplates)
Copy-Template 'templates\loops\loop-budget.md' $budgetRel ([bool]$ForceTemplates)
Copy-Template 'templates\loops\loop-run-log.md' $runLogRel ([bool]$ForceTemplates)
Copy-Template 'templates\loops\loop-constraints.md' $constraintsRel ([bool]$ForceTemplates)
Copy-Template 'templates\loops\loop-state.md' $stateRel $false
Copy-Template 'templates\loops\loop-state.md' '.agent\loops\loop-state.md' $false
if ($worktreePolicyRel) { Copy-Template 'templates\loops\worktree-policy.md' $worktreePolicyRel ([bool]$ForceTemplates) }
if ($assistedPlanRel) { Copy-Template 'templates\loops\assisted-fix-plan.md' $assistedPlanRel $false }
if ($verifierRel) { Copy-Template 'templates\loops\loop-verifier-report.md' $verifierRel $false }

$managedPaths = @('.agent\loops\LOOP.md', $stateRel, $budgetRel, $runLogRel, $constraintsRel, '.agent\loops\loop-state.md', '.agent\loops\lizard-agent-layer.loop-install.json')
if ($worktreePolicyRel) { $managedPaths += $worktreePolicyRel }
if ($assistedPlanRel) { $managedPaths += $assistedPlanRel }
if ($verifierRel) { $managedPaths += $verifierRel }

$updatedManifest = [ordered]@{
  schema_version = 1
  layer = 'lizard-agent-layer'
  layer_version = $currentVersion
  installed_at = if ($manifest.installed_at) { [string]$manifest.installed_at } else { (Get-Date).ToUniversalTime().ToString('o') }
  synced_at = (Get-Date).ToUniversalTime().ToString('o')
  pattern = [string]$patternDoc.name
  readiness_level = [string]$patternDoc.readinessLevel
  risk_level = [string]$patternDoc.riskLevel
  state_file = [string]$patternDoc.stateFile
  budget_file = [string]$patternDoc.budgetFile
  run_log_file = [string]$patternDoc.runLogFile
  constraints_file = [string]$patternDoc.constraintsFile
  worktree_policy_file = if ($worktreePolicyRel) { [string]$patternDoc.worktreePolicyFile } else { $null }
  assisted_plan_file = if ($assistedPlanRel) { [string]$patternDoc.assistedPlanFile } else { $null }
  verifier_file = if ($verifierRel) { [string]$patternDoc.verifierFile } else { $null }
  skills = @($patternDoc.skills)
  allowed_actions = @($patternDoc.allowedActions)
  denied_actions = @($patternDoc.deniedActions)
  human_gates = @($patternDoc.humanGates)
  managed_paths = @($managedPaths)
  transaction_operation_id = if ($syncTransaction) { [string]$syncTransaction.operation_id } else { $null }
}
Add-Unique $Planned '.agent\loops\lizard-agent-layer.loop-install.json'
if ($Apply) {
  if ($Failures.Count -gt 0) { throw "LOOP_SYNC_PREFLIGHT_FAILED: $($Failures -join '; ')" }
  Set-LizardTransactionalContent -Path $manifestPath -Value ($updatedManifest | ConvertTo-Json -Depth 10)
  Add-Unique $Written '.agent\loops\lizard-agent-layer.loop-install.json'
  Complete-LizardTransaction | Out-Null
}
} catch {
  $loopSyncError = $_
  if ($Apply -and (Test-Path -LiteralPath (Join-Path $TargetRoot '.lizard-agent-layer.lock'))) {
    try { Undo-LizardTransaction | Out-Null } catch { Write-Warning "Loop sync rollback requires recovery: $($_.Exception.Message)" }
  }
  throw $loopSyncError
}

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
  target = $TargetRoot
  pattern = [string]$patternDoc.name
  current_layer_version = $currentVersion
  installed_layer_version = [string]$manifest.layer_version
  force_templates = $ForceTemplates.IsPresent
  planned = @($Planned.ToArray())
  written = @($Written.ToArray())
  skipped = @($Skipped.ToArray())
  warnings = @($Warnings.ToArray())
  failures = @($Failures.ToArray())
}
$reportPath = Join-Path $EffectiveOutputDir 'loop-sync-report.json'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 10)

if ($Json) {
  $report | ConvertTo-Json -Depth 10
} else {
  Write-Host 'lizard-agent-layer loop sync'
  Write-Host "Mode: $($report.mode)"
  Write-Host "Target: $TargetRoot"
  Write-Host "Pattern: $($patternDoc.name)"
  Write-Host "Planned: $($Planned.Count)"
  Write-Host "Written: $($Written.Count)"
  Write-Host "Skipped: $($Skipped.Count)"
  Write-Host "Warnings: $($Warnings.Count)"
  Write-Host "Report: $reportPath"
  if (-not $Apply) { Write-Host 'Preview only. Re-run with -Apply to update loop metadata or create missing files.' }
}
if ($Failures.Count -gt 0 -or ($Strict -and $Warnings.Count -gt 0)) { exit 1 }
