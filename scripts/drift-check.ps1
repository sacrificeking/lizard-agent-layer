param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$BaselinePath,
  [string]$OutputDir,
  [switch]$UpdateBaseline,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
if ([string]::IsNullOrWhiteSpace($BaselinePath)) { $BaselinePath = Join-Path $LayerRoot 'registry\drift-baseline.json' }
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $LayerRoot '.tmp\drift' }
$OutputDir = Initialize-SafeDirectory -Path $OutputDir

function Get-RelativePath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $resolved.Substring($LayerRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}

function Get-ArtifactKind {
  param([string]$RelativePath)
  $first = ($RelativePath -split '/')[0]
  switch ($first) {
    'adapters' { 'adapter' }
    'skills' { 'skill' }
    'protocols' { 'protocol' }
    'profiles' { 'profile' }
    'model-profiles' { 'model-profile' }
    'packs' { 'pack' }
    'loops' { 'loop' }
    'templates' { 'template' }
    'registry' { 'registry' }
    'schemas' { 'schema' }
    default { 'other' }
  }
}

function Read-TextMetrics {
  param([string]$Path)
  $text = [System.IO.File]::ReadAllText($Path)
  if ($null -eq $text) { $text = '' }
  $canonical = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  $lineCount = if ($canonical.Length -eq 0) { 0 } else { @($canonical -split "`n").Count }
  $wordCount = ([regex]::Matches($canonical, '\S+')).Count
  $tokenEstimate = [Math]::Ceiling([Math]::Max(1, $canonical.Length) / 4)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  $bytes = $encoding.GetBytes($canonical)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
  [ordered]@{ sha256 = $hash; bytes = [int64]$bytes.Length; lines = $lineCount; words = $wordCount; token_estimate = [int]$tokenEstimate }
}

function New-ArtifactRecord {
  param([System.IO.FileInfo]$File)
  $relative = Get-RelativePath $File.FullName
  $metrics = Read-TextMetrics -Path $File.FullName
  [ordered]@{
    kind = Get-ArtifactKind $relative
    path = $relative
    sha256 = [string]$metrics.sha256
    bytes = [int64]$metrics.bytes
    lines = [int]$metrics.lines
    words = [int]$metrics.words
    token_estimate = [int]$metrics.token_estimate
  }
}

function Get-TrackedFiles {
  $roots = @('adapters', 'skills', 'protocols', 'profiles', 'model-profiles', 'packs', 'loops', 'templates', 'registry', 'schemas')
  $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
  foreach ($root in $roots) {
    $path = Join-Path $LayerRoot $root
    if (-not (Test-Path -LiteralPath $path)) { continue }
    Get-ChildItem -LiteralPath $path -Recurse -File | Sort-Object FullName | ForEach-Object {
      $relative = Get-RelativePath $_.FullName
      if ($relative -eq 'registry/drift-baseline.json') { return }
      $files.Add($_) | Out-Null
    }
  }
  @($files.ToArray())
}

function New-Snapshot {
  $versionPath = Join-Path $LayerRoot 'VERSION'
  $layerVersion = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { '0.0.0-dev' }
  $artifacts = New-Object System.Collections.Generic.List[object]
  foreach ($file in Get-TrackedFiles) { $artifacts.Add((New-ArtifactRecord -File $file)) | Out-Null }
  $totalTokens = 0
  $totalBytes = 0
  foreach ($artifact in @($artifacts.ToArray())) {
    $totalTokens += [int]$artifact.token_estimate
    $totalBytes += [int64]$artifact.bytes
  }
  [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    layer_version = $layerVersion
    artifact_count = $artifacts.Count
    total_bytes = $totalBytes
    token_estimate = $totalTokens
    artifacts = @($artifacts.ToArray())
  }
}

function Convert-ToArtifactMap {
  param([object[]]$Artifacts)
  $map = @{}
  foreach ($artifact in @($Artifacts)) { $map[[string]$artifact.path] = $artifact }
  $map
}

function Compare-Snapshots {
  param([object]$Baseline, [object]$Current)
  $baselineMap = Convert-ToArtifactMap @($Baseline.artifacts)
  $currentMap = Convert-ToArtifactMap @($Current.artifacts)
  $added = New-Object System.Collections.Generic.List[object]
  $removed = New-Object System.Collections.Generic.List[object]
  $changed = New-Object System.Collections.Generic.List[object]

  foreach ($path in @($currentMap.Keys | Sort-Object)) {
    if (-not $baselineMap.ContainsKey($path)) {
      $added.Add($currentMap[$path]) | Out-Null
      continue
    }
    $old = $baselineMap[$path]
    $new = $currentMap[$path]
    if ([string]$old.sha256 -ne [string]$new.sha256) {
      $changed.Add([ordered]@{
        path = $path
        kind = [string]$new.kind
        old_sha256 = [string]$old.sha256
        new_sha256 = [string]$new.sha256
        old_token_estimate = [int]$old.token_estimate
        new_token_estimate = [int]$new.token_estimate
        token_delta = ([int]$new.token_estimate - [int]$old.token_estimate)
      }) | Out-Null
    }
  }
  foreach ($path in @($baselineMap.Keys | Sort-Object)) {
    if (-not $currentMap.ContainsKey($path)) { $removed.Add($baselineMap[$path]) | Out-Null }
  }

  $tokenDelta = [int]$Current.token_estimate - [int]$Baseline.token_estimate
  [ordered]@{
    status = if ($added.Count -eq 0 -and $changed.Count -eq 0 -and $removed.Count -eq 0) { 'pass' } else { 'drift' }
    added = @($added.ToArray())
    changed = @($changed.ToArray())
    removed = @($removed.ToArray())
    added_count = $added.Count
    changed_count = $changed.Count
    removed_count = $removed.Count
    token_delta = $tokenDelta
  }
}

function Add-MarkdownTable {
  param($Lines, [string]$Title, [object[]]$Items, [string]$Mode)
  $Lines.Add("## $Title") | Out-Null
  $Lines.Add('') | Out-Null
  if (@($Items).Count -eq 0) { $Lines.Add('- None') | Out-Null; $Lines.Add('') | Out-Null; return }
  if ($Mode -eq 'changed') {
    $Lines.Add('| Path | Kind | Token Delta |') | Out-Null
    $Lines.Add('| --- | --- | ---: |') | Out-Null
    foreach ($item in @($Items)) { $Lines.Add("| $($item.path) | $($item.kind) | $($item.token_delta) |") | Out-Null }
  } else {
    $Lines.Add('| Path | Kind | Tokens |') | Out-Null
    $Lines.Add('| --- | --- | ---: |') | Out-Null
    foreach ($item in @($Items)) { $Lines.Add("| $($item.path) | $($item.kind) | $($item.token_estimate) |") | Out-Null }
  }
  $Lines.Add('') | Out-Null
}

$current = New-Snapshot
$baselineExists = Test-Path -LiteralPath $BaselinePath
$baseline = $null
$comparison = [ordered]@{ status = 'baseline-missing'; added = @(); changed = @(); removed = @(); added_count = 0; changed_count = 0; removed_count = 0; token_delta = 0 }

if ($baselineExists) {
  $baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
  $comparison = Compare-Snapshots -Baseline $baseline -Current $current
}

if ($UpdateBaseline) {
  $BaselinePath = ConvertTo-LizardFullPath -Path $BaselinePath
  $parent = Split-Path -Parent $BaselinePath
  if ($parent) { $parent = Initialize-SafeDirectory -Path $parent }
  Set-SafeContent -AuthorizedRoot $parent -Path $BaselinePath -Value ($current | ConvertTo-Json -Depth 8)
  $baseline = $current
  $baselineExists = $true
  $comparison = [ordered]@{ status = 'updated'; added = @(); changed = @(); removed = @(); added_count = 0; changed_count = 0; removed_count = 0; token_delta = 0 }
}

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  layer_root = $LayerRoot
  baseline_path = $BaselinePath
  baseline_exists = $baselineExists
  update_baseline = $UpdateBaseline.IsPresent
  strict = $Strict.IsPresent
  status = [string]$comparison.status
  current = [ordered]@{
    layer_version = $current.layer_version
    artifact_count = $current.artifact_count
    token_estimate = $current.token_estimate
    total_bytes = $current.total_bytes
  }
  baseline = if ($baselineExists) { [ordered]@{ layer_version = $baseline.layer_version; artifact_count = $baseline.artifact_count; token_estimate = $baseline.token_estimate; total_bytes = $baseline.total_bytes } } else { $null }
  summary = [ordered]@{
    added = [int]$comparison.added_count
    changed = [int]$comparison.changed_count
    removed = [int]$comparison.removed_count
    token_delta = [int]$comparison.token_delta
  }
  added = @($comparison.added)
  changed = @($comparison.changed)
  removed = @($comparison.removed)
}

$jsonPath = Join-Path $OutputDir 'drift-report.json'
$mdPath = Join-Path $OutputDir 'drift-report.md'
Set-SafeContent -AuthorizedRoot $OutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 10)

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Lizard Agent Layer Drift Report') | Out-Null
$md.Add('') | Out-Null
$md.Add("Generated: $($report.generated_at)") | Out-Null
$md.Add("Status: $($report.status)") | Out-Null
$md.Add("Baseline: $BaselinePath") | Out-Null
$md.Add('') | Out-Null
$md.Add('## Summary') | Out-Null
$md.Add('') | Out-Null
$md.Add("- Current layer version: $($current.layer_version)") | Out-Null
$md.Add("- Current artifacts: $($current.artifact_count)") | Out-Null
$md.Add("- Current token estimate: $($current.token_estimate)") | Out-Null
if ($baselineExists -and $baseline) {
  $md.Add("- Baseline layer version: $($baseline.layer_version)") | Out-Null
  $md.Add("- Baseline artifacts: $($baseline.artifact_count)") | Out-Null
  $md.Add("- Baseline token estimate: $($baseline.token_estimate)") | Out-Null
}
$md.Add("- Added: $($comparison.added_count)") | Out-Null
$md.Add("- Changed: $($comparison.changed_count)") | Out-Null
$md.Add("- Removed: $($comparison.removed_count)") | Out-Null
$md.Add("- Token delta: $($comparison.token_delta)") | Out-Null
$md.Add('') | Out-Null
Add-MarkdownTable $md 'Added Artifacts' @($comparison.added) 'artifact'
Add-MarkdownTable $md 'Changed Artifacts' @($comparison.changed) 'changed'
Add-MarkdownTable $md 'Removed Artifacts' @($comparison.removed) 'artifact'
Set-SafeContent -AuthorizedRoot $OutputDir -Path $mdPath -Value $md

Write-Host "Drift status: $($report.status)"
Write-Host "Artifacts: $($current.artifact_count), token estimate: $($current.token_estimate)"
Write-Host "Added: $($comparison.added_count), changed: $($comparison.changed_count), removed: $($comparison.removed_count), token delta: $($comparison.token_delta)"
Write-Host "Report: $jsonPath"
Write-Host "Markdown: $mdPath"

if ($Strict) {
  if (-not $baselineExists) { Write-Host 'FAIL Missing drift baseline.'; exit 1 }
  if ($comparison.status -eq 'drift') { Write-Host 'FAIL Drift detected. Run drift-check.ps1 -UpdateBaseline only after reviewing intentional changes.'; exit 1 }
}
