param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$Profile = "standard",
  [string[]]$Harnesses,
  [string]$OutputDir,
  [switch]$Json,
  [switch]$AllowTargetReportWrite
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$ProfilePath = Join-Path $LayerRoot "profiles\$Profile.json"
$VersionPath = Join-Path $LayerRoot "VERSION"
$LayerVersion = if (Test-Path -LiteralPath $VersionPath) { (Get-Content -LiteralPath $VersionPath -Raw).Trim() } else { "0.0.0-dev" }

if (-not (Test-Path -LiteralPath $ProfilePath)) {
  throw "Unknown profile '$Profile'. Expected a JSON file under profiles/."
}

function Expand-HarnessList {
  param($Values)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in ([string]$value -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed -and -not $out.Contains($trimmed)) { $out.Add($trimmed) | Out-Null }
    }
  }
  return @($out)
}

function Normalize-RelPath {
  param([string]$Path)
  return $Path.Replace('/', '\').TrimStart('\')
}

function Assert-SafeRelativePath {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label path is empty." }
  $normalized = Normalize-RelPath $Path
  if ($normalized -match '(^|\\)\.\.($|\\)') { throw "$Label path contains traversal: $Path" }
  if ([System.IO.Path]::IsPathRooted($Path)) { throw "$Label path must be relative: $Path" }
  if ($Path -match '^[A-Za-z]:') { throw "$Label path must not use a drive prefix: $Path" }
  return $normalized
}

function Convert-ToPatchPath {
  param([string]$Path)
  return $Path.Replace('\', '/')
}

function Convert-ToSafeFileName {
  param([string]$Value)
  $safe = $Value -replace '[^A-Za-z0-9._-]+', '-'
  return $safe.Trim('-')
}

function New-MergeBlock {
  param([string]$Harness, [string]$InstructionPath, [string]$SidecarPath)
  return @(
    '## lizard-agent-layer',
    '',
    ('Review `{0}` before using this project with the `{1}` harness.' -f $SidecarPath, $Harness),
    'The sidecar contains reusable agent rules, skills, memory, safety, and handoff guidance installed by `lizard-agent-layer`.',
    ('Keep repository-specific rules in `{0}` authoritative; merge sidecar guidance intentionally when it fits this project.' -f $InstructionPath)
  ) -join "`n"
}

function Split-Lines {
  param([string]$Content)
  if ([string]::IsNullOrEmpty($Content)) { return @() }
  return @($Content -split "`r?`n")
}

function New-AppendPatch {
  param([string]$RelativePath, [string]$ExistingContent, [string]$Block)
  $oldContent = $ExistingContent.TrimEnd("`r", "`n")
  $oldLines = Split-Lines $oldContent
  $blockLines = Split-Lines $Block
  $newCount = $oldLines.Count + $(if ($oldLines.Count -gt 0) { 1 } else { 0 }) + $blockLines.Count
  $oldCount = $oldLines.Count
  $patchPath = Convert-ToPatchPath $RelativePath
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("diff --git a/$patchPath b/$patchPath") | Out-Null
  $lines.Add("--- a/$patchPath") | Out-Null
  $lines.Add("+++ b/$patchPath") | Out-Null
  if ($oldCount -eq 0) {
    $lines.Add("@@ -0,0 +1,$newCount @@") | Out-Null
  } else {
    $lines.Add("@@ -1,$oldCount +1,$newCount @@") | Out-Null
    foreach ($line in $oldLines) { $lines.Add(" $line") | Out-Null }
    $lines.Add('+') | Out-Null
  }
  foreach ($line in $blockLines) { $lines.Add("+$line") | Out-Null }
  return ($lines -join "`n") + "`n"
}

function Add-MarkdownList {
  param($Lines, [string]$Title, $Items)
  $Lines.Add("## $Title") | Out-Null
  $Lines.Add('') | Out-Null
  if (@($Items).Count -eq 0) {
    $Lines.Add('- None') | Out-Null
  } else {
    foreach ($item in @($Items)) { $Lines.Add(('- `{0}`' -f $item)) | Out-Null }
  }
  $Lines.Add('') | Out-Null
}

$ProfileDoc = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$SelectedHarnesses = if ($Harnesses -and $Harnesses.Count -gt 0) { Expand-HarnessList $Harnesses } else { Expand-HarnessList $ProfileDoc.harnesses }
if ($SelectedHarnesses.Count -eq 0) { throw "No harnesses selected. Set profile.harnesses or pass -Harnesses." }

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $stamp = Get-Date -Format 'yyyyMMddHHmmss'
  $targetName = Split-Path -Leaf $TargetRoot
  $OutputDir = Join-Path $LayerRoot ".tmp\merge-suggestions\$targetName-$stamp"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
  $OutputDir = Join-Path (Get-Location).Path $OutputDir
}

if (-not $AllowTargetReportWrite) { Assert-PathOutsideRoot -Path $OutputDir -ExcludedRoot $TargetRoot -Label 'OutputDir' }
$OutputDir = Initialize-SafeDirectory -Path $OutputDir
$results = New-Object System.Collections.Generic.List[object]
$patchFiles = New-Object System.Collections.Generic.List[string]
$blockFiles = New-Object System.Collections.Generic.List[string]

foreach ($harness in $SelectedHarnesses) {
  if ($harness -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid harness name '$harness'." }
  $adapterDir = Join-Path $LayerRoot "adapters\$harness"
  $adapterManifestPath = Join-Path $adapterDir 'adapter.json'
  if (-not (Test-Path -LiteralPath $adapterManifestPath)) { throw "Missing adapter manifest for '$harness'." }
  $adapter = Get-Content -LiteralPath $adapterManifestPath -Raw | ConvertFrom-Json
  $instruction = $adapter.instruction
  $dstRel = Assert-SafeRelativePath $instruction.dst "adapter instruction dst"
  $sidecarRel = if ($instruction.sidecar) { Assert-SafeRelativePath $instruction.sidecar "adapter instruction sidecar" } else { "$dstRel.lizard-agent-layer" }
  $targetInstructionPath = Join-Path $TargetRoot $dstRel

  $status = 'create-by-installer'
  $message = "$dstRel is missing; installer can create it directly."
  $patchFile = $null
  $blockFile = $null
  $block = New-MergeBlock -Harness $harness -InstructionPath $dstRel -SidecarPath $sidecarRel

  if (Test-Path -LiteralPath $targetInstructionPath) {
    $existing = Get-Content -LiteralPath $targetInstructionPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($existing -match 'lizard-agent-layer') {
      $status = 'already-wired'
      $message = "$dstRel already references lizard-agent-layer."
    } else {
      $status = 'merge-needed'
      $message = "$dstRel exists without lizard-agent-layer guidance; review sidecar $sidecarRel and append the suggested block intentionally."
      $baseName = Convert-ToSafeFileName "$harness-$dstRel"
      $patchFile = Join-Path $OutputDir "$baseName.patch"
      $blockFile = Join-Path $OutputDir "$baseName.block.md"
      Set-SafeContent -AuthorizedRoot $OutputDir -Path $patchFile -Value (New-AppendPatch -RelativePath $dstRel -ExistingContent $existing -Block $block)
      Set-SafeContent -AuthorizedRoot $OutputDir -Path $blockFile -Value $block
      $patchFiles.Add($patchFile) | Out-Null
      $blockFiles.Add($blockFile) | Out-Null
    }
  }

  $result = New-Object System.Collections.Specialized.OrderedDictionary
  $result['harness'] = $harness
  $result['instruction_path'] = $dstRel
  $result['sidecar_path'] = $sidecarRel
  $result['status'] = $status
  $result['message'] = $message
  $result['patch_file'] = $patchFile
  $result['block_file'] = $blockFile
  $result['suggested_block'] = $block
  $results.Add($result) | Out-Null
}

$reportPath = Join-Path $OutputDir 'merge-suggestions.md'
$jsonPath = Join-Path $OutputDir 'merge-suggestions.json'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# lizard-agent-layer merge suggestions') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('- Generated: {0}' -f (Get-Date).ToUniversalTime().ToString('o'))) | Out-Null
$lines.Add(('- Target: `{0}`' -f $TargetRoot)) | Out-Null
$lines.Add(('- Layer version: `{0}`' -f $LayerVersion)) | Out-Null
$lines.Add(('- Profile: `{0}`' -f $Profile)) | Out-Null
$lines.Add(('- Harnesses: `{0}`' -f ($SelectedHarnesses -join ', '))) | Out-Null
$lines.Add('') | Out-Null
$mergeNeeded = @($results.ToArray() | Where-Object { $_['status'] -eq 'merge-needed' })
$alreadyWired = @($results.ToArray() | Where-Object { $_['status'] -eq 'already-wired' })
$createdByInstaller = @($results.ToArray() | Where-Object { $_['status'] -eq 'create-by-installer' })
$lines.Add('## Summary') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('- Merge needed: `{0}`' -f $mergeNeeded.Count)) | Out-Null
$lines.Add(('- Already wired: `{0}`' -f $alreadyWired.Count)) | Out-Null
$lines.Add(('- Create by installer: `{0}`' -f $createdByInstaller.Count)) | Out-Null
$lines.Add('') | Out-Null
foreach ($result in @($results.ToArray())) {
  $lines.Add(('## {0}: {1}' -f $result['harness'], $result['instruction_path'])) | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add(('- Status: `{0}`' -f $result['status'])) | Out-Null
  $lines.Add(('- Sidecar: `{0}`' -f $result['sidecar_path'])) | Out-Null
  $lines.Add(('- Message: {0}' -f $result['message'])) | Out-Null
  if ($result['patch_file']) { $lines.Add(('- Patch: `{0}`' -f $result['patch_file'])) | Out-Null }
  if ($result['block_file']) { $lines.Add(('- Block: `{0}`' -f $result['block_file'])) | Out-Null }
  if ($result['status'] -eq 'merge-needed') {
    $lines.Add('') | Out-Null
    $lines.Add('Suggested block:') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('```markdown') | Out-Null
    $lines.Add($result['suggested_block']) | Out-Null
    $lines.Add('```') | Out-Null
  }
  $lines.Add('') | Out-Null
}
Add-MarkdownList $lines 'Patch files' @($patchFiles.ToArray())
Add-MarkdownList $lines 'Block files' @($blockFiles.ToArray())
Set-SafeContent -AuthorizedRoot $OutputDir -Path $reportPath -Value ($lines -join "`n")

$jsonDoc = New-Object System.Collections.Specialized.OrderedDictionary
$jsonDoc['generated_at'] = (Get-Date).ToUniversalTime().ToString('o')
$jsonDoc['target'] = $TargetRoot
$jsonDoc['layer_version'] = $LayerVersion
$jsonDoc['profile'] = $Profile
$jsonDoc['harnesses'] = @($SelectedHarnesses)
$jsonDoc['output_dir'] = $OutputDir
$jsonDoc['report_path'] = $reportPath
$jsonDoc['patch_files'] = @($patchFiles.ToArray())
$jsonDoc['block_files'] = @($blockFiles.ToArray())
$jsonDoc['results'] = @($results.ToArray())
Set-SafeContent -AuthorizedRoot $OutputDir -Path $jsonPath -Value ($jsonDoc | ConvertTo-Json -Depth 10)

if ($Json) {
  $jsonDoc | ConvertTo-Json -Depth 10
  exit 0
}

Write-Host "lizard-agent-layer merge suggestions"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $Profile"
Write-Host "Harnesses: $($SelectedHarnesses -join ', ')"
Write-Host "Output: $OutputDir"
Write-Host "Report: $reportPath"
Write-Host "JSON: $jsonPath"
Write-Host "Merge needed: $($mergeNeeded.Count)"
Write-Host "Already wired: $($alreadyWired.Count)"
Write-Host "Create by installer: $($createdByInstaller.Count)"
foreach ($result in @($results.ToArray())) {
  Write-Host "  $($result['status']) $($result['harness']) -> $($result['instruction_path'])"
}
