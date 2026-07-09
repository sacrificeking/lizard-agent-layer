param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$Strict,
  [switch]$Json,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$EffectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) { Join-Path $LayerRoot ".tmp\loops\report-$stamp" } elseif ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path (Get-Location).Path $OutputDir }
New-Item -ItemType Directory -Path $EffectiveOutputDir -Force | Out-Null

$failures = @()
$fileRows = @()
function Add-Failure { param([string]$Message) $script:failures += $Message }
function Get-FirstHeading {
  param([string]$Relative)
  $resolved = Join-Path $TargetRoot ($Relative.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $resolved)) { return $null }
  $lines = @(Get-Content -LiteralPath $resolved -TotalCount 40)
  foreach ($line in $lines) {
    if ($line -match '^#+\s+') { return $line }
  }
  return $null
}
function Add-FileStatus {
  param([string]$Label, [string]$Relative)
  if ([string]::IsNullOrWhiteSpace($Relative)) {
    Add-Failure "$Label path is empty."
    $script:fileRows += [pscustomobject]@{ label = $Label; path = ''; exists = $false; heading = $null }
    return
  }
  $path = Join-Path $TargetRoot ($Relative.Replace('/', '\'))
  $exists = Test-Path -LiteralPath $path
  $heading = $null
  if ($exists) { $heading = [string](Get-FirstHeading -Relative $Relative) }
  $script:fileRows += [pscustomobject]@{ label = $Label; path = $Relative; exists = $exists; heading = $heading }
  if (-not $exists) { Add-Failure "$Label missing: $Relative" }
}

$manifestPath = Join-Path $TargetRoot '.agent\loops\lizard-agent-layer.loop-install.json'
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
  try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
  catch { Add-Failure "Invalid loop manifest: $($_.Exception.Message)" }
} else {
  Add-Failure 'Loop manifest missing. Run loop-init.ps1 first.'
}

if ($null -ne $manifest) {
  Add-FileStatus 'Control document' '.agent\loops\LOOP.md'
  Add-FileStatus 'State' ([string]$manifest.state_file)
  Add-FileStatus 'Budget' ([string]$manifest.budget_file)
  Add-FileStatus 'Run log' ([string]$manifest.run_log_file)
  Add-FileStatus 'Constraints' ([string]$manifest.constraints_file)
  if (($manifest.PSObject.Properties.Name -contains 'worktree_policy_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.worktree_policy_file)) { Add-FileStatus 'Worktree policy' ([string]$manifest.worktree_policy_file) }
  if (($manifest.PSObject.Properties.Name -contains 'assisted_plan_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.assisted_plan_file)) { Add-FileStatus 'Assisted fix plan' ([string]$manifest.assisted_plan_file) }
  if (($manifest.PSObject.Properties.Name -contains 'verifier_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.verifier_file)) { Add-FileStatus 'Verifier report' ([string]$manifest.verifier_file) }
}

$report = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  target = $TargetRoot
  pattern = if ($null -ne $manifest) { [string]$manifest.pattern } else { $null }
  installed_layer_version = if ($null -ne $manifest) { [string]$manifest.layer_version } else { $null }
  readiness_level = if ($null -ne $manifest) { [string]$manifest.readiness_level } else { $null }
  risk_level = if ($null -ne $manifest) { [string]$manifest.risk_level } else { $null }
  worktree_policy_file = if ($null -ne $manifest -and ($manifest.PSObject.Properties.Name -contains 'worktree_policy_file')) { [string]$manifest.worktree_policy_file } else { $null }
  assisted_plan_file = if ($null -ne $manifest -and ($manifest.PSObject.Properties.Name -contains 'assisted_plan_file')) { [string]$manifest.assisted_plan_file } else { $null }
  verifier_file = if ($null -ne $manifest -and ($manifest.PSObject.Properties.Name -contains 'verifier_file')) { [string]$manifest.verifier_file } else { $null }
  skills = if ($null -ne $manifest) { @($manifest.skills) } else { @() }
  human_gates = if ($null -ne $manifest) { @($manifest.human_gates) } else { @() }
  files = @($fileRows | ForEach-Object { [pscustomobject]@{ label = [string]$_.label; path = [string]$_.path; exists = [bool]$_.exists; heading = if ($null -ne $_.heading) { [string]$_.heading } else { $null } } })
  failures = @($failures)
}
$jsonPath = Join-Path $EffectiveOutputDir 'loop-report.json'
$mdPath = Join-Path $EffectiveOutputDir 'loop-report.md'
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @()
$lines += '# lizard-agent-layer loop report'
$lines += ''
$lines += ('- Target: `{0}`' -f $TargetRoot)
$lines += ('- Pattern: `{0}`' -f $report.pattern)
$lines += ('- Layer version: `{0}`' -f $report.installed_layer_version)
$lines += ('- Readiness: `{0}`' -f $report.readiness_level)
$lines += ('- Risk: `{0}`' -f $report.risk_level)
$lines += ''
$lines += '## Files'
$lines += ''
foreach ($row in @($fileRows)) {
  $status = if ($row.exists) { 'ok' } else { 'missing' }
  $lines += ('- `{0}` - {1} ({2})' -f $row.path, $row.label, $status)
}
$lines += ''
$lines += '## Human Gates'
$lines += ''
if (@($report.human_gates).Count -eq 0) { $lines += '- None recorded' } else { foreach ($gate in @($report.human_gates)) { $lines += ('- {0}' -f $gate) } }
$lines += ''
$lines += '## Failures'
$lines += ''
if ($failures.Count -eq 0) { $lines += '- None' } else { foreach ($failure in $failures) { $lines += ('- {0}' -f $failure) } }
$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8

if ($Json) {
  $report | ConvertTo-Json -Depth 10
} else {
  Write-Host 'lizard-agent-layer loop report'
  Write-Host "Target: $TargetRoot"
  Write-Host "Pattern: $($report.pattern)"
  Write-Host "Failures: $($failures.Count)"
  Write-Host "Markdown: $mdPath"
  Write-Host "JSON: $jsonPath"
}
if ($failures.Count -gt 0 -and $Strict) { exit 1 }
