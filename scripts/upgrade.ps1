param(
  [string]$TargetPath = (Get-Location).Path,
  [string[]]$Harnesses,
  [ValidateSet('curated', 'private-episodic', 'off')]
  [string]$MemoryMode,
  [switch]$Apply,
  [switch]$Force,
  [switch]$AllowDowngrade,
  [switch]$HumanApproved,
  [string]$OutputDir,
  [string]$PlanPath,
  [string]$CanonicalPlanPath,
  [string]$ApprovedPlanPath,
  [string]$ApprovedPlanSha256
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Json.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Host.psm1') -Force
$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$manifestPath = Join-Path $TargetRoot '.agent/lizard-agent-layer.install.json'
$profilePath = Join-Path $TargetRoot '.agent/project-profile.json'

if (-not (Test-Path -LiteralPath $manifestPath) -and -not (Test-Path -LiteralPath $profilePath)) {
  throw "Target is not installed yet. Run scripts\install.ps1 first."
}

$profile = 'standard'
$selectedHarnesses = $Harnesses
$selectedPacks = @()
$selectedMemoryMode = $MemoryMode
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $manifestPath -Raw)
  if ($manifest.profile) { $profile = $manifest.profile }
  if ((-not $selectedHarnesses -or $selectedHarnesses.Count -eq 0) -and $manifest.harnesses) { $selectedHarnesses = @($manifest.harnesses) }
  if ($manifest.requested_packs) { $selectedPacks = @($manifest.requested_packs) }
  elseif ($manifest.packs) { $selectedPacks = @($manifest.packs) }
  if ([string]::IsNullOrWhiteSpace($selectedMemoryMode) -and $manifest.memory_mode) { $selectedMemoryMode = [string]$manifest.memory_mode }
} elseif (Test-Path -LiteralPath $profilePath) {
  $profileDoc = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $profilePath -Raw)
  if ($profileDoc.profile) { $profile = $profileDoc.profile }
  if ((-not $selectedHarnesses -or $selectedHarnesses.Count -eq 0) -and $profileDoc.harnesses) { $selectedHarnesses = @($profileDoc.harnesses) }
  if ($profileDoc.requestedPacks) { $selectedPacks = @($profileDoc.requestedPacks) }
  elseif ($profileDoc.packs) { $selectedPacks = @($profileDoc.packs) }
  if ([string]::IsNullOrWhiteSpace($selectedMemoryMode) -and $profileDoc.memoryMode) { $selectedMemoryMode = [string]$profileDoc.memoryMode }
}
if ($selectedMemoryMode -notin @('curated', 'private-episodic', 'off')) { throw "MEMORY_MODE_MANIFEST_INVALID: Unsupported or missing memory mode '$selectedMemoryMode'." }

Write-Host "lizard-agent-layer upgrade"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $profile"
Write-Host "Harnesses: $($selectedHarnesses -join ', ')"
Write-Host "Packs: $($selectedPacks -join ', ')"
Write-Host "Memory mode: $selectedMemoryMode"
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host ""
Write-Host "This conservative upgrade repairs missing generated files. Existing files are preserved unless -Force is passed."
Write-Host ""

$workflowScript = if (Test-Path -LiteralPath $manifestPath) { 'update-target.ps1' } else { 'install.ps1' }
$argsList = @($PowerShellFilePrefix) + @((Join-Path $ScriptDir $workflowScript), '-TargetPath', $TargetRoot)
$argsList += @('-MemoryMode', $selectedMemoryMode)
if ($workflowScript -eq 'install.ps1') {
  $argsList += @('-Profile', $profile)
  if ($selectedHarnesses -and $selectedHarnesses.Count -gt 0) { $argsList += '-Harnesses'; $argsList += ($selectedHarnesses -join ',') }
  if ($selectedPacks -and $selectedPacks.Count -gt 0) { $argsList += '-Packs'; $argsList += ($selectedPacks -join ',') }
  if ($PlanPath) { $argsList += @('-WritePlan', '-PlanPath', $PlanPath) }
  if ($CanonicalPlanPath) { $argsList += @('-CanonicalPlanPath', $CanonicalPlanPath) }
} else {
  if ($Force) { $argsList += '-ForceManaged' }
  if ($AllowDowngrade) { $argsList += '-AllowDowngrade' }
  if ($HumanApproved) { $argsList += '-HumanApproved' }
  if ($OutputDir) { $argsList += @('-OutputDir', $OutputDir) }
  if ($PlanPath) { $argsList += @('-PlanPath', $PlanPath) }
  if ($CanonicalPlanPath) { $argsList += @('-CanonicalPlanPath', $CanonicalPlanPath) }
}
if ($Apply) {
  $argsList += '-Apply'
  if ($ApprovedPlanPath) { $argsList += @('-ApprovedPlanPath', $ApprovedPlanPath) }
  if ($ApprovedPlanSha256) { $argsList += @('-ApprovedPlanSha256', $ApprovedPlanSha256) }
  if ($HumanApproved -and $workflowScript -eq 'install.ps1') { $argsList += '-HumanApproved' }
}
& $PowerShellHost @argsList
