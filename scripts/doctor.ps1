param(
  [string]$TargetPath = (Get-Location).Path,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]
$Ok = New-Object System.Collections.Generic.List[string]

function Add-Ok { param([string]$Message) $Ok.Add($Message) | Out-Null }
function Add-Warn { param([string]$Message) $Warnings.Add($Message) | Out-Null }
function Add-Fail { param([string]$Message) $Failures.Add($Message) | Out-Null }
function Check-File {
  param([string]$Relative, [switch]$Required)
  $path = Join-Path $TargetRoot $Relative
  if (Test-Path -LiteralPath $path) { Add-Ok "$Relative exists"; return $true }
  if ($Required) { Add-Fail "$Relative missing" } else { Add-Warn "$Relative missing" }
  return $false
}

Write-Host "lizard-agent-layer doctor"
Write-Host "Target: $TargetRoot"
Write-Host ""

$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
$manifestPath = Join-Path $TargetRoot '.agent\lizard-agent-layer.install.json'
$profile = $null
$manifest = $null

Check-File '.agent\project-profile.json' -Required | Out-Null
if (Test-Path -LiteralPath $profilePath) {
  try { $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json; Add-Ok "profile loaded: $($profile.profile)" }
  catch { Add-Fail "project-profile.json is invalid JSON: $($_.Exception.Message)" }
}

if (Test-Path -LiteralPath $manifestPath) {
  try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json; Add-Ok "install manifest loaded: $($manifest.layer_version)" }
  catch { Add-Fail "install manifest is invalid JSON: $($_.Exception.Message)" }
} else {
  Add-Warn '.agent\lizard-agent-layer.install.json missing; target may be preview-only or pre-manifest install.'
}

foreach ($file in @(
  '.agent\.gitignore',
  '.agent\memory\personal\PREFERENCES.md',
  '.agent\memory\semantic\DECISIONS.md',
  '.agent\memory\semantic\LESSONS.md',
  '.agent\memory\working\WORKSPACE.md',
  '.agent\protocols\permissions.md',
  '.agent\protocols\memory-policy.md',
  '.agent\protocols\secret-handling.md',
  '.agent\protocols\release-gates.md',
  '.agent\skills\_index.md',
  '.agent\skills\_manifest.jsonl'
)) {
  Check-File $file -Required | Out-Null
}

if ($null -ne $profile) {
  foreach ($skill in @($profile.skills)) {
    Check-File ".agent\skills\$skill\SKILL.md" -Required | Out-Null
    Check-File ".agents\skills\$skill\SKILL.md" -Required | Out-Null
  }
}

$agentsPath = Join-Path $TargetRoot 'AGENTS.md'
$sidecarPath = Join-Path $TargetRoot 'AGENTS.lizard-agent-layer.md'
if (Test-Path -LiteralPath $agentsPath) {
  $agents = Get-Content -LiteralPath $agentsPath -Raw
  if ($agents -match 'lizard-agent-layer') { Add-Ok 'AGENTS.md is wired to lizard-agent-layer' }
  elseif (Test-Path -LiteralPath $sidecarPath) { Add-Warn 'AGENTS.md exists but is not wired; sidecar merge file exists.' }
  else { Add-Warn 'AGENTS.md exists but is not wired and no sidecar merge file exists.' }
} elseif (Test-Path -LiteralPath $sidecarPath) {
  Add-Warn 'Only AGENTS.lizard-agent-layer.md exists; merge or rename intentionally.'
} else {
  Add-Fail 'No AGENTS.md or AGENTS.lizard-agent-layer.md found.'
}

foreach ($line in $Ok) { Write-Host "  OK   $line" }
foreach ($line in $Warnings) { Write-Host "  WARN $line" }
foreach ($line in $Failures) { Write-Host "  FAIL $line" }

if ($Failures.Count -gt 0 -or ($Strict -and $Warnings.Count -gt 0)) { exit 1 }
Write-Host "Doctor completed. Failures=$($Failures.Count) Warnings=$($Warnings.Count)"
