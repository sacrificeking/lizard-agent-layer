param(
  [string]$TargetPath = (Get-Location).Path,
  [string[]]$Harnesses,
  [switch]$Apply,
  [switch]$Force
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
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ($manifest.profile) { $profile = $manifest.profile }
  if ((-not $selectedHarnesses -or $selectedHarnesses.Count -eq 0) -and $manifest.harnesses) { $selectedHarnesses = @($manifest.harnesses) }
} elseif (Test-Path -LiteralPath $profilePath) {
  $profileDoc = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
  if ($profileDoc.profile) { $profile = $profileDoc.profile }
  if ((-not $selectedHarnesses -or $selectedHarnesses.Count -eq 0) -and $profileDoc.harnesses) { $selectedHarnesses = @($profileDoc.harnesses) }
}

Write-Host "lizard-agent-layer upgrade"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $profile"
Write-Host "Harnesses: $($selectedHarnesses -join ', ')"
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host ""
Write-Host "This conservative upgrade repairs missing generated files. Existing files are preserved unless -Force is passed."
Write-Host ""

$argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ScriptDir 'install.ps1'), '-TargetPath', $TargetRoot, '-Profile', $profile)
if ($selectedHarnesses -and $selectedHarnesses.Count -gt 0) { $argsList += '-Harnesses'; $argsList += ($selectedHarnesses -join ',') }
if ($Apply) { $argsList += '-Apply' }
if ($Force) { $argsList += '-Force' }
& powershell.exe @argsList
