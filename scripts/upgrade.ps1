param(
  [string]$TargetPath = (Get-Location).Path,
  [string[]]$Harnesses,
  [switch]$Apply,
  [switch]$Force,
  [switch]$AllowDowngrade,
  [switch]$HumanApproved
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$manifestPath = Join-Path $TargetRoot '.agent\lizard-agent-layer.install.json'
$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'

if (-not (Test-Path -LiteralPath $manifestPath) -and -not (Test-Path -LiteralPath $profilePath)) {
  throw "Target is not installed yet. Run scripts\install.ps1 first."
}

$profile = 'standard'
$selectedHarnesses = $Harnesses
$selectedPacks = @()
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ($manifest.profile) { $profile = $manifest.profile }
  if ((-not $selectedHarnesses -or $selectedHarnesses.Count -eq 0) -and $manifest.harnesses) { $selectedHarnesses = @($manifest.harnesses) }
  if ($manifest.requested_packs) { $selectedPacks = @($manifest.requested_packs) }
  elseif ($manifest.packs) { $selectedPacks = @($manifest.packs) }
} elseif (Test-Path -LiteralPath $profilePath) {
  $profileDoc = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
  if ($profileDoc.profile) { $profile = $profileDoc.profile }
  if ((-not $selectedHarnesses -or $selectedHarnesses.Count -eq 0) -and $profileDoc.harnesses) { $selectedHarnesses = @($profileDoc.harnesses) }
  if ($profileDoc.requestedPacks) { $selectedPacks = @($profileDoc.requestedPacks) }
  elseif ($profileDoc.packs) { $selectedPacks = @($profileDoc.packs) }
}

Write-Host "lizard-agent-layer upgrade"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $profile"
Write-Host "Harnesses: $($selectedHarnesses -join ', ')"
Write-Host "Packs: $($selectedPacks -join ', ')"
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host ""
Write-Host "This conservative upgrade repairs missing generated files. Existing files are preserved unless -Force is passed."
Write-Host ""

$workflowScript = if (Test-Path -LiteralPath $manifestPath) { 'update-target.ps1' } else { 'install.ps1' }
$argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ScriptDir $workflowScript), '-TargetPath', $TargetRoot)
if ($workflowScript -eq 'install.ps1') {
  $argsList += @('-Profile', $profile)
  if ($selectedHarnesses -and $selectedHarnesses.Count -gt 0) { $argsList += '-Harnesses'; $argsList += ($selectedHarnesses -join ',') }
  if ($selectedPacks -and $selectedPacks.Count -gt 0) { $argsList += '-Packs'; $argsList += ($selectedPacks -join ',') }
} else {
  if ($Force) { $argsList += '-ForceManaged' }
  if ($AllowDowngrade) { $argsList += '-AllowDowngrade' }
  if ($HumanApproved) { $argsList += '-HumanApproved' }
}
if ($Apply) { $argsList += '-Apply' }
& powershell.exe @argsList
