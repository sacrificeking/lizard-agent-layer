param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$Pattern = 'daily-triage',
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$Apply,
  [switch]$Force,
  [switch]$WritePlan,
  [string]$PlanPath,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
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

function Assert-PreviewOutputOutsideTarget {
  param([string]$Path, [string]$Label)
  if (-not $Apply -and $Path -and (Is-UnderPath -Path $Path -Root $TargetRoot)) {
    throw "$Label would write inside the target during preview. Choose a path outside the target or re-run with -Apply."
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
  if (-not (Is-UnderPath -Path $Dest -Root $TargetRoot)) { throw "Refusing to write outside target: $Dest" }
  $rel = To-TargetRel $Dest
  Add-Unique $Managed $rel
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) { Add-Unique $Skipped $rel; return }
  Add-Unique $Planned $rel
  if ($Apply) {
    $parent = Split-Path -Parent $Dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $Dest -Force:$Force
    Add-Unique $Written $rel
  }
}

function Write-Or-Skip {
  param([string]$Dest, [string]$Content)
  if (-not (Is-UnderPath -Path $Dest -Root $TargetRoot)) { throw "Refusing to write outside target: $Dest" }
  $rel = To-TargetRel $Dest
  Add-Unique $Managed $rel
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) { Add-Unique $Skipped $rel; return }
  Add-Unique $Planned $rel
  if ($Apply) {
    $parent = Split-Path -Parent $Dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $Dest -Value $Content -Encoding UTF8
    Add-Unique $Written $rel
  }
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\loops\init-$stamp")
$ShouldWritePlan = $WritePlan.IsPresent -or -not [string]::IsNullOrWhiteSpace($PlanPath)
$EffectivePlanPath = if ($ShouldWritePlan) { Resolve-UserPath -Path $PlanPath -Fallback (Join-Path $EffectiveOutputDir 'loop-init-plan.md') } else { $null }
Assert-PreviewOutputOutsideTarget -Path $EffectiveOutputDir -Label 'OutputDir'
Assert-PreviewOutputOutsideTarget -Path $EffectivePlanPath -Label 'PlanPath'
New-Item -ItemType Directory -Path $EffectiveOutputDir -Force | Out-Null
if ($EffectivePlanPath) {
  $planParent = Split-Path -Parent $EffectivePlanPath
  if ($planParent -and -not (Test-Path -LiteralPath $planParent)) { New-Item -ItemType Directory -Path $planParent -Force | Out-Null }
}

$Mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
$Planned = New-Object System.Collections.Generic.List[string]
$Written = New-Object System.Collections.Generic.List[string]
$Skipped = New-Object System.Collections.Generic.List[string]
$Managed = New-Object System.Collections.Generic.List[string]
$loopsRoot = Join-Path $TargetRoot '.agent\loops'
if (-not (Test-Path -LiteralPath $loopsRoot)) {
  Add-Unique $Planned '.agent\loops'
  if ($Apply) { New-Item -ItemType Directory -Path $loopsRoot -Force | Out-Null; Add-Unique $Written '.agent\loops' }
} else {
  Add-Unique $Skipped '.agent\loops'
}

$stateFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.stateFile) -Label 'stateFile'
$budgetFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.budgetFile) -Label 'budgetFile'
$runLogFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.runLogFile) -Label 'runLogFile'
$constraintsFileRel = Assert-SafeRelativeTargetPath -Path ([string]$PatternDoc.constraintsFile) -Label 'constraintsFile'

Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\LOOP.md') (Join-Path $loopsRoot 'LOOP.md')
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-budget.md') (Join-Path $TargetRoot $budgetFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-run-log.md') (Join-Path $TargetRoot $runLogFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-constraints.md') (Join-Path $TargetRoot $constraintsFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-state.md') (Join-Path $TargetRoot $stateFileRel)
Copy-Or-Skip (Join-Path $LayerRoot 'templates\loops\loop-state.md') (Join-Path $loopsRoot 'loop-state.md')

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
  skills = @($PatternDoc.skills)
  allowed_actions = @($PatternDoc.allowedActions)
  denied_actions = @($PatternDoc.deniedActions)
  human_gates = @($PatternDoc.humanGates)
  managed_paths = @($manifestManaged.ToArray())
}
Write-Or-Skip $manifestPath ($manifest | ConvertTo-Json -Depth 10)

$planLines = New-Object System.Collections.Generic.List[string]
$planLines.Add('# lizard-agent-layer loop init plan') | Out-Null
$planLines.Add('') | Out-Null
$planLines.Add(('- Mode: `{0}`' -f $Mode)) | Out-Null
$planLines.Add(('- Target: `{0}`' -f $TargetRoot)) | Out-Null
$planLines.Add(('- Pattern: `{0}`' -f $PatternDoc.name)) | Out-Null
$planLines.Add(('- Readiness: `{0}`' -f $PatternDoc.readinessLevel)) | Out-Null
$planLines.Add(('- Risk: `{0}`' -f $PatternDoc.riskLevel)) | Out-Null
$planLines.Add(('- Layer version: `{0}`' -f $LayerVersion)) | Out-Null
$planLines.Add('- Default action: report-only') | Out-Null
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
if ($ShouldWritePlan) { $planLines | Set-Content -LiteralPath $EffectivePlanPath -Encoding UTF8 }

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
  plan_path = $EffectivePlanPath
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $EffectiveOutputDir 'loop-init-report.json') -Encoding UTF8

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
