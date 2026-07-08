param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$Profile = "standard",
  [string[]]$Harnesses,
  [switch]$Apply,
  [switch]$Force,
  [switch]$WritePlan,
  [string]$PlanPath
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$ProfilePath = Join-Path $LayerRoot "profiles\$Profile.json"
$VersionPath = Join-Path $LayerRoot "VERSION"
$LayerVersion = if (Test-Path -LiteralPath $VersionPath) { (Get-Content -LiteralPath $VersionPath -Raw).Trim() } else { "0.0.0-dev" }
$ShouldWritePlan = $WritePlan.IsPresent -or -not [string]::IsNullOrWhiteSpace($PlanPath)
$EffectivePlanPath = $null

if (-not (Test-Path -LiteralPath $ProfilePath)) {
  throw "Unknown profile '$Profile'. Expected a JSON file under profiles/."
}

$ProfileDoc = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
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
$SelectedHarnesses = if ($Harnesses -and $Harnesses.Count -gt 0) { Expand-HarnessList $Harnesses } else { Expand-HarnessList $ProfileDoc.harnesses }
if ($SelectedHarnesses.Count -eq 0) { throw "No harnesses selected. Set profile.harnesses or pass -Harnesses." }

function Resolve-PlanReportPath {
  if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
    if ([System.IO.Path]::IsPathRooted($PlanPath)) { return $PlanPath }
    return (Join-Path (Get-Location).Path $PlanPath)
  }
  $stamp = Get-Date -Format 'yyyyMMddHHmmss'
  return (Join-Path $LayerRoot ".tmp\install-plans\lizard-agent-layer-$Profile-$stamp.md")
}

if ($ShouldWritePlan) {
  $EffectivePlanPath = Resolve-PlanReportPath
  $planParent = Split-Path -Parent $EffectivePlanPath
  if ($planParent -and -not (Test-Path -LiteralPath $planParent)) { New-Item -ItemType Directory -Path $planParent -Force | Out-Null }
}

$Mode = if ($Apply) { "APPLY" } else { "PREVIEW" }
$Planned = New-Object System.Collections.Generic.List[string]
$Created = New-Object System.Collections.Generic.List[string]
$Skipped = New-Object System.Collections.Generic.List[string]
$MergeNeeded = New-Object System.Collections.Generic.List[string]
$MergeSuggestions = New-Object System.Collections.Generic.List[object]
$ManagedPaths = New-Object System.Collections.Generic.List[string]
$OwnedPaths = New-Object System.Collections.Generic.List[string]
$InstalledAdapters = New-Object System.Collections.Generic.List[string]

function Add-UniqueListItem {
  param($List, [string]$Value)
  if (-not $List.Contains($Value)) { $List.Add($Value) | Out-Null }
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

function To-RelativeDisplay {
  param([string]$Path)
  if ($Path.StartsWith($TargetRoot)) {
    return $Path.Substring($TargetRoot.Length).TrimStart("\", "/")
  }
  return $Path
}

function New-MergeSuggestion {
  param([string]$Harness, [string]$InstructionPath, [string]$SidecarPath)
  $snippet = @(
    '## lizard-agent-layer',
    '',
    ('Review `{0}` before using this project with the `{1}` harness.' -f $SidecarPath, $Harness),
    'The sidecar contains reusable agent rules, skills, memory, safety, and handoff guidance installed by `lizard-agent-layer`.',
    ('Keep repository-specific rules in `{0}` authoritative; merge sidecar guidance intentionally when it fits this project.' -f $InstructionPath)
  ) -join "`n"
  return [ordered]@{
    harness = $Harness
    instruction_path = $InstructionPath
    sidecar_path = $SidecarPath
    action = "Review the sidecar and paste the suggested block into $InstructionPath when you want the harness to load lizard-agent-layer guidance."
    suggested_block = $snippet
  }
}

function Add-MergeSuggestion {
  param([string]$Harness, [string]$InstructionPath, [string]$SidecarPath)
  foreach ($item in @($MergeSuggestions.ToArray())) {
    if ($item.harness -eq $Harness -and $item.instruction_path -eq $InstructionPath -and $item.sidecar_path -eq $SidecarPath) { return }
  }
  $MergeSuggestions.Add((New-MergeSuggestion -Harness $Harness -InstructionPath $InstructionPath -SidecarPath $SidecarPath)) | Out-Null
}

function Add-MarkdownList {
  param($Lines, [string]$Title, $Items)
  $Lines.Add("## $Title") | Out-Null
  $Lines.Add("") | Out-Null
  if (@($Items).Count -eq 0) {
    $Lines.Add('- None') | Out-Null
  } else {
    foreach ($item in @($Items)) { $Lines.Add(('- `{0}`' -f $item)) | Out-Null }
  }
  $Lines.Add("") | Out-Null
}

function New-InstallPlanMarkdown {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('# lizard-agent-layer install plan') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add(('- Generated: {0}' -f (Get-Date).ToUniversalTime().ToString('o'))) | Out-Null
  $lines.Add(('- Mode: `{0}`' -f $Mode)) | Out-Null
  $lines.Add(('- Target: `{0}`' -f $TargetRoot)) | Out-Null
  $lines.Add(('- Layer version: `{0}`' -f $LayerVersion)) | Out-Null
  $lines.Add(('- Profile: `{0}`' -f $Profile)) | Out-Null
  $lines.Add(('- Risk level: `{0}`' -f $ProfileDoc.riskLevel)) | Out-Null
  $lines.Add(('- Memory mode: `{0}`' -f $ProfileDoc.memoryMode)) | Out-Null
  $lines.Add(('- Harnesses: `{0}`' -f ($SelectedHarnesses -join ', '))) | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('## Summary') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add(('- Planned paths: `{0}`' -f $Planned.Count)) | Out-Null
  $lines.Add(('- Created paths: `{0}`' -f $Created.Count)) | Out-Null
  $lines.Add(('- Skipped existing paths: `{0}`' -f $Skipped.Count)) | Out-Null
  $lines.Add(('- Manual merge items: `{0}`' -f $MergeNeeded.Count)) | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('## Commands') | Out-Null
  $lines.Add('') | Out-Null
  $previewCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath "{0}" -Profile {1} -Harnesses {2}' -f $TargetRoot, $Profile, ($SelectedHarnesses -join ',')
  $applyCommand = "$previewCommand -Apply"
  $lines.Add('Preview:') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('```powershell') | Out-Null
  $lines.Add($previewCommand) | Out-Null
  $lines.Add('```') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('Apply:') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('```powershell') | Out-Null
  $lines.Add($applyCommand) | Out-Null
  $lines.Add('```') | Out-Null
  $lines.Add('') | Out-Null
  Add-MarkdownList $lines 'Skills' @($ProfileDoc.skills)
  Add-MarkdownList $lines 'Planned paths' @($Planned)
  Add-MarkdownList $lines 'Created paths' @($Created)
  Add-MarkdownList $lines 'Skipped existing paths' @($Skipped)
  Add-MarkdownList $lines 'Manual merge needed' @($MergeNeeded)
  $lines.Add('## Merge suggestions') | Out-Null
  $lines.Add('') | Out-Null
  if ($MergeSuggestions.Count -eq 0) {
    $lines.Add('- None') | Out-Null
  } else {
    foreach ($suggestion in @($MergeSuggestions.ToArray())) {
      $lines.Add(('### {0}: {1}' -f $suggestion.harness, $suggestion.instruction_path)) | Out-Null
      $lines.Add('') | Out-Null
      $lines.Add(('- Sidecar: `{0}`' -f $suggestion.sidecar_path)) | Out-Null
      $lines.Add(('- Action: {0}' -f $suggestion.action)) | Out-Null
      $lines.Add('') | Out-Null
      $lines.Add('Suggested block:') | Out-Null
      $lines.Add('') | Out-Null
      $lines.Add('```markdown') | Out-Null
      $lines.Add($suggestion.suggested_block) | Out-Null
      $lines.Add('```') | Out-Null
      $lines.Add('') | Out-Null
    }
  }
  return ($lines -join "`n")
}

function Write-PlanReport {
  if (-not $ShouldWritePlan) { return }
  $markdown = New-InstallPlanMarkdown
  Set-Content -LiteralPath $EffectivePlanPath -Value $markdown -Encoding UTF8
}

function Ensure-Dir {
  param([string]$Path)
  $label = To-RelativeDisplay $Path
  Add-UniqueListItem $ManagedPaths $label
  if (Test-Path -LiteralPath $Path) {
    Add-UniqueListItem $Skipped $label
    return
  }
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    New-Item -ItemType Directory -Path $Path | Out-Null
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  }
}

function Copy-IfMissing {
  param([string]$Source, [string]$Dest)
  if (-not (Test-Path -LiteralPath $Source)) { throw "Missing source file: $Source" }
  $label = To-RelativeDisplay $Dest
  Add-UniqueListItem $ManagedPaths $label
  $parent = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $parent)) {
    if ($Apply) { New-Item -ItemType Directory -Path $parent | Out-Null }
  }
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) {
    Add-UniqueListItem $Skipped $label
    return
  }
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    Copy-Item -LiteralPath $Source -Destination $Dest -Force:$Force
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  }
}

function Copy-SkillPackage {
  param([string]$SkillName, [string]$DestRoot)
  if ($SkillName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid skill name '$SkillName'." }
  $sourceDir = Join-Path $LayerRoot "skills\$SkillName"
  $sourceSkill = Join-Path $sourceDir 'SKILL.md'
  if (-not (Test-Path -LiteralPath $sourceSkill)) { throw "Missing skill package: $SkillName" }
  $destSkillDir = Join-Path $DestRoot $SkillName
  Ensure-Dir $destSkillDir
  Get-ChildItem -LiteralPath $sourceDir -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($sourceDir.Length).TrimStart('\')
    Copy-IfMissing $_.FullName (Join-Path $destSkillDir $relative)
  }
}
function Write-IfMissing {
  param([string]$Dest, [string]$Content)
  $label = To-RelativeDisplay $Dest
  Add-UniqueListItem $ManagedPaths $label
  $parent = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $parent)) {
    if ($Apply) { New-Item -ItemType Directory -Path $parent | Out-Null }
  }
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) {
    Add-UniqueListItem $Skipped $label
    return
  }
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    Set-Content -LiteralPath $Dest -Value $Content -Encoding UTF8
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  }
}

function Copy-InstructionFile {
  param($Adapter, [string]$AdapterDir, [string]$AdapterName)
  $instruction = $Adapter.instruction
  $srcRel = Assert-SafeRelativePath $instruction.src "adapter instruction src"
  $dstRel = Assert-SafeRelativePath $instruction.dst "adapter instruction dst"
  $src = Join-Path $AdapterDir $srcRel
  $dst = Join-Path $TargetRoot $dstRel
  $policy = if ($instruction.mergePolicy) { $instruction.mergePolicy } else { 'sidecar-if-exists' }

  if ((Test-Path -LiteralPath $dst) -and -not $Force -and $policy -ne 'overwrite') {
    $existing = Get-Content -LiteralPath $dst -Raw -ErrorAction SilentlyContinue
    if ($existing -match 'lizard-agent-layer') {
      Add-UniqueListItem $Skipped $dstRel
      Add-UniqueListItem $ManagedPaths $dstRel
      return
    }
    if ($policy -eq 'sidecar-if-exists') {
      $sidecarRel = if ($instruction.sidecar) { Assert-SafeRelativePath $instruction.sidecar "adapter instruction sidecar" } else { "$dstRel.lizard-agent-layer" }
      Copy-IfMissing $src (Join-Path $TargetRoot $sidecarRel)
      Add-UniqueListItem $MergeNeeded "$dstRel exists; review $sidecarRel and merge intentionally."
      Add-MergeSuggestion -Harness $AdapterName -InstructionPath $dstRel -SidecarPath $sidecarRel
      return
    }
    Add-UniqueListItem $Skipped $dstRel
    return
  }

  Copy-IfMissing $src $dst
}

function Install-Adapter {
  param([string]$AdapterName)
  if ($AdapterName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid adapter name '$AdapterName'." }
  $adapterDir = Join-Path $LayerRoot "adapters\$AdapterName"
  $adapterManifestPath = Join-Path $adapterDir 'adapter.json'
  if (-not (Test-Path -LiteralPath $adapterManifestPath)) { throw "Missing adapter manifest for '$AdapterName': $adapterManifestPath" }
  $adapter = Get-Content -LiteralPath $adapterManifestPath -Raw | ConvertFrom-Json
  if ($adapter.name -ne $AdapterName) { throw "Adapter manifest name '$($adapter.name)' does not match folder '$AdapterName'." }

  Add-UniqueListItem $InstalledAdapters $AdapterName
  Copy-InstructionFile $adapter $adapterDir $AdapterName

  foreach ($mirror in @($adapter.skillMirrors)) {
    $mirrorRel = Assert-SafeRelativePath $mirror.dst "skill mirror dst"
    Ensure-Dir (Join-Path $TargetRoot $mirrorRel)
    foreach ($skill in @($ProfileDoc.skills)) {
      Copy-SkillPackage $skill (Join-Path $TargetRoot $mirrorRel)
    }
  }
}

function Write-InstallManifest {
  $manifestPath = Join-Path $TargetRoot ".agent\lizard-agent-layer.install.json"
  $label = To-RelativeDisplay $manifestPath
  Add-UniqueListItem $ManagedPaths $label
  $doc = New-Object System.Collections.Specialized.OrderedDictionary
  $doc['schema_version'] = 2
  $doc['layer'] = "lizard-agent-layer"
  $doc['layer_version'] = $LayerVersion
  $doc['profile'] = $Profile
  $doc['installed_at'] = (Get-Date).ToUniversalTime().ToString("o")
  $doc['target_root'] = $TargetRoot
  $doc['memory_mode'] = $ProfileDoc.memoryMode
  $doc['risk_level'] = $ProfileDoc.riskLevel
  $doc['harnesses'] = @($SelectedHarnesses)
  $doc['model_profiles'] = $ProfileDoc.modelProfiles
  $doc['skills'] = @($ProfileDoc.skills)
  $doc['adapters'] = @($InstalledAdapters.ToArray())
  $doc['managed_paths'] = @($ManagedPaths.ToArray())
  $doc['owned_paths'] = @($OwnedPaths.ToArray())
  $doc['merge_needed'] = @($MergeNeeded.ToArray())
  $doc['merge_suggestions'] = @($MergeSuggestions.ToArray())
  if ($Apply) {
    $doc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  } else {
    Add-UniqueListItem $Planned $label
  }
}

Write-Host "lizard-agent-layer $Mode"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $Profile"
Write-Host "Harnesses: $($SelectedHarnesses -join ', ')"
Write-Host "Version: $LayerVersion"
if ($ShouldWritePlan) { Write-Host "Plan report: $EffectivePlanPath" }
Write-Host ""

Ensure-Dir (Join-Path $TargetRoot ".agent")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\personal")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\semantic")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\working")
Ensure-Dir (Join-Path $TargetRoot ".agent\protocols")
Ensure-Dir (Join-Path $TargetRoot ".agent\skills")

Copy-IfMissing (Join-Path $LayerRoot "templates\agent-gitignore") (Join-Path $TargetRoot ".agent\.gitignore")
Copy-IfMissing $ProfilePath (Join-Path $TargetRoot ".agent\project-profile.json")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\personal\PREFERENCES.md") (Join-Path $TargetRoot ".agent\memory\personal\PREFERENCES.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\semantic\DECISIONS.md") (Join-Path $TargetRoot ".agent\memory\semantic\DECISIONS.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\semantic\LESSONS.md") (Join-Path $TargetRoot ".agent\memory\semantic\LESSONS.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\working\WORKSPACE.md") (Join-Path $TargetRoot ".agent\memory\working\WORKSPACE.md")

foreach ($protocol in @("permissions.md", "memory-policy.md", "secret-handling.md", "release-gates.md", "handoff.md")) {
  Copy-IfMissing (Join-Path $LayerRoot "protocols\$protocol") (Join-Path $TargetRoot ".agent\protocols\$protocol")
}

$indexLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add("# Skill Index") | Out-Null
$indexLines.Add("") | Out-Null
$manifestLines = New-Object System.Collections.Generic.List[string]

foreach ($skill in $ProfileDoc.skills) {
  $source = Join-Path $LayerRoot "skills\$skill\SKILL.md"
  if (-not (Test-Path -LiteralPath $source)) {
    Write-Warning "Profile references missing skill '$skill'."
    continue
  }
  Copy-SkillPackage $skill (Join-Path $TargetRoot ".agent\skills")
  $indexLines.Add("## $skill") | Out-Null
  $indexLines.Add(('Source: `.agent/skills/{0}/SKILL.md`' -f $skill)) | Out-Null
  $indexLines.Add("") | Out-Null
  $manifest = [ordered]@{ name = $skill; source = ".agent/skills/$skill/SKILL.md" }
  $manifestLines.Add(($manifest | ConvertTo-Json -Compress)) | Out-Null
}

Write-IfMissing (Join-Path $TargetRoot ".agent\skills\_index.md") ($indexLines -join "`n")
Write-IfMissing (Join-Path $TargetRoot ".agent\skills\_manifest.jsonl") ($manifestLines -join "`n")

foreach ($adapterName in $SelectedHarnesses) {
  Install-Adapter $adapterName
}

Write-InstallManifest
Write-PlanReport

Write-Host "Summary"
Write-Host "Planned: $($Planned.Count)"
foreach ($item in $Planned) { Write-Host "  + $item" }
Write-Host "Created: $($Created.Count)"
foreach ($item in $Created) { Write-Host "  + $item" }
Write-Host "Skipped existing: $($Skipped.Count)"
foreach ($item in $Skipped) { Write-Host "  ~ $item" }
if ($MergeNeeded.Count -gt 0) {
  Write-Host "Manual merge needed:"
  foreach ($item in $MergeNeeded) { Write-Host "  ! $item" }
}
if ($MergeSuggestions.Count -gt 0) {
  Write-Host "Merge suggestions: $($MergeSuggestions.Count)"
  foreach ($item in @($MergeSuggestions.ToArray())) { Write-Host "  ? $($item.harness): add pointer in $($item.instruction_path) for $($item.sidecar_path)" }
}
if ($ShouldWritePlan) {
  Write-Host ""
  Write-Host "Plan report written: $EffectivePlanPath"
}
if (-not $Apply) {
  Write-Host ""
  Write-Host "Preview only. Re-run with -Apply to write files."
}

