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
function Normalize-RelPath { param([string]$Path) return $Path.Replace('/', '\').TrimStart('\') }

Write-Host "lizard-agent-layer doctor"
Write-Host "Target: $TargetRoot"
Write-Host ""

$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
$manifestPath = Join-Path $TargetRoot '.agent\lizard-agent-layer.install.json'
$profile = $null
$manifest = $null
$harnesses = @()

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

if ($null -ne $manifest -and $manifest.harnesses) { $harnesses = @($manifest.harnesses) }
elseif ($null -ne $profile -and $profile.harnesses) { $harnesses = @($profile.harnesses) }

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
  '.agent\protocols\handoff.md',
  '.agent\skills\_index.md',
  '.agent\skills\_manifest.jsonl'
)) {
  Check-File $file -Required | Out-Null
}

if ($null -ne $profile) {
  foreach ($skill in @($profile.skills)) {
    Check-File ".agent\skills\$skill\SKILL.md" -Required | Out-Null
  }
}

foreach ($harness in $harnesses) {
  $adapterPath = Join-Path $TargetRoot "..\..\lizard-agent-layer\adapters\$harness\adapter.json"
  $layerAdapterPath = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "adapters\$harness\adapter.json"
  if (-not (Test-Path -LiteralPath $layerAdapterPath)) {
    Add-Warn "Adapter '$harness' is installed in manifest/profile, but this doctor cannot find its local adapter manifest."
    continue
  }
  $adapter = Get-Content -LiteralPath $layerAdapterPath -Raw | ConvertFrom-Json
  $dst = Normalize-RelPath $adapter.instruction.dst
  $sidecar = if ($adapter.instruction.sidecar) { Normalize-RelPath $adapter.instruction.sidecar } else { "$dst.lizard-agent-layer" }
  $dstPath = Join-Path $TargetRoot $dst
  $sidecarPath = Join-Path $TargetRoot $sidecar
  if (Test-Path -LiteralPath $dstPath) {
    $content = Get-Content -LiteralPath $dstPath -Raw
    if ($content -match 'lizard-agent-layer') { Add-Ok "$harness instruction wired at $dst" }
    elseif (Test-Path -LiteralPath $sidecarPath) { Add-Warn "$harness instruction $dst exists but is not wired; sidecar $sidecar exists." }
    else { Add-Warn "$harness instruction $dst exists but is not wired and no sidecar exists." }
  } elseif (Test-Path -LiteralPath $sidecarPath) {
    Add-Warn "$harness has only sidecar $sidecar; merge intentionally."
  } else {
    Add-Fail "$harness instruction missing: $dst"
  }

  foreach ($mirror in @($adapter.skillMirrors)) {
    $mirrorRel = Normalize-RelPath $mirror.dst
    Check-File $mirrorRel -Required | Out-Null
    if ($null -ne $profile) {
      foreach ($skill in @($profile.skills)) {
        Check-File "$mirrorRel\$skill\SKILL.md" -Required | Out-Null
      }
    }
  }
}

foreach ($line in $Ok) { Write-Host "  OK   $line" }
foreach ($line in $Warnings) { Write-Host "  WARN $line" }
foreach ($line in $Failures) { Write-Host "  FAIL $line" }

if ($Failures.Count -gt 0 -or ($Strict -and $Warnings.Count -gt 0)) { exit 1 }
Write-Host "Doctor completed. Failures=$($Failures.Count) Warnings=$($Warnings.Count)"
